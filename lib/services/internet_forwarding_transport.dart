import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/forwarding_transport.dart';

/// Forwarding over the BSAT backend (`POST /api/fcm/send-secure`, relayed to
/// the destination by FCM). A thin wrapper around [BackendService.post]: the
/// endpoint, method, headers, authorization, body and error handling are
/// exactly BackendService's.
class InternetForwardingTransport implements ForwardingTransport {
  static const String defaultEndpoint = '/api/fcm/send-secure';

  final BackendService _backendService;

  /// Backend path the message is posted to. Only acknowledgements of
  /// incoming messages use a different one (the message's `callbackUrl`).
  final String endpoint;

  InternetForwardingTransport({
    BackendService? backendService,
    this.endpoint = defaultEndpoint,
  }) : _backendService = backendService ?? BackendService();

  @override
  Future<ForwardingSubmissionResult> submit(
    ForwardingSubmission submission,
  ) async {
    // BackendService.post converts network, HTTP and parse failures into a
    // result map; it does not throw for them.
    final result = await _backendService.post(
      endpoint,
      body: submission.request,
    );
    final statusCode = result['statusCode'];
    return ForwardingSubmissionResult(
      accepted: result['success'] == true,
      statusCode: statusCode is int ? statusCode : null,
      details: result,
    );
  }
}
