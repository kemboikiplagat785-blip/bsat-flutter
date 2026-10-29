import 'package:bsat/utils/constants.dart';

const _forwardedStatuses = <String>{
  TransactionStatuses.forwarded,
  TransactionStatuses.forwardedPending,
  TransactionStatuses.forwardedConfirmed,
  TransactionStatuses.forwardedOnline,
};

String? meaningfulForwardingDeviceName(String? value) {
  final name = value?.trim() ?? '';
  if (name.isEmpty) return null;
  final normalized = name.toLowerCase();
  if (normalized == 'null' ||
      normalized == 'device' ||
      normalized.startsWith('unknown device') ||
      RegExp(r'^device[_ -]?id\s*[:#=]').hasMatch(normalized)) {
    return null;
  }
  return name;
}

String forwardingDisplayReply({
  required String status,
  required String reply,
  String? destinationDeviceName,
  String? transactionId,
}) {
  if (!_forwardedStatuses.contains(status)) return reply;
  final entries = reply.split('\n•\n');
  final forwardingEntryIndex = entries.indexWhere(
    (entry) =>
        RegExp(r'^\s*Forwarded to\b', caseSensitive: false).hasMatch(entry),
  );
  final forwardingEntry =
      forwardingEntryIndex >= 0 ? entries[forwardingEntryIndex] : reply;
  final embeddedDeviceId = RegExp(
    r'\(ID:\s*([^)]+)\)',
    caseSensitive: false,
  ).firstMatch(forwardingEntry)?.group(1)?.trim();
  final name = meaningfulForwardingDeviceName(destinationDeviceName) ??
      meaningfulForwardingDeviceName(embeddedDeviceId);
  if (name == null) return reply;
  final id = transactionId?.trim() ?? '';
  final label =
      'Forwarded to $name${id.isEmpty ? '' : ' — Transaction ID: $id'}';
  if (forwardingEntryIndex >= 0) {
    entries[forwardingEntryIndex] = label;
  } else {
    entries.insert(0, label);
  }
  return entries.join('\n•\n');
}
