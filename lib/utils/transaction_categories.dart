import 'package:bsat/utils/constants.dart';

/// A History category: which stored transactions it shows and counts. Home,
/// History counts, History filters and the bulk retry/delete sheets all use
/// these, so a transaction counted under a category is also listed under it.
class TransactionCategory {
  /// The query History filters by (a [TransactionStatuses] value).
  final String key;
  final String label;

  /// SQL condition on `transactions`; status values are constants, so it
  /// takes no arguments.
  final String where;

  const TransactionCategory(this.key, this.label, this.where);

  static String _statusIn(Iterable<String> statuses) =>
      "status IN (${statuses.map((status) => "'$status'").join(', ')})";

  static const _noJob = "COALESCE(forwardingJobId, '') = '' AND "
      "COALESCE(forwardingRecipientDeviceName, '') = ''";

  static final confirmed = TransactionCategory(
    TransactionStatuses.doneConfirmed,
    'Successful(Confirmed)',
    _statusIn(const [TransactionStatuses.doneConfirmed]),
  );

  static final advanced = TransactionCategory(
    TransactionStatuses.advancedUssd,
    'Advanced',
    _statusIn(const [
      TransactionStatuses.advancedUssd,
      TransactionStatuses.advancedQueue,
    ]),
  );

  /// Dialed successfully, confirmation SMS not received yet. `done` is the
  /// status of a dial whose reply matched no known pattern.
  static final successfulPending = TransactionCategory(
    TransactionStatuses.successfulPending,
    'Successful(Pending)',
    _statusIn(const [
      TransactionStatuses.successfulPending,
      TransactionStatuses.done,
    ]),
  );

  /// Forwarded by SMS (offline); no forwarding job.
  static final forwarded = TransactionCategory(
    TransactionStatuses.forwarded,
    'Forwarded',
    "${_statusIn(const [TransactionStatuses.forwarded])} AND $_noJob",
  );

  /// Forwarding jobs to a paired device (Online or LAN) not confirmed yet,
  /// including legacy jobs stored as plain `forwarded`.
  static final forwardedPending = TransactionCategory(
    TransactionStatuses.forwardedPending,
    'Forwarded (Pending)',
    "(${_statusIn(const [
          TransactionStatuses.forwardedPending,
          TransactionStatuses.forwardedOnline,
        ])} OR (${_statusIn(const [
          TransactionStatuses.forwarded
        ])} AND NOT ($_noJob)))",
  );

  static final forwardedConfirmed = TransactionCategory(
    TransactionStatuses.forwardedConfirmed,
    'Forwarded (Successful)',
    _statusIn(const [TransactionStatuses.forwardedConfirmed]),
  );

  static final okoa = TransactionCategory(
    TransactionStatuses.hasOkoa,
    'Okoa',
    _statusIn(const [TransactionStatuses.hasOkoa]),
  );

  static final unavailableOffer = TransactionCategory(
    TransactionStatuses.unavailableOffer,
    'Unavailable Offer',
    _statusIn(const [TransactionStatuses.unavailableOffer]),
  );

  /// The primary code failed; includes its alternative while it runs or
  /// its outcome is unknown.
  static final secondAttempt = TransactionCategory(
    TransactionStatuses.secondAttempt,
    'Second Attempt',
    _statusIn(const [
      TransactionStatuses.secondAttempt,
      TransactionStatuses.alternativeExecuting,
      TransactionStatuses.alternativeDeliveryPending,
      TransactionStatuses.alternativeAmbiguous,
    ]),
  );

  static final paused = TransactionCategory(
    TransactionStatuses.paused,
    'Paused',
    _statusIn(const [TransactionStatuses.paused]),
  );

  static final blacklisted = TransactionCategory(
    TransactionStatuses.blacklisted,
    'Blacklisted',
    "(${_statusIn(const [TransactionStatuses.blacklisted])} "
        "OR ussdReply LIKE '%blacklisted%')",
  );

  /// Failures: errors, timeouts, a failed alternative, and rows with no
  /// status at all.
  static final error = TransactionCategory(
    TransactionStatuses.error,
    'Error',
    "(${_statusIn(const [
          TransactionStatuses.error,
          TransactionStatuses.timedOut,
          TransactionStatuses.alternativeFailed,
          'No reply',
        ])} OR COALESCE(status, '') = '')",
  );

  static final masked = TransactionCategory(
    TransactionStatuses.masked,
    'Masked',
    _statusIn(const [TransactionStatuses.masked]),
  );

  static final all = <TransactionCategory>[
    confirmed,
    advanced,
    successfulPending,
    forwarded,
    forwardedPending,
    forwardedConfirmed,
    okoa,
    unavailableOffer,
    secondAttempt,
    paused,
    blacklisted,
    error,
    masked,
  ];

  static const _aliases = <String, String>{
    'advanced': TransactionStatuses.advancedUssd,
    TransactionStatuses.advancedQueue: TransactionStatuses.advancedUssd,
    TransactionStatuses.done: TransactionStatuses.successfulPending,
    TransactionStatuses.forwardedOnline: TransactionStatuses.forwardedPending,
    TransactionStatuses.timedOut: TransactionStatuses.error,
    TransactionStatuses.alternativeFailed: TransactionStatuses.error,
    TransactionStatuses.alternativeExecuting: TransactionStatuses.secondAttempt,
    TransactionStatuses.alternativeDeliveryPending:
        TransactionStatuses.secondAttempt,
    TransactionStatuses.alternativeAmbiguous: TransactionStatuses.secondAttempt,
    'blacklist': TransactionStatuses.blacklisted,
  };

  /// The category History shows for [query] (a category key, a status it
  /// contains, or a legacy alias), or null for a text search.
  static TransactionCategory? forQuery(String? query) {
    if (query == null) return null;
    final key = _aliases[query] ?? query;
    for (final category in all) {
      if (category.key == key) return category;
    }
    return null;
  }

  /// [where] limited to transactions processed on [date] (`date` column).
  String onDate(String date) => "($where) AND date = '$date'";
}
