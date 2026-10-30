// STAGE 2B (disposable copy): per-destination forwarding transport selection.
// Only the online (Internet) transport is implemented. A LAN destination is
// not deliverable for new jobs and must never be sent over the Internet.
// Offline: requests are answered locally, USSD/SMS channels refuse and record.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/forwarding_delivery_retry.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/stage0_harness.dart';
import 'support/stage1_fakes.dart';
import 'support/stage2b_fakes.dart';

const _receipt = 'SJK1ABCD23';
const _sms = '$_receipt Confirmed. Ksh100.00 received from JOHN DOE '
    '0712345678. SYNTHETIC STAGE 2B TEST MESSAGE ONLY.';

const _phoneB = ForwardingDestination(deviceId: 'device-b', deviceName: 'Phone B');
const _phoneC = ForwardingDestination(deviceId: 'device-c', deviceName: 'Phone C');

Map<String, Object?> _deviceRow(String name, String id, {int paused = 0}) => {
      'device_name': name,
      'device_id': id,
      'owner_email': 'owner@example.test',
      'amounts_to_forward': '[100]',
      'paused': paused,
    };

void main() {
  group('preference parsing (pure)', () {
    test('only an exact "lan" selects LAN; everything else is online', () {
      expect(parseForwardingTransportPreference('lan'),
          ForwardingTransportKind.lan);
      for (final value in <Object?>[
        null,
        '',
        'online',
        'LAN',
        ' lan ',
        'wifi',
        'lan;drop',
        1,
        true,
        const {'transport': 'lan'},
        const ['lan'],
      ]) {
        expect(parseForwardingTransportPreference(value),
            ForwardingTransportKind.online,
            reason: '$value');
      }
    });

    test('destination identity comes from the device row; missing fields are '
        'empty, not invented', () {
      final d = ForwardingDestination.fromDeviceRow(
          {'device_id': 'device-c', 'device_name': 'Phone C'});
      expect(d.deviceId, 'device-c');
      expect(d.deviceName, 'Phone C');
      final legacy = ForwardingDestination.fromDeviceRow({'id': 3});
      expect(legacy.deviceId, '');
      expect(legacy.deviceName, '');
    });
  });

  group('resolver', () {
    test('default source: every destination (legacy, no preference) is '
        'online and deliverable', () async {
      // Nothing stored (the persisted default is covered by
      // stage2b_transport_persistence_test.dart).
      final resolver =
          ForwardingTransportResolver(MapForwardingTransportPreferences());
      for (final d in [_phoneB, _phoneC]) {
        final decision = await resolver.resolve(d);
        expect(decision.selected, ForwardingTransportKind.online);
        expect(decision.deliverable, isTrue);
      }
    });

    test('explicit online is deliverable; explicit LAN is selected and not '
        'deliverable', () async {
      final resolver = ForwardingTransportResolver(
          MapForwardingTransportPreferences(
              {'device-b': 'online', 'device-c': 'lan'}));
      final b = await resolver.resolve(_phoneB);
      final c = await resolver.resolve(_phoneC);
      expect(b.selected, ForwardingTransportKind.online);
      expect(b.deliverable, isTrue);
      expect(c.selected, ForwardingTransportKind.lan,
          reason: 'LAN is reported as LAN, not reinterpreted as online');
      expect(c.deliverable, isFalse);
      expect(c.label, 'lan');
    });

    test('destinations are independent; changing one leaves the other', () async {
      final store = MapForwardingTransportPreferences(
          {'device-b': 'online', 'device-c': 'lan'});
      final resolver = ForwardingTransportResolver(store);
      store.byDeviceId['device-b'] = 'lan';
      expect((await resolver.resolve(_phoneB)).selected,
          ForwardingTransportKind.lan);
      expect((await resolver.resolve(_phoneC)).selected,
          ForwardingTransportKind.lan);
      store.byDeviceId['device-b'] = 'online';
      expect((await resolver.resolve(_phoneB)).selected,
          ForwardingTransportKind.online);
      expect((await resolver.resolve(_phoneC)).selected,
          ForwardingTransportKind.lan, reason: 'C unchanged by B updates');
      expect(store.byDeviceId, {'device-b': 'online', 'device-c': 'lan'});
    });

    test('an unreadable preference is unresolved and NOT deliverable (never '
        'assumed online)', () async {
      final decision =
          await ForwardingTransportResolver(FailingForwardingTransportPreferences())
              .resolve(_phoneB);
      expect(decision.selected, isNull);
      expect(decision.deliverable, isFalse);
      expect(decision.label, 'unresolved');
    });
  });

  group('routing gates (controller)', () {
    final h = Stage0Harness();

    setUpAll(Stage0Harness.setUpAllOnce);
    tearDownAll(Stage0Harness.tearDownAllOnce);
    tearDown(h.tearDown);

    Future<void> phoneA(List<Map<String, Object?>> devices) async {
      await h.setUp(prefs: {
        'user_device_name': 'Phone A',
        'jwt_token': 'stage2b-test-jwt',
      });
      final db = await h.db;
      for (final d in devices) {
        await db.insert('forwardingDevices', d);
      }
    }

    Future<int> unrelatedRow() async => (await h.db).insert('transactions', {
          'transactionId': 'UNRELATED01',
          'status': TransactionStatuses.forwardedPending,
          'forwardingJobId': 'fwd_UNRELATED01_1761650000000',
          'forwardingSenderDeviceName': 'Phone A',
          'forwardingRecipientDeviceName': 'Phone B',
          'canRetry': 1,
          'timeStamp': 1761650000000,
        });

    Future<List<Map<String, Object?>>> table(String name) async =>
        (await h.db).query(name, orderBy: 'rowid');

    test('LAN-only destination: no Internet request, no job, no state change',
        () async {
      await phoneA([_deviceRow('Phone C', 'device-c')]);
      final unrelatedId = await unrelatedRow();
      final unrelatedBefore = await table('transactions');
      final transport = RecordingForwardingTransport();
      final prefs = MapForwardingTransportPreferences({'device-c': 'lan'});
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransport: transport,
        forwardingTransportPreferences: prefs,
      );

      final result = await h.capture(() => controller.forwardIfNeeded(
          100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));

      expect(result.state, ForwardingAttemptState.configuredButUnavailable,
          reason: 'existing "do not deliver" result; callers persist '
              'error/canRetry and never dial locally');
      expect(transport.submissions, isEmpty, reason: 'no Internet submission');
      expect(h.requests, isEmpty, reason: 'not even the pingDevice GET');
      expect(prefs.lookups.map((d) => d.deviceId), ['device-c']);
      expect(await table('transactions'), unrelatedBefore,
          reason: 'no job row created; unrelated row untouched');
      expect(unrelatedBefore.single['id'], unrelatedId);
      expect(await table('forwardedSmsJobs'), isEmpty);
      expect(await table('forwardingDeliveryRetries'), isEmpty);
      expect(await table('forwardingSubmissionClaims'), isEmpty);
      expect(
          (await SharedPreferences.getInstance())
              .getInt('online_forwarding_index_100'),
          isNull);
      h.expectNoExternalEffects();
    });

    test('an unreadable preference blocks new jobs the same way', () async {
      await phoneA([_deviceRow('Phone B', 'device-b')]);
      final transport = RecordingForwardingTransport();
      final result = await h.capture(() => TransactionController(
            sqliteService: SQLiteService(),
            forwardingTransport: transport,
            forwardingTransportPreferences:
                FailingForwardingTransportPreferences(),
          ).forwardIfNeeded(
              100, _sms, _sms, _receipt, 712345678, 'JOHN DOE', false));
      expect(result.state, ForwardingAttemptState.configuredButUnavailable);
      expect(transport.submissions, isEmpty);
      expect(h.requests, isEmpty);
      h.expectNoExternalEffects();
    });

    test('automatic retry of a row for a LAN-only route: stays error/retryable, '
        'not confirmed, no USSD, no Internet', () async {
      await phoneA([_deviceRow('Phone C', 'device-c')]);
      final id = await (await h.db).insert('transactions', {
        'transactionId': _receipt,
        'initialMessage': _sms,
        'amount': 100,
        'number': 712345678,
        'source': 'JOHN DOE',
        'status': TransactionStatuses.error,
        'canRetry': 1,
        // As _persistUnavailableForwardingTransaction -> dontProcess writes it.
        'ussdDialed': '',
        'simSubId': -1,
        'smsDate': '2026-10-28',
        'smsTime': '12:00',
        'ussdReply': 'Paired-device forwarding is configured but currently '
            'unavailable. Will retry forwarding later.',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      final transport = RecordingForwardingTransport();
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransport: transport,
        forwardingTransportPreferences:
            MapForwardingTransportPreferences({'device-c': 'lan'}),
      );
      await h.capture(() => controller.redoTransaction(id, '', -1, 1, ''));

      final row = (await (await h.db)
              .query('transactions', where: 'id = ?', whereArgs: [id]))
          .single;
      expect(row['status'], TransactionStatuses.error);
      expect(row['canRetry'], 1);
      expect(row['forwardingJobId'], isNull);
      expect(
          row['status'],
          isNot(anyOf(TransactionStatuses.forwardedConfirmed,
              TransactionStatuses.doneConfirmed)));
      expect(transport.submissions, isEmpty);
      expect(h.requests, isEmpty);
      expect(h.ussdCalls, isEmpty, reason: 'no local purchase');
      h.expectNoExternalEffects();
    });

    test('forwardToAllAvenues sends only to the online destination', () async {
      await phoneA([
        _deviceRow('Phone B', 'device-b'),
        _deviceRow('Phone C', 'device-c'),
      ]);
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransportPreferences:
            MapForwardingTransportPreferences({'device-c': 'lan'}),
      );
      await h.capture(() => controller.forwardToAllAvenues(_sms));

      expect(h.backendPosts, hasLength(1));
      expect(h.backendPosts.single.json['recipientDeviceName'], 'Phone B');
      expect(h.backendPosts.single.data['type'], 'forwarded_sms');
      final rows = await table('transactions');
      expect(rows.map((r) => r['forwardingRecipientDeviceName']), ['Phone B'],
          reason: 'no job is created for the LAN destination');
      expect(
          h.requests.where((r) => r.method == 'GET'), hasLength(1),
          reason: 'only the online destination is pinged');
      h.expectNoExternalEffects();
    });

    test('forwardToAllAvenues with only a LAN destination sends nothing',
        () async {
      await phoneA([_deviceRow('Phone C', 'device-c')]);
      final controller = TransactionController(
        sqliteService: SQLiteService(),
        forwardingTransportPreferences:
            MapForwardingTransportPreferences({'device-c': 'lan'}),
      );
      await h.capture(() => controller.forwardToAllAvenues(_sms));
      expect(h.requests, isEmpty);
      expect(await table('transactions'), isEmpty);
      h.expectNoExternalEffects();
    });

    group('new alternative job (via retryAll, stopped before purchase '
        'retries by offers_might_have_changed)', () {
      Future<int> seedAlternative(String target) async {
        await h.setUp(prefs: {
          'user_device_name': 'Phone B',
          'jwt_token': 'stage2b-test-jwt',
          'offers_might_have_changed': true,
        });
        final db = await h.db;
        await db.insert('forwardingDevices', _deviceRow(target, 'device-c'));
        final offerId = await db.insert('ussdCodes', {'amount': 50});
        await db.insert('ussdCodeVariants', {
          'ussdCodeId': offerId,
          'code': '*180*1*N#',
          'alternativeUssdCode': '*180*5*N#',
          'runAltOn': target,
          'altDelaySeconds': 0,
        });
        return db.insert('transactions', {
          'transactionId': 'ALT1ABCD23',
          'initialMessage': 'ALT1ABCD23 Confirmed. Ksh50.00 received from '
              'SYNTHETIC TEST 0712345678.',
          'amount': 50,
          'number': 712345678,
          'status': TransactionStatuses.secondAttempt,
          'firstFailedTimeStamp':
              DateTime.now().subtract(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
        });
      }

      test('control: an online target is queued and requested', () async {
        final id = await seedAlternative('Phone C');
        await h.capture(() => TransactionController(
              sqliteService: SQLiteService(),
              forwardingTransportPreferences:
                  MapForwardingTransportPreferences(),
            ).retryAll(true));
        final row = (await (await h.db)
                .query('transactions', where: 'id = ?', whereArgs: [id]))
            .single;
        expect(row['status'], TransactionStatuses.alternativeDeliveryPending);
        expect(h.backendPosts.where((p) => p.data['type'] == 'process_alt_request'),
            hasLength(1));
        h.expectNoExternalEffects();
      });

      test('a LAN target is queued over LAN; nothing goes online', () async {
        final id = await seedAlternative('Phone C');
        await h.capture(() => TransactionController(
              sqliteService: SQLiteService(),
              forwardingTransportPreferences:
                  MapForwardingTransportPreferences({'device-c': 'lan'}),
            ).retryAll(true));
        final row = (await (await h.db)
                .query('transactions', where: 'id = ?', whereArgs: [id]))
            .single;
        expect(row['status'], TransactionStatuses.alternativeDeliveryPending);
        expect(row['forwardingTransport'], 'lan');
        expect(row['forwardingJobId'], isNotNull);
        expect(h.backendPosts, isEmpty);
        expect(h.ussdCalls, isEmpty);
        h.expectNoExternalEffects();
      });
    });

    test('Rule E: an in-flight job keeps its transport after the destination '
        'is switched to LAN (delivery retry still uses the Internet job)',
        () async {
      await phoneA([_deviceRow('Phone C', 'device-c')]);
      const jobId = 'fwd_${_receipt}_1761650000000';
      final db = await h.db;
      final rowId = await db.insert('transactions', {
        'initialMessage': _sms,
        'transactionId': _receipt,
        'status': TransactionStatuses.forwardedPending,
        'forwardingJobId': jobId,
        'forwardingSenderDeviceName': 'Phone A',
        'forwardingRecipientDeviceName': 'Phone C',
        // LAN integration: every in-flight Online job now persists its
        // transport (migration backfill or creation path).
        'forwardingTransport': 'online',
        'awaitingTopUp': 0,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
      });
      await db.insert('forwardingDeliveryRetries', {
        'forwardingJobId': jobId,
        'attempt': 0,
        'nextAttemptAt': DateTime.now().millisecondsSinceEpoch - 1000,
        'acknowledged': 0,
      });
      final transport = RecordingForwardingTransport();
      final prefs = MapForwardingTransportPreferences({'device-c': 'lan'});
      await h.capture(() async {
        TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransport: transport,
          forwardingTransportPreferences: prefs,
        );
      });
      expect(transport.submissions, hasLength(1));
      expect(
        transport.submissions.single.request,
        buildForwardedSmsRequestPayload(
          message: _sms,
          messageId: _receipt,
          transactionRowId: rowId,
          forwardingJobId: jobId,
          senderDeviceName: 'Phone A',
          recipientDeviceName: 'Phone C',
        ),
      );
      expect(prefs.lookups, isEmpty,
          reason: 'in-flight jobs are not re-resolved');
      h.expectNoExternalEffects();
    });
  });
}
