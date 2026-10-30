import 'package:bsat/utils/constants.dart';

/// Reply stored for a transaction whose USSD call failed without any reply.
const String failedUssdNoReply =
    'USSD call failed: no reply was received from the network. '
    'Retry the transaction.';

/// Reply stored for a transaction that finished without any reply.
const String noReplyReceived = 'No reply was received for this transaction.';

/// [reply], or a readable fallback when it is missing or blank, so every
/// transaction shows a reply. A failure ([status] error, timed out, or no
/// status) gets [failedUssdNoReply].
String transactionReplyOrFallback(Object? reply, Object? status) {
  final text = reply?.toString() ?? '';
  if (text.trim().isNotEmpty) return text;
  final value = status?.toString().trim() ?? '';
  return value.isEmpty ||
          value == 'No reply' ||
          value == TransactionStatuses.error ||
          value == TransactionStatuses.timedOut
      ? failedUssdNoReply
      : noReplyReceived;
}
