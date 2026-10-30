// STAGE 2B persistence fix, Step A (disposable copy): an alternative request
// whose runAltOn target exists only in whitelistedDevices (no
// forwardingDevices row) is routed online again, as before preferences were
// persisted. Missing forwarding device records, unreadable stores and
// ambiguous identities still fail closed. Controller tests use the Stage 0
// harness: offline, USSD/SMS refused and recorded, HTTP answered locally.
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/stage0_harness.dart';
import 'support/stage2b_fakes.dart';

const _receipt = 'ALT1ABCD23';
const _sms = '$_receipt Confirmed. Ksh50.00 received from '
    'SYNTHETIC TEST 0712345678.';

Map<String, Object?> _device(String name, String id) => {
      'device_name': name,
      'device_id': id,
      'owner_email': 'owner@example.test',
    };

/// Deletes the target's forwarding device record after the controller has
/// found it and before the preference is read.
class _RecordDisappearsPreferences implements ForwardingTransportPreferences {
  final Stage0Harness h;
  final List<ForwardingDestination> lookups = [];
  _RecordDisappearsPreferences(this.h);

  @override
  Future<Object?> storedPreferenceFor(ForwardingDestination destination) async {
    lookups.add(destination);
    await (await h.db).delete('forwardingDevices');
    return SQLiteForwardingTransportPreferences()
        .storedPreferenceFor(destination);
  }
}

void main() {
  final h = Stage0Harness();
  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  /// Phone B holds a secondAttempt transaction whose offer runs its
  /// alternative on Phone C. retryAll stops before purchase retries
  /// (offers_might_have_changed), so only the alternative path runs.
  Future<int> seed({
    List<Map<String, Object?>> whitelisted = const [],
    List<Map<String, Object?>> forwarding = const [],
    int altDelaySeconds = 0,
  }) async {
    await h.setUp(prefs: {
      'user_device_name': 'Phone B',
      'jwt_token': 'stepa-test-jwt',
      'offers_might_have_changed': true,
    });
    final db = await h.db;
    for (final row in whitelisted) {
      await db.insert('whitelistedDevices', row);
    }
    for (final row in forwarding) {
      await db.insert('forwardingDevices', row);
    }
    final offerId = await db.insert('ussdCodes', {'amount': 50});
    await db.insert('ussdCodeVariants', {
      'ussdCodeId': offerId,
      'code': '*180*1*N#',
      'alternativeUssdCode': '*180*5*N#',
      'runAltOn': 'Phone C',
      'altDelaySeconds': altDelaySeconds,
    });
    return db.insert('transactions', {
      'transactionId': _receipt,
      'initialMessage': _sms,
      'amount': 50,
      'number': 712345678,
      'status': TransactionStatuses.secondAttempt,
      'firstFailedTimeStamp': DateTime.now()
          .subtract(const Duration(minutes: 5))
          .millisecondsSinceEpoch,
      'timeStamp': DateTime.now().millisecondsSinceEpoch,
    });
  }

  Future<Map<String, Object?>> runAlternative(
    int id, [
    ForwardingTransportPreferences? preferences,
  ]) async {
    await h.capture(() => TransactionController(
          sqliteService: SQLiteService(),
          forwardingTransportPreferences: preferences,
        ).retryAll(true));
    return (await (await h.db)
            .query('transactions', where: 'id = ?', whereArgs: [id]))
        .single;
  }

  List<CapturedRequest> altPosts() => h.backendPosts
      .where((p) => p.data['type'] == 'process_alt_request')
      .toList();

  void expectNotQueued(Map<String, Object?> row) {
    expect(row['status'], TransactionStatuses.secondAttempt);
    expect(row['forwardingJobId'], isNull);
    expect(row['forwardingRecipientDeviceName'], isNull);
    expect(row['alternativeQueueState'], isNull);
    expect(h.requests, isEmpty, reason: 'no Internet fallback');
    expect(h.ussdCalls, isEmpty, reason: 'no local USSD fallback');
  }

  /// Everything a queued alternative leaves behind, with the generated job
  /// ID masked: the stored row fields and the one request (URL, headers,
  /// body).
  Map<String, Object?> queuedOutcome(Map<String, Object?> row) {
    final post = altPosts().single;
    final jobId = row['forwardingJobId'] as String;
    String mask(String s) => s.replaceAll(jobId, '<job>');
    return {
      'requests': h.requests.length,
      'status': row['status'],
      'alternativeQueueState': row['alternativeQueueState'],
      'forwardingRecipientDeviceName': row['forwardingRecipientDeviceName'],
      'alternativeRequestSenderDeviceName':
          row['alternativeRequestSenderDeviceName'],
      'alternativeRequestCode': row['alternativeRequestCode'],
      'alternativeRequestIsAdvanced': row['alternativeRequestIsAdvanced'],
      'ussdReply': row['ussdReply'],
      'url': '${post.url}',
      'headers': post.headers,
      'body': mask(post.rawBody),
    };
  }

  group('alternative request to a whitelist-only target', () {
    test('1: is queued and requested online exactly as before persistence',
        () async {
      // Before persistence (Stage 2B: nothing stored).
      var id = await seed(whitelisted: [_device('Phone C', 'device-c')]);
      var row = await runAlternative(id, MapForwardingTransportPreferences());
      final legacy = queuedOutcome(row);
      h.expectNoExternalEffects();

      // With the default persisted store.
      id = await seed(whitelisted: [_device('Phone C', 'device-c')]);
      row = await runAlternative(id);
      expect(row['status'], TransactionStatuses.alternativeDeliveryPending);
      expect(row['alternativeQueueState'], 'active');
      expect(row['forwardingRecipientDeviceName'], 'Phone C');
      final post = altPosts().single;
      expect(post.json['recipientDeviceName'], 'Phone C');
      expect(post.data['type'], 'process_alt_request');
      expect(post.data['transactionId'], '$id');
      expect(post.data['forwardingJobId'], row['forwardingJobId']);
      expect(post.data['senderDeviceName'], 'Phone B');
      expect(post.data['recipientDeviceName'], 'Phone C');
      expect(post.data['smsMessage'], _sms);
      expect(queuedOutcome(row), legacy);
      h.expectNoExternalEffects();
    });

    test('2: a forwarding device with an online or legacy (NULL) preference '
        'is requested exactly like a whitelist-only target', () async {
      var id = await seed(whitelisted: [_device('Phone C', 'device-c')]);
      final whitelistOnly = queuedOutcome(await runAlternative(id));

      for (final stored in ['online', null]) {
        id = await seed(forwarding: [
          {..._device('Phone C', 'device-c'), 'forwarding_transport': stored},
        ]);
        expect(queuedOutcome(await runAlternative(id)), whitelistOnly,
            reason: 'stored preference $stored');
        h.expectNoExternalEffects();
      }
    });

    void expectQueuedOverLan(Map<String, Object?> row) {
      expect(row['status'], TransactionStatuses.alternativeDeliveryPending);
      expect(row['forwardingTransport'], 'lan');
      expect(row['forwardingRecipientDeviceName'], 'Phone C');
      expect(row['alternativeRequestSenderDeviceName'], 'Phone B');
      expect(row['forwardingJobId'], isNotNull);
      // No LAN service in this isolate: the request is not delivered and
      // waits for the next attempt; it never falls back to the Internet.
      expect(h.requests, isEmpty, reason: 'no Internet fallback');
      expect(h.ussdCalls, isEmpty, reason: 'no local USSD fallback');
    }

    test('3: a forwarding device with a LAN preference is queued over LAN '
        'only, even when it is also whitelisted', () async {
      final id = await seed(
        whitelisted: [_device('Phone C', 'device-c')],
        forwarding: [
          {..._device('Phone C', 'device-c'), 'forwarding_transport': 'lan'},
        ],
      );
      expectQueuedOverLan(await runAlternative(id));
      h.expectNoExternalEffects();
    });

    test('3b: a trusted LAN pairing with no Online record is queued over LAN '
        'only; no Online account is needed', () async {
      final id = await seed();
      await LanPeerStore().trust(
        publicKey: List<int>.generate(32, (i) => i + 1),
        deviceName: 'Phone C',
        deviceId: '',
      );
      expectQueuedOverLan(await runAlternative(id));
      h.expectNoExternalEffects();
    });

    test('3c: a revoked LAN pairing with no Online record is not queued',
        () async {
      final id = await seed();
      final peer = await LanPeerStore().trust(
        publicKey: List<int>.generate(32, (i) => i + 1),
        deviceName: 'Phone C',
        deviceId: '',
      );
      await LanPeerStore().revoke(peer.fingerprint);
      expectNotQueued(await runAlternative(id));
      h.expectNoExternalEffects();
    });

    test('4: a forwarding device record that disappears is not reinterpreted '
        'as a whitelist-only target', () async {
      final id = await seed(
        whitelisted: [_device('Phone C', 'device-c')],
        forwarding: [_device('Phone C', 'device-c')],
      );
      final preferences = _RecordDisappearsPreferences(h);
      expectNotQueued(await runAlternative(id, preferences));
      expect(preferences.lookups.single.whitelistOnly, isFalse);
      h.expectNoExternalEffects();
    });

    test('5: an unreadable preference store fails closed', () async {
      final id = await seed(whitelisted: [_device('Phone C', 'device-c')]);
      expectNotQueued(
          await runAlternative(id, FailingForwardingTransportPreferences()));
      h.expectNoExternalEffects();
    });

    test('6a: a whitelisted name shared by two devices fails closed', () async {
      final id = await seed(whitelisted: [
        _device('Phone C', 'device-c'),
        _device('Phone C', 'device-c2'),
      ]);
      expectNotQueued(await runAlternative(id));
      h.expectNoExternalEffects();
    });

    test('6b: a whitelisted device whose ID has a forwarding device record '
        'under another name (possibly LAN) fails closed', () async {
      final id = await seed(
        whitelisted: [_device('Phone C', 'device-c')],
        forwarding: [
          {..._device('Phone C old', 'device-c'), 'forwarding_transport': 'lan'},
        ],
      );
      expectNotQueued(await runAlternative(id));
      h.expectNoExternalEffects();
    });

    test('6c: a whitelisted device without an ID fails closed', () async {
      final id = await seed(whitelisted: [_device('Phone C', '')]);
      expectNotQueued(await runAlternative(id));
      h.expectNoExternalEffects();
    });

    test('7a: the alternative delay still applies; nothing is resolved or '
        'sent before it elapses', () async {
      final id = await seed(
        whitelisted: [_device('Phone C', 'device-c')],
        altDelaySeconds: 3600,
      );
      final preferences = MapForwardingTransportPreferences();
      final row = await runAlternative(id, preferences);
      expectNotQueued(row);
      expect(row['alternativeExecuteAt'], isNotNull);
      expect(preferences.lookups, isEmpty);
      h.expectNoExternalEffects();
    });

    test('7b: a target in neither table is still skipped without a lookup',
        () async {
      final id = await seed();
      final preferences = MapForwardingTransportPreferences();
      expectNotQueued(await runAlternative(id, preferences));
      expect(preferences.lookups, isEmpty);
      h.expectNoExternalEffects();
    });

    test('7c: the controller marks only the whitelist fallback as '
        'whitelist-only', () async {
      for (final forwarding in [true, false]) {
        final id = await seed(
          whitelisted: [_device('Phone C', 'device-c')],
          forwarding: [if (forwarding) _device('Phone C', 'device-c')],
        );
        final preferences = MapForwardingTransportPreferences();
        await runAlternative(id, preferences);
        final lookup = preferences.lookups.single;
        expect(lookup.whitelistOnly, !forwarding);
        expect(lookup.deviceId, 'device-c');
        expect(lookup.deviceName, 'Phone C');
        h.expectNoExternalEffects();
      }
    });
  });

  group('store: whitelist-only destinations', () {
    late Database db;
    late ForwardingTransportResolver resolver;

    setUp(() async {
      db = await databaseFactoryFfiNoIsolate.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      );
      // The columns the queries use; whitelistedDevices as onCreate makes it
      // (device_name not UNIQUE).
      await db.execute('CREATE TABLE forwardingDevices (id INTEGER PRIMARY '
          'KEY, device_name TEXT NOT NULL UNIQUE, device_id TEXT NOT NULL, '
          'owner_email TEXT NOT NULL, forwarding_transport TEXT)');
      await db.execute('CREATE TABLE whitelistedDevices (id INTEGER PRIMARY '
          'KEY, device_name TEXT NOT NULL, device_id TEXT NOT NULL, '
          'owner_email TEXT NOT NULL)');
      resolver = ForwardingTransportResolver(SQLiteForwardingTransportPreferences(
          SQLiteService(databaseOverride: db)));
    });
    tearDown(() => db.close());

    const whitelistedC = ForwardingDestination(
        deviceId: 'device-c', deviceName: 'Phone C', whitelistOnly: true);
    const forwardingC =
        ForwardingDestination(deviceId: 'device-c', deviceName: 'Phone C');

    Future<String> label(ForwardingDestination d) async =>
        (await resolver.resolve(d)).label;

    test('a confirmed whitelist-only destination resolves online', () async {
      await db.insert('whitelistedDevices', _device('Phone C', 'device-c'));
      expect(await label(whitelistedC), 'online');
    });

    test('a forwarding destination without its record is still unresolved',
        () async {
      await db.insert('whitelistedDevices', _device('Phone C', 'device-c'));
      expect(await label(forwardingC), 'unresolved');
    });

    test('whitelist-only is rejected once a forwarding record exists '
        '(by name or by ID)', () async {
      await db.insert('whitelistedDevices', _device('Phone C', 'device-c'));
      await db.insert('forwardingDevices',
          {..._device('Phone C', 'device-c'), 'forwarding_transport': 'lan'});
      expect(await label(whitelistedC), 'unresolved');
      expect(await label(forwardingC), 'lan');
      await db.update('forwardingDevices', {'device_name': 'Phone C old'});
      expect(await label(whitelistedC), 'unresolved');
      await db.update('forwardingDevices',
          {'device_name': 'Phone C', 'device_id': 'device-other'});
      expect(await label(whitelistedC), 'unresolved');
    });

    test('a missing, duplicated, mismatched or blank whitelist entry is '
        'unresolved', () async {
      expect(await label(whitelistedC), 'unresolved', reason: 'missing');
      await db.insert('whitelistedDevices', _device('Phone C', 'device-x'));
      expect(await label(whitelistedC), 'unresolved', reason: 'other ID');
      await db.insert('whitelistedDevices', _device('Phone C', 'device-c'));
      expect(await label(whitelistedC), 'unresolved', reason: 'duplicate');
      await db.insert('whitelistedDevices', _device('Phone D', ''));
      expect(
          await label(const ForwardingDestination(
              deviceId: '', deviceName: 'Phone D', whitelistOnly: true)),
          'unresolved',
          reason: 'blank ID');
    });

    test('a database failure is unresolved', () async {
      await db.insert('whitelistedDevices', _device('Phone C', 'device-c'));
      await db.execute('DROP TABLE forwardingDevices');
      expect(await label(whitelistedC), 'unresolved');
    });
  });
}
