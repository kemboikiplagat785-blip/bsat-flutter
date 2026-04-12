
import 'dart:math';

String generateHash(String phoneNumber, String amount, int keyDigit) {
  int startMarker = 90;
  int keyAscii = keyDigit + 48;

  List<int> rawValues = [];
  rawValues.add(startMarker);
  rawValues.add(keyAscii);
  rawValues.addAll(phoneNumber.codeUnits);
  rawValues
      .addAll(amount.padLeft(3, '0').codeUnits);

  print("Raw Values: ${rawValues.map((v) => String.fromCharCode(v)).join()}");

  List<int> encodedValues = rawValues.map((v) {
    if (v == startMarker) return v;
    if (v == keyAscii) return v + 17;
    return v + keyDigit + 17;
  }).toList();

  String encodedString = String.fromCharCodes(encodedValues);
Random _rng = Random();

String randomPrefix = String.fromCharCodes(
  List.generate(5, (_) => 65 + _rng.nextInt(25))
);

int payloadLength = 16;
int suffixLength = 30 - 5 - payloadLength;
  // random number between 1 and 6
  int randomNum = 1 + (DateTime.now().millisecondsSinceEpoch % 6);

  String randomSuffix = String.fromCharCodes(
  List.generate(suffixLength, (_) => 65 + _rng.nextInt(26))
);

  String fullHash = randomPrefix + encodedString + randomSuffix;

  return fullHash;
}

void decode(String hash) {
  print("decoding");

  List<int> values = hash.codeUnits;

  int start = values.indexOf(90);

  print(
      "Start Index: $start, Values: ${values.map((v) => String.fromCharCode(v)).join()}");

  if (start == -1 || start + 15 > values.length) {
    return;
  }

  int shift = values[start + 1] - 48 - 17;
  List<int> shiftedValues = values.map((v) => v - shift - 17).toList();

  int number = int.parse(
      String.fromCharCodes(shiftedValues.sublist(start + 2, start + 12)));
  int amt = int.parse(
      String.fromCharCodes(shiftedValues.sublist(start + 12, start + 15)));

  print("Number: $number, amt: $amt");

}

void main() {
  // Example usage:
  String phone = "0115584442"; // 11 digits
  // String phone = "0110382792"; // 11 digits
  String amt = "90"; // 3 digits
  int key = 9; // Single digit key for the shift

  String hash = generateHash(phone, amt, key);
  print("Generated Hash: $hash");

  decode(hash);
}


// VDTMFZJJKKOORNNNLJOJNDBKQDHSO - 0115584442, 50
// VOPHBZJJQJKORKMMQJLJRKZRUVVCS - 0701581337, 20
// HGRNDZJJKKOORNNNLJJJQVKULTWVV - 0115584442, 90