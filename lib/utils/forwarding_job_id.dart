import 'dart:math';

class ForwardingJobId {
  static String generate({String? mpesaCode}) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;

    if (mpesaCode != null && mpesaCode.trim().isNotEmpty) {
      final cleanCode = mpesaCode.trim().replaceAll(
            RegExp(r'[^A-Za-z0-9]'),
            '',
          );

      return 'fwd_${cleanCode}_$timestamp';
    }

    final random = Random();
    final randomPart = List.generate(
      12,
      (_) => String.fromCharCode(
        random.nextInt(26) + 65,
      ),
    ).join();

    return 'fwd_${randomPart}_$timestamp';
  }
}
