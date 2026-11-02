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

bool isMatchingForwardingReceipt({
  required String expectedJobId,
  required String receivedJobId,
  required String expectedTransactionId,
  required String receivedTransactionId,
  required String expectedRecipientDeviceName,
  required String receivedSenderDeviceName,
  required String expectedSenderDeviceName,
  required String receivedRecipientDeviceName,
}) {
  final expectedLocalId = int.tryParse(expectedTransactionId.trim());
  final receivedLocalId = int.tryParse(receivedTransactionId.trim());
  return expectedJobId.trim().isNotEmpty &&
      expectedJobId.trim() == receivedJobId.trim() &&
      expectedLocalId != null &&
      expectedLocalId > 0 &&
      expectedLocalId == receivedLocalId &&
      expectedRecipientDeviceName.trim().isNotEmpty &&
      expectedRecipientDeviceName.trim() == receivedSenderDeviceName.trim() &&
      expectedSenderDeviceName.trim().isNotEmpty &&
      expectedSenderDeviceName.trim() == receivedRecipientDeviceName.trim();
}

/// Why a final forwarded-SMS confirmation was not applied to a persisted
/// forwarding transaction on the origin device.
enum ForwardingConfirmationRejection {
  /// The persisted row has no recipient (or sender) to correlate with.
  incompleteForwardingIdentity,

  /// The confirmation was not sent by the device the job was forwarded to.
  unexpectedSender,

  /// The confirmation is addressed to a different origin device.
  unexpectedRecipient,

  /// The confirmation names a different M-PESA receipt than the job's.
  transactionMismatch,

  /// The transport authenticated a sender that is not the expected
  /// recipient, or that differs from the sender named in the message.
  authenticatedSenderMismatch,
}

/// Correlates a final confirmation with one persisted forwarding row.
/// Returns null when it may be applied, otherwise the first failed rule.
///
/// * The job IDs are already equal (the row was looked up by job ID).
/// * [receivedSenderDeviceName] must equal the row's persisted recipient
///   ([expectedRecipientDeviceName]). This is the sender *named in the
///   message*; it is consistency, not authentication.
/// * [receivedRecipientDeviceName] must equal the row's persisted sender, or
///   this device's name when the row predates that column.
/// * [receivedTransactionId] may be empty, a positive integer (the
///   destination's own local row ID, which several valid paths send and this
///   device cannot verify), or otherwise must equal the row's M-PESA receipt
///   ([expectedReceiptCode]).
/// * When the transport authenticated the sender
///   ([authenticatedSenderDeviceName] non-null), it must equal both the
///   expected recipient and the named sender. The Internet (FCM) path
///   provides no such identity and passes null.
ForwardingConfirmationRejection? forwardingConfirmationRejection({
  required String expectedRecipientDeviceName,
  required String expectedSenderDeviceName,
  required String localDeviceName,
  required String expectedReceiptCode,
  required String receivedSenderDeviceName,
  required String receivedRecipientDeviceName,
  required String receivedTransactionId,
  String? authenticatedSenderDeviceName,
}) {
  final expectedRecipient = expectedRecipientDeviceName.trim();
  final expectedSender = expectedSenderDeviceName.trim().isEmpty
      ? localDeviceName.trim()
      : expectedSenderDeviceName.trim();
  if (expectedRecipient.isEmpty || expectedSender.isEmpty) {
    return ForwardingConfirmationRejection.incompleteForwardingIdentity;
  }
  final namedSender = receivedSenderDeviceName.trim();
  if (authenticatedSenderDeviceName != null &&
      (authenticatedSenderDeviceName.trim() != expectedRecipient ||
          authenticatedSenderDeviceName.trim() != namedSender)) {
    return ForwardingConfirmationRejection.authenticatedSenderMismatch;
  }
  if (namedSender != expectedRecipient) {
    return ForwardingConfirmationRejection.unexpectedSender;
  }
  if (receivedRecipientDeviceName.trim() != expectedSender) {
    return ForwardingConfirmationRejection.unexpectedRecipient;
  }
  final transactionId = receivedTransactionId.trim();
  final isLocalRowId = RegExp(r'^[1-9]\d*$').hasMatch(transactionId);
  if (transactionId.isNotEmpty &&
      !isLocalRowId &&
      transactionId != expectedReceiptCode.trim()) {
    return ForwardingConfirmationRejection.transactionMismatch;
  }
  return null;
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

bool isForwardingReceiptAcknowledgement({
  required String ackKind,
  required String status,
}) =>
    ackKind.toLowerCase() == 'received' &&
    status.toLowerCase() == 'received';
