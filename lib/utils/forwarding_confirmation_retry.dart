const List<int> forwardingConfirmationRetrySeconds = [5, 15, 30, 60, 120, 300];

int nextForwardingConfirmationAttempt(int currentAttempt) => currentAttempt + 1;

Duration forwardingConfirmationRetryDelay({
  required int attempt,
  int? statusCode,
  String? message,
  Object? error,
}) {
  final details = '${message ?? ''} ${error ?? ''}'.toLowerCase();
  final identifiesUnpairedDevices =
      RegExp(r'devices?\s+(?:are\s+)?not\s+paired').hasMatch(details) ||
          RegExp(r'not\s+paired.{0,100}devices?').hasMatch(details);

  if (statusCode == 403 && identifiesUnpairedDevices) {
    return const Duration(minutes: 30);
  }

  final index = (attempt - 1)
      .clamp(0, forwardingConfirmationRetrySeconds.length - 1)
      .toInt();
  return Duration(seconds: forwardingConfirmationRetrySeconds[index]);
}
