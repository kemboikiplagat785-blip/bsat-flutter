import 'package:bsat/utils/constants.dart';

const int initialForwardingDeliveryRetryDelaySeconds = 30;
const List<int> forwardingDeliveryRetryBackoffSeconds = [
  30,
  60,
  120,
  300,
  600,
  1800,
];

int get maxForwardingDeliveryRetries =>
    forwardingDeliveryRetryBackoffSeconds.length + 1;

Duration? forwardingDeliveryRetryDelayAfterAttempt(int attempt) {
  if (attempt <= 0 || attempt > forwardingDeliveryRetryBackoffSeconds.length) {
    return null;
  }
  return Duration(
    seconds: forwardingDeliveryRetryBackoffSeconds[attempt - 1],
  );
}

Map<String, dynamic> buildForwardedSmsRequestPayload({
  required String message,
  required String messageId,
  required int transactionRowId,
  required String forwardingJobId,
  required String senderDeviceName,
  required String recipientDeviceName,
}) {
  return {
    'title': 'BSAT Online Forwarding',
    'body': message,
    'senderDeviceName': senderDeviceName,
    'recipientDeviceName': recipientDeviceName,
    'data': {
      'type': 'forwarded_sms',
      'body': message,
      'title': 'Forwarded Message',
      'messageId': messageId,
      'transactionId': transactionRowId,
      'forwardingJobId': forwardingJobId,
      'forwardingStatus': ForwardingJobStatuses.pending,
      'senderDeviceName': senderDeviceName,
      'recipientDeviceName': recipientDeviceName,
    },
  };
}
