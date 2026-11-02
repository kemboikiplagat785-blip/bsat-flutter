/// Outgoing forwarding messages between paired devices (forwarded SMS,
/// receipt ACKs, final confirmations and their receipts).
///
/// A transport only submits a message. It never decides purchase, retry or
/// USSD outcomes, and it adds no retries, timers or background work of its
/// own: callers keep their existing durable retry schedules and claims.
library;

/// One outgoing message, exactly as the existing code builds it. [request] is
/// submitted unchanged: its field names, values and JSON types are part of
/// the existing wire format.
class ForwardingSubmission {
  final Map<String, dynamic> request;

  const ForwardingSubmission(this.request);
}

/// Outcome of one submission attempt.
///
/// [accepted] means only that the transport accepted the message for
/// delivery (for the Internet transport: the backend answered with a 2xx
/// status). It says nothing about receipt, execution or confirmation on the
/// destination device. [details] is the transport's raw result, kept so
/// existing callers can read the same fields as before.
class ForwardingSubmissionResult {
  final bool accepted;
  final int? statusCode;
  final Map<String, dynamic> details;

  const ForwardingSubmissionResult({
    required this.accepted,
    required this.statusCode,
    required this.details,
  });
}

abstract class ForwardingTransport {
  /// Submits [submission] once. Implementations report failures in the
  /// returned result rather than retrying.
  Future<ForwardingSubmissionResult> submit(ForwardingSubmission submission);
}
