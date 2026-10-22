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
}) {
  if (!_forwardedStatuses.contains(status)) return reply;
  final name = meaningfulForwardingDeviceName(destinationDeviceName);
  if (name == null) return reply;
  return 'Forwarded to $name';
}
