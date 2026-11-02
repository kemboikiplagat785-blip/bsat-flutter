import 'dart:math';
import 'dart:typed_data';

final Random _secure = Random.secure();

/// Bytes from the platform CSPRNG (dart:math Random.secure).
Uint8List secureRandomBytes(int length) =>
    Uint8List.fromList(List<int>.generate(length, (_) => _secure.nextInt(256)));

/// Constant-time comparison for MACs, fingerprints and tokens.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

/// RFC 4648 base32, uppercase, no padding.
String base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_base32Alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_base32Alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// Decodes [base32Encode] output. Ignores separators and spaces; accepts
/// lowercase; maps the commonly confused 0/1/8 to O/I/B.
Uint8List base32Decode(String text) {
  final cleaned = text
      .toUpperCase()
      .replaceAll(RegExp(r'[\s\-]'), '')
      .replaceAll('0', 'O')
      .replaceAll('1', 'I')
      .replaceAll('8', 'B');
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final char in cleaned.split('')) {
    final value = _base32Alphabet.indexOf(char);
    if (value < 0) throw FormatException('Invalid base32 character "$char".');
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
    }
    buffer &= (1 << bits) - 1;
  }
  return Uint8List.fromList(out);
}
