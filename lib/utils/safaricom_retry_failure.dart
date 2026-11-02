/// Safaricom's "We're sorry, your transaction could not be completed. Please
/// try again later." and "Sorry, we are unable to process your request at the
/// moment." name no customer, code or amount. Each is held and given to the
/// Successful(Pending) transaction it belongs to by the rules in
/// inactive_line_failure.dart; that transaction moves to Error and is retried.
library;

/// True for Safaricom's temporary failures, whose purchase can be tried again.
/// The SMS handler removes apostrophes, so "We're" can arrive as "Were".
bool isSafaricomRetryFailureMessage(String body) => RegExp(
      r"we\W*re\s+sorry\W+your\s+transaction\s+could\s+not\s+be\s+completed"
      r"|sorry\W+we\s+are\s+unable\s+to\s+process\s+your\s+request",
      caseSensitive: false,
    ).hasMatch(body);

/// How long a failure waits for a confirmation before it is acted on.
const Duration safaricomRetryFailureWait = Duration(minutes: 1);

/// Dials allowed for a transaction after such a failure, and the time between
/// them. Past the limit it stays in Error for a manual retry.
const int maxSafaricomFailureRetries = 3;
const Duration safaricomFailureRetryGap = Duration(minutes: 1);
