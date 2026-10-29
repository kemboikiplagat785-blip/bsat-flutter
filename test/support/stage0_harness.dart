// STAGE 0 test harness (disposable copy only; not part of the repository).
//
// Isolation provided for characterization tests of HEAD behaviour:
// * SQLite: sqflite FFI without isolates, default database redirected to a
//   fresh temporary directory per test (SQLiteService's static database is
//   closed and deleted between tests).
// * SharedPreferences: in-memory mock values.
// * Telephony (SMS) and USSD platform channels: recorded; every SMS send or
//   USSD dial is refused and recorded so tests can assert none happened.
// * HTTP: package:http calls are captured by a MockClient via
//   http.runWithClient; anything else that creates an HttpClient is refused.
// * TransactionController's static 15 s periodic timer is created once inside
//   a FakeAsync zone, so it never fires during these tests.
import 'dart:convert';
import 'dart:io';

import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const telephonyChannel =
    MethodChannel('plugins.shounakmulay.com/foreground_sms_channel');
const ussdChannel = MethodChannel('com.bsat.app');

/// One captured outgoing HTTP request.
class CapturedRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String rawBody;

  CapturedRequest(this.method, this.url, this.headers, this.rawBody);

  Map<String, dynamic> get json => jsonDecode(rawBody) as Map<String, dynamic>;
  Map<String, dynamic> get data => json['data'] as Map<String, dynamic>;

  @override
  String toString() => '$method $url $rawBody';
}

class Stage0Harness {
  final List<CapturedRequest> requests = [];
  final List<MethodCall> telephonyCalls = [];
  final List<MethodCall> ussdCalls = [];
  final List<String> blockedHttpClients = [];

  /// Status code returned for backend (api.*) requests.
  int backendStatus = 200;
  Map<String, dynamic> backendResponse = {'success': true};

  /// Stage 1: when set, backend requests fail at the client level (thrown).
  Object? backendError;

  /// Stage 1: when set, sent verbatim instead of [backendResponse].
  String? backendRawBody;

  List<CapturedRequest> get backendPosts => requests
      .where((r) => r.method == 'POST' && r.url.host.startsWith('api.'))
      .toList();

  List<MethodCall> get smsSends =>
      telephonyCalls.where((c) => c.method.toLowerCase().contains('send')).toList();

  /// Call from setUpAll.
  static Future<void> setUpAllOnce() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // The binding installs its own HttpOverrides; replace it with one that
    // refuses (and records) any client not created through runWithClient.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    _tempDir = await Directory.systemTemp.createTemp('bsat_stage0_db_');
    await databaseFactory.setDatabasesPath(_tempDir.path);
    _neutralizeStaticConfirmationTimer();
  }

  static late Directory _tempDir;

  /// Call from tearDownAll.
  static Future<void> tearDownAllOnce() async {
    final db = await SQLiteService().database;
    await db.close();
    try {
      await _tempDir.delete(recursive: true);
    } catch (_) {}
  }

  /// The constructor's `Timer.periodic` is stored in a private static field
  /// and only created once per isolate. Creating it inside FakeAsync makes it
  /// a fake timer that never fires; later constructors reuse it.
  static void _neutralizeStaticConfirmationTimer() {
    fakeAsync((_) {
      TransactionController(
        sqliteService: SQLiteService(databaseOverride: _NeverUsedDatabase()),
      );
    });
  }

  Future<void> setUp({Map<String, Object> prefs = const {}}) async {
    requests.clear();
    telephonyCalls.clear();
    ussdCalls.clear();
    blockedHttpClients.clear();
    backendStatus = 200;
    backendResponse = {'success': true};
    backendError = null;
    backendRawBody = null;
    HttpOverrides.global = _RefusingHttpOverrides(blockedHttpClients);

    await _emptyStaticDatabase();

    SharedPreferences.setMockInitialValues(prefs);

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(telephonyChannel, (call) async {
      telephonyCalls.add(call);
      if (call.method.toLowerCase().contains('send')) {
        throw PlatformException(
          code: 'STAGE0_REFUSED',
          message: 'SMS sending is refused in Stage 0 tests',
        );
      }
      return <Object?>[];
    });
    messenger.setMockMethodCallHandler(ussdChannel, (call) async {
      ussdCalls.add(call);
      throw PlatformException(
        code: 'STAGE0_REFUSED',
        message: 'USSD is refused in Stage 0 tests',
      );
    });
  }

  Future<void> tearDown() async {
    await settle();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(telephonyChannel, null);
    messenger.setMockMethodCallHandler(ussdChannel, null);
  }

  /// Every test starts from an empty schema in the temporary database.
  static Future<void> _emptyStaticDatabase() async {
    final db = await SQLiteService().database;
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' "
      "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata'",
    );
    for (final table in tables) {
      await db.execute('DELETE FROM "${table['name']}"');
    }
    final hasSequence = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE name = 'sqlite_sequence'");
    if (hasSequence.isNotEmpty) await db.execute('DELETE FROM sqlite_sequence');
  }

  /// The default (static) database used by code that calls `SQLiteService()`.
  Future<Database> get db => SQLiteService().database;

  /// Runs [body] with every package:http request captured and answered
  /// locally. Pending work started inside is drained before returning.
  Future<T> capture<T>(Future<T> Function() body) {
    final client = MockClient((request) async {
      final captured = CapturedRequest(
        request.method,
        request.url,
        request.headers.map((k, v) => MapEntry(k.toLowerCase(), v)),
        request.body,
      );
      requests.add(captured);
      // Stage 1: optional byte-level dump for before/after comparison.
      final dump = Platform.environment['STAGE1_CAPTURE_DUMP'];
      if (dump != null && dump.isNotEmpty) {
        File(dump).writeAsStringSync(
          '${jsonEncode({
                'method': captured.method,
                'url': '${captured.url}',
                'headers': (captured.headers.entries.toList()
                      ..sort((a, b) => a.key.compareTo(b.key)))
                    .map((e) => '${e.key}: ${e.value}')
                    .toList(),
                'body': captured.rawBody,
              })}\n',
          mode: FileMode.append,
          flush: true,
        );
      }
      if (request.url.host.startsWith('api.')) {
        final error = backendError;
        if (error != null) throw error;
        final raw = backendRawBody;
        return http.Response(raw ?? jsonEncode(backendResponse), backendStatus,
            headers: {
              'content-type': raw == null ? 'application/json' : 'text/plain'
            });
      }
      return http.Response('ok', 200);
    });
    return http.runWithClient(() async {
      final result = await body();
      await settle();
      return result;
    }, () => client);
  }

  /// Drains microtasks and zero-duration timers (no wall-clock waiting).
  static Future<void> settle([int turns = 60]) async {
    for (var i = 0; i < turns; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  /// Asserts the safety envelope of every Stage 0 test.
  void expectNoExternalEffects() {
    expect(smsSends, isEmpty, reason: 'no SMS may be sent');
    expect(ussdCalls, isEmpty, reason: 'no USSD may be dialled');
    expect(blockedHttpClients, isEmpty,
        reason: 'all HTTP must go through the captured client');
  }
}

class _RefusingHttpOverrides extends HttpOverrides {
  final List<String> log;
  _RefusingHttpOverrides(this.log);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    log.add(StackTrace.current.toString().split('\n').take(6).join(' | '));
    File('network_attempts.log').writeAsStringSync(
      '${DateTime.now().toIso8601String()} BLOCKED (stage0 harness)\n',
      mode: FileMode.append,
      flush: true,
    );
    throw const SocketException('Network access is blocked in Stage 0 tests');
  }
}

/// Placeholder database for the timer-neutralizing controller. Its work is
/// scheduled inside an abandoned FakeAsync zone and never runs.
class _NeverUsedDatabase implements Database {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Stage 0 placeholder database must not be used');
}
