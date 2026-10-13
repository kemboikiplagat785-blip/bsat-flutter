import 'constants.dart';

class ForwardingModes {
  static const offline = 'offline';
}

int parseAlternativeDelaySeconds(String value) {
  final parsed = int.tryParse(value);
  if (parsed == null || parsed < 0) {
    throw const FormatException(
      'Alternative delay must be a whole number of seconds (0 or more).',
    );
  }
  return parsed;
}

int legacyAlternativeDelayMinutesToSeconds(Object? value) {
  final minutes = int.tryParse(value?.toString() ?? '') ?? 0;
  return minutes < 0 ? 0 : minutes * 60;
}

int readAlternativeDelaySeconds(Object? seconds, Object? legacyMinutes) {
  final configuredSeconds = int.tryParse(seconds?.toString() ?? '');
  return configuredSeconds ??
      legacyAlternativeDelayMinutesToSeconds(legacyMinutes);
}

int alternativeDelayDeadlineMs(int failedAtMs, int delaySeconds) {
  if (delaySeconds < 0) {
    throw ArgumentError.value(
      delaySeconds,
      'delaySeconds',
      'must be non-negative',
    );
  }
  return failedAtMs + delaySeconds * 1000;
}

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
