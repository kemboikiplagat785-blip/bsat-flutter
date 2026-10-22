/// Returns Phone A's transaction row ID only when the caller can establish
/// that [value] came from the originating-row-ID field in the request
/// contract. Numeric shape alone cannot distinguish it from a receipt code or
/// Phone B's local row ID.
String? originatingForwardingTransactionId(
  String? value, {
  bool hasOriginatingRowIdProvenance = false,
}) {
  if (!hasOriginatingRowIdProvenance) return null;
  final id = int.tryParse(value?.trim() ?? '');
  return id != null && id > 0 ? id.toString() : null;
}

bool isFinalForwardedSmsConfirmation({
  required String ackKind,
  required String status,
}) {
  final normalizedAckKind = ackKind.toLowerCase();
  final normalizedStatus = status.toLowerCase();
  if (normalizedAckKind == 'received' || normalizedStatus == 'received') {
    return false;
  }
  return normalizedAckKind == 'confirmed' ||
      normalizedStatus == 'transaction-confirmed';
}
