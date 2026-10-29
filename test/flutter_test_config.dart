// STAGE 0 AUDIT-ONLY network guard. Exists only in a disposable copy outside
// the repository. Any HTTP client created outside a test's own capturing
// HttpOverrides zone is refused and logged, so no test can reach a backend.
import 'dart:async';
import 'dart:io';

final File _attemptLog = File('network_attempts.log');

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  HttpOverrides.global = _BlockingHttpOverrides();
  await testMain();
}

class _BlockingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final caller = StackTrace.current
        .toString()
        .split('\n')
        .where((line) => line.contains('package:bsat/'))
        .take(3)
        .join(' <- ');
    _attemptLog.writeAsStringSync(
      '${DateTime.now().toIso8601String()} BLOCKED $caller\n',
      mode: FileMode.append,
      flush: true,
    );
    throw const SocketException('Network access is blocked in audit tests');
  }
}
