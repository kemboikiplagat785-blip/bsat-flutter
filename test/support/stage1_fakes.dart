import 'package:bsat/services/forwarding_transport.dart';

/// Records submissions and answers with a configurable result. Makes no
/// network calls, so any HTTP request seen alongside it bypassed the
/// injected transport.
class RecordingForwardingTransport implements ForwardingTransport {
  final List<ForwardingSubmission> submissions = [];
  ForwardingSubmissionResult result = const ForwardingSubmissionResult(
    accepted: true,
    statusCode: 200,
    details: {'success': true, 'data': {}, 'statusCode': 200},
  );

  @override
  Future<ForwardingSubmissionResult> submit(
    ForwardingSubmission submission,
  ) async {
    submissions.add(submission);
    return result;
  }
}
