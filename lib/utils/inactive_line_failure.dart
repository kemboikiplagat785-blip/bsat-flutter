/// Safaricom's "Purchase failed, the customer line is inactive. Kindly topup
/// the line with any amount to reactivate" names no customer, code or amount.
/// These rules decide which Successful(Pending) transaction it belongs to,
/// from the SIM it arrived on and the time it arrived; they never guess
/// between transactions that fit equally.
library;

/// True for Safaricom's inactive-line purchase failure.
bool isInactiveLineFailureMessage(String body) => RegExp(
      r'purchase\s+failed\W+(?:the\s+)?customer\s+line\s+is\s+inactive',
      caseSensitive: false,
    ).hasMatch(body);

/// How long before the failure SMS the matching purchase may have been
/// dialed (the window confirmations use).
const Duration inactiveLineFailureWindow = Duration(minutes: 20);

/// How long an unclear failure waits for confirmations to rule out the
/// other transactions before the oldest-first pairing is tried.
const Duration inactiveLineFailureWait = Duration(minutes: 5);

/// How long an unmatched failure is kept trying.
const Duration inactiveLineFailureExpiry = Duration(days: 1);

class InactiveLineFailure {
  final int id;
  final int smsTimestamp;

  /// SIM the SMS arrived on; null when unknown.
  final int? simSubId;

  const InactiveLineFailure({
    required this.id,
    required this.smsTimestamp,
    this.simSubId,
  });
}

/// A Successful(Pending) transaction still waiting for its confirmation.
class PendingPurchase {
  final int id;

  /// When it was (last) dialed.
  final int dialedAt;

  /// SIM it was dialed on; null when unknown.
  final int? simSubId;

  const PendingPurchase({
    required this.id,
    required this.dialedAt,
    this.simSubId,
  });
}

bool _fits(InactiveLineFailure failure, PendingPurchase purchase) {
  final sameSim = failure.simSubId == null ||
      purchase.simSubId == null ||
      failure.simSubId == purchase.simSubId;
  return sameSim &&
      purchase.dialedAt <= failure.smsTimestamp &&
      purchase.dialedAt >=
          failure.smsTimestamp - inactiveLineFailureWindow.inMilliseconds;
}

/// Pairs failures with the pending purchases they belong to, as
/// `(failureId, purchaseId)`:
///
/// 1. A failure that fits exactly one purchase gets it. This repeats, since
///    each pairing can leave another failure with one purchase.
/// 2. After [inactiveLineFailureWait], the failures still unclear on one SIM
///    are paired oldest-first with the purchases that fit them, but only when
///    there are as many purchases as failures and every pair fits
///    (Safaricom answers in the order the codes were dialed).
///
/// Anything else is left unpaired: confirmations arriving later rule out
/// purchases, and the next call tries again.
List<(int, int)> matchInactiveLineFailures({
  required List<InactiveLineFailure> failures,
  required List<PendingPurchase> pending,
  required int now,
}) {
  final pairs = <(int, int)>[];
  final openFailures = [...failures]
    ..sort((a, b) => a.smsTimestamp.compareTo(b.smsTimestamp));
  final openPurchases = [...pending];

  void pair(InactiveLineFailure failure, PendingPurchase purchase) {
    pairs.add((failure.id, purchase.id));
    openFailures.remove(failure);
    openPurchases.remove(purchase);
  }

  var changed = true;
  while (changed) {
    changed = false;
    for (final failure in [...openFailures]) {
      final fitting =
          openPurchases.where((purchase) => _fits(failure, purchase)).toList();
      if (fitting.length == 1) {
        pair(failure, fitting.single);
        changed = true;
      }
    }
  }

  final simGroups = <int?, List<InactiveLineFailure>>{};
  for (final failure in openFailures) {
    simGroups.putIfAbsent(failure.simSubId, () => []).add(failure);
  }
  for (final group in simGroups.values) {
    final waitedLongEnough = group.every((failure) =>
        now - failure.smsTimestamp >= inactiveLineFailureWait.inMilliseconds);
    if (!waitedLongEnough) continue;
    final fitting = openPurchases
        .where((purchase) => group.any((failure) => _fits(failure, purchase)))
        .toList()
      ..sort((a, b) => a.dialedAt.compareTo(b.dialedAt));
    if (fitting.length != group.length) continue;
    final allFit = [
      for (var i = 0; i < group.length; i++) _fits(group[i], fitting[i]),
    ].every((fits) => fits);
    if (!allFit) continue;
    for (var i = 0; i < group.length; i++) {
      pair(group[i], fitting[i]);
    }
  }
  return pairs;
}
