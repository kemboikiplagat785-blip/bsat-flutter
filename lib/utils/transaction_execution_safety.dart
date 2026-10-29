import 'constants.dart';

enum SafaricomTransactionMessageKind {
  recommendationSubmitted,
  recommendationConfirmed,
  giftBundlePurchased,
}

class SafaricomTransactionEvidence {
  final SafaricomTransactionMessageKind kind;
  final String recipientNumber;
  final int? amount;
  final String? transactionCode;

  const SafaricomTransactionEvidence({
    required this.kind,
    required this.recipientNumber,
    this.amount,
    this.transactionCode,
  });

  String get targetStatus => switch (kind) {
        SafaricomTransactionMessageKind.recommendationSubmitted =>
          TransactionStatuses.successfulPending,
        SafaricomTransactionMessageKind.recommendationConfirmed ||
        SafaricomTransactionMessageKind.giftBundlePurchased =>
          TransactionStatuses.doneConfirmed,
      };

  static SafaricomTransactionEvidence? parse(String body) {
    final kind = RegExp(
      r'thank\s+you\s+for\s+choosing\s+safaricom.*?'
      r'you\s+have\s+purchased\s+.+?for\s+\d+',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(body)
        ? SafaricomTransactionMessageKind.giftBundlePurchased
        : RegExp(
            r'you\s+have\s+successfully\s+recommended\s+offer',
            caseSensitive: false,
          ).hasMatch(body)
            ? SafaricomTransactionMessageKind.recommendationConfirmed
            : RegExp(
                r'recommendation\s+for\s+\d+\s+submitted\s+successfully',
                caseSensitive: false,
              ).hasMatch(body)
                ? SafaricomTransactionMessageKind.recommendationSubmitted
                : null;
    if (kind == null) return null;

    final recipientMatch = RegExp(
      r'\b(?:to|for)\s+((?:\+?254|0)?[\d][\d\s().-]{7,15})',
      caseSensitive: false,
    ).firstMatch(body);
    final digits =
        recipientMatch?.group(1)?.replaceAll(RegExp(r'\D'), '') ?? '';
    if (digits.length < 9 || digits.length > 12) return null;
    final normalized = normalizeSafaricomRecipient(digits);
    if (normalized.isEmpty) return null;
    final amountMatch = RegExp(
      r'(?:offer|bundle|purchase|purchased)[^\n]{0,35}?(?:kshs?|kes)\s*([\d,]+)'
      r'|(?:kshs?|kes)\s*([\d,]+)[^\n]{0,25}?(?:offer|bundle|purchase)',
      caseSensitive: false,
    ).firstMatch(body);
    final amount = int.tryParse(
      (amountMatch?.group(1) ?? amountMatch?.group(2) ?? '')
          .replaceAll(',', ''),
    );
    final codeMatch = RegExp(
      r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]{10}\b',
      caseSensitive: false,
    ).firstMatch(body);
    return SafaricomTransactionEvidence(
      kind: kind,
      recipientNumber: normalized,
      amount: amount,
      transactionCode: codeMatch?.group(0),
    );
  }
}

String normalizeSafaricomRecipient(String digits) {
  final normalized = digits.startsWith('254') && digits.length == 12
      ? digits.substring(3)
      : digits.startsWith('254') && digits.length == 11
          ? digits.substring(3)
          : digits.startsWith('0') && digits.length == 10
              ? digits.substring(1)
              : digits;
  return normalized.length == 9 ? '0$normalized' : '';
}

bool isAmbiguousTransactionOutcome({
  required String status,
  required String reply,
}) {
  if (status == TransactionStatuses.timedOut || reply.trim().isEmpty) {
    return true;
  }
  if (RegExp(
    r'error sending code|time.?out|timed out|no reply|connection code error|'
    r'session already in progress|duplicate sessions',
    caseSensitive: false,
  ).hasMatch(reply)) {
    return true;
  }
  final definitiveRejection = RegExp(
    r'recommendation failed|bundle activation request has failed|'
    r'mobile number is not active|insufficient balance|invalid number|'
    r'offer is unavailable|offer unavailable',
    caseSensitive: false,
  ).hasMatch(reply);
  return status == TransactionStatuses.error && !definitiveRejection;
}

Map<String, dynamic>? uniqueSafaricomTransactionCandidate(
  Iterable<Map<String, dynamic>> candidates,
) {
  final iterator = candidates.iterator;
  if (!iterator.moveNext()) return null;
  final candidate = iterator.current;
  if (iterator.moveNext()) return null;
  return candidate;
}
