// STAGE 1 (disposable copy): InternetForwardingTransport must be an exact
// pass-through to BackendService.post. Each scenario sends the same request
// directly and through the adapter and requires identical HTTP requests and
// identical result maps. No real network: requests are answered locally.
import 'dart:convert';

import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/internet_forwarding_transport.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'support/stage0_harness.dart';

const _jwt = 'stage1-test-jwt';
const _endpoint = 'https://api.bsat2.xyz/api/fcm/send-secure';

/// A forwarded-SMS-shaped request with mixed JSON value types.
Map<String, dynamic> _request() => {
      'title': 'BSAT Online Forwarding',
      'body': 'SYNTHETIC body',
      'senderDeviceName': 'Phone A',
      'recipientDeviceName': 'Phone B',
      'data': {
        'type': 'forwarded_sms',
        'messageId': 'SJK1ABCD23',
        'transactionId': 41,
        'forwardingJobId': 'fwd_SJK1ABCD23_1761650000000',
        'requiredTopUp': 20,
        'flag': true,
        'missing': null,
        'list': [1, 'two'],
      },
    };

class _RecordingBackend extends BackendService {
  final List<(String, Map<String, dynamic>?)> calls = [];
  Object? throwOnPost;
  Map<String, dynamic> answer = {'success': true, 'statusCode': 200};

  @override
  Future<Map<String, dynamic>> post(String endpoint,
      {Map<String, dynamic>? body}) async {
    calls.add((endpoint, body));
    final error = throwOnPost;
    if (error != null) throw error;
    return answer;
  }
}

void main() {
  final h = Stage0Harness();

  setUpAll(Stage0Harness.setUpAllOnce);
  tearDownAll(Stage0Harness.tearDownAllOnce);
  tearDown(h.tearDown);

  /// Sends [request] directly and through the adapter; returns both results
  /// and the two captured HTTP requests (direct first).
  Future<
      (
        Map<String, dynamic>,
        ForwardingSubmissionResult,
        List<CapturedRequest>
      )> sendBothWays({String endpoint = '/api/fcm/send-secure'}) async {
    late Map<String, dynamic> direct;
    late ForwardingSubmissionResult viaAdapter;
    await h.capture(() async {
      direct = await BackendService().post(endpoint, body: _request());
      viaAdapter = await InternetForwardingTransport(endpoint: endpoint)
          .submit(ForwardingSubmission(_request()));
    });
    return (direct, viaAdapter, List.of(h.requests));
  }

  void expectSameRequest(CapturedRequest a, CapturedRequest b) {
    expect(b.method, a.method);
    expect(b.url, a.url);
    expect(b.headers, a.headers);
    expect(b.rawBody, a.rawBody);
  }

  test('success: exact endpoint, method, headers and JSON body', () async {
    await h.setUp(prefs: {'jwt_token': _jwt});
    h.backendResponse = {'success': true, 'messageId': 'backend-1'};
    final (direct, viaAdapter, requests) = await sendBothWays();

    expect(requests, hasLength(2));
    expectSameRequest(requests[0], requests[1]);
    final sent = requests[1];
    expect(sent.method, 'POST');
    expect(sent.url.toString(), _endpoint);
    expect(sent.headers['content-type'], startsWith('application/json'));
    expect(sent.headers['authorization'], 'Bearer $_jwt');
    expect(sent.rawBody, jsonEncode(_request()),
        reason: 'body is jsonEncode of the request, field order included');
    final data = sent.data;
    expect(data['transactionId'], isA<int>());
    expect(data['requiredTopUp'], isA<int>());
    expect(data['flag'], isTrue);
    expect(data.containsKey('missing'), isTrue);
    expect(data['missing'], isNull);
    expect(data['list'], [1, 'two']);

    expect(viaAdapter.details, direct);
    expect(viaAdapter.details, {
      'success': true,
      'data': {'success': true, 'messageId': 'backend-1'},
      'statusCode': 200,
    });
    expect(viaAdapter.accepted, isTrue);
    expect(viaAdapter.statusCode, 200);
    h.expectNoExternalEffects();
  });

  test('any 2xx status is accepted, as BackendService treats it', () async {
    await h.setUp(prefs: {'jwt_token': _jwt});
    h.backendStatus = 201;
    final (direct, viaAdapter, _) = await sendBothWays();
    expect(direct['success'], isTrue);
    expect(viaAdapter.accepted, isTrue);
    expect(viaAdapter.statusCode, 201);
  });

  test('HTTP failure: same result map, not accepted, exactly one request',
      () async {
    await h.setUp(prefs: {'jwt_token': _jwt});
    h.backendStatus = 503;
    h.backendResponse = {'message': 'Service unavailable'};
    final (direct, viaAdapter, requests) = await sendBothWays();

    expect(requests, hasLength(2), reason: 'one per send; no retry');
    expectSameRequest(requests[0], requests[1]);
    expect(viaAdapter.details, direct);
    expect(viaAdapter.details, {
      'success': false,
      'message': 'Service unavailable',
      'error': {'message': 'Service unavailable'},
      'statusCode': 503,
    });
    expect(viaAdapter.accepted, isFalse);
    expect(viaAdapter.statusCode, 503);
    h.expectNoExternalEffects();
  });

  test('unparseable response body: same parse-failure mapping', () async {
    await h.setUp(prefs: {'jwt_token': _jwt});
    h.backendStatus = 502;
    h.backendRawBody = '<html>Bad gateway</html>';
    final (direct, viaAdapter, requests) = await sendBothWays();
    expect(requests, hasLength(2));
    expect(viaAdapter.details, direct);
    expect(viaAdapter.details['success'], isFalse);
    expect(viaAdapter.details['message'],
        'Failed to parse response: <html>Bad gateway</html>');
    expect(viaAdapter.accepted, isFalse);
    expect(viaAdapter.statusCode, 502);
  });

  test('network error: mapped (not thrown), no status, no retry', () async {
    await h.setUp(prefs: {'jwt_token': _jwt});
    h.backendError = http.ClientException('connection refused');
    final (direct, viaAdapter, requests) = await sendBothWays();
    expect(viaAdapter.details, direct);
    expect(viaAdapter.details['success'], isFalse);
    expect(viaAdapter.details['message'], startsWith('Network error: '));
    expect(viaAdapter.details.containsKey('statusCode'), isFalse);
    expect(viaAdapter.accepted, isFalse);
    expect(viaAdapter.statusCode, isNull);
    expect(requests, hasLength(2),
        reason: 'one attempt per send (recorded before the client failed); '
            'no retry');
    h.expectNoExternalEffects();
  });

  test('no stored token: no Authorization header, as before', () async {
    await h.setUp();
    final (_, _, requests) = await sendBothWays();
    expectSameRequest(requests[0], requests[1]);
    expect(requests[1].headers.containsKey('authorization'), isFalse);
  });

  test('a callback endpoint is posted to unchanged', () async {
    await h.setUp(prefs: {'jwt_token': _jwt});
    final (_, _, requests) =
        await sendBothWays(endpoint: '/api/fcm/custom-callback');
    expectSameRequest(requests[0], requests[1]);
    expect(requests[1].url.toString(),
        'https://api.bsat2.xyz/api/fcm/custom-callback');
  });

  group('delegation (no HTTP)', () {
    setUp(() => h.setUp(prefs: {'jwt_token': _jwt}));

    test('passes the identical request object and endpoint, once', () async {
      final backend = _RecordingBackend();
      final request = _request();
      final result = await InternetForwardingTransport(backendService: backend)
          .submit(ForwardingSubmission(request));
      expect(backend.calls, hasLength(1));
      expect(backend.calls.single.$1, '/api/fcm/send-secure');
      expect(identical(backend.calls.single.$2, request), isTrue);
      expect(identical(result.details, backend.answer), isTrue);
    });

    test('a non-int statusCode is not reported as a status', () async {
      final backend = _RecordingBackend()
        ..answer = {'success': false, 'statusCode': '503'};
      final result = await InternetForwardingTransport(backendService: backend)
          .submit(ForwardingSubmission(_request()));
      expect(result.statusCode, isNull);
      expect(result.details['statusCode'], '503');
      expect(result.accepted, isFalse);
    });

    test('an exception from the backend propagates unchanged, no retry',
        () async {
      final backend = _RecordingBackend()..throwOnPost = StateError('boom');
      await expectLater(
        InternetForwardingTransport(backendService: backend)
            .submit(ForwardingSubmission(_request())),
        throwsA(isA<StateError>()),
      );
      expect(backend.calls, hasLength(1));
    });
  });
}
