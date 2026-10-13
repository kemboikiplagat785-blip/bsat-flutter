import 'constants.dart';

bool isSuccessfulSmsForwardingHandoff(String result) {
  final normalizedResult = result.trim().toLowerCase();
  return normalizedResult == 'sent' || normalizedResult == 'already sent';
}

String? offlineForwardingStatusForHandoff(String result) {
  return isSuccessfulSmsForwardingHandoff(result)
      ? TransactionStatuses.forwarded
      : null;
}

bool isValidSmsForwardingRequest(String address, String message) {
  return address.trim().isNotEmpty && message.trim().isNotEmpty;
}

bool isOfflineForwardingMode(String? mode) {
  return mode?.trim().toLowerCase() == ForwardingModes.offline;
}
