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

/// The 9-digit Kenyan mobile number in [input] (`0712345678`,
/// `254712345678`, `+254 712 345 678` or `712345678`), or null when it is
/// not one. SMS go to `254` followed by this number.
String? normalizeKenyanMobileNumber(String? input) {
  final digits = (input ?? '').replaceAll(RegExp(r'\D'), '');
  final local = digits.length == 12 && digits.startsWith('254')
      ? digits.substring(3)
      : digits.length == 10 && digits.startsWith('0')
          ? digits.substring(1)
          : digits;
  return RegExp(r'^[17]\d{8}$').hasMatch(local) ? local : null;
}

bool isValidSmsForwardingRequest(String address, String message) {
  return address.trim().isNotEmpty && message.trim().isNotEmpty;
}

bool isOfflineForwardingMode(String? mode) {
  return mode?.trim().toLowerCase() == ForwardingModes.offline;
}
