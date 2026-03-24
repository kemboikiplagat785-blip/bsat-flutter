import 'dart:io';

void main() {
  var file = File('lib/services/sms_sevice.dart');
  var content = file.readAsStringSync();
  
  var newContent = content.replaceAll(RegExp(r'String unmaskNumberInMessage[\s\S]*?return message.replaceAll\(maskedPattern, number\);\s*\}'), '''String unmaskNumberInMessage(String number, String message) {
  // First, explicitly check for Kenyan/MPesa-like masked numbers (07xx***xxx, 2547xx***xxx, etc.)
  final RegExp mpesaMaskedPattern = RegExp(
    r'(?:254|0|\\+254)[17]\\d*[\\*xX]+[\\d\\*xX]*',
    caseSensitive: false,
  );
  
  if (mpesaMaskedPattern.hasMatch(message)) {
    return message.replaceAll(mpesaMaskedPattern, number);
  }

  // Strip non-numeric characters to safely get the last 3 digits
  final cleanNumber = number.replaceAll(RegExp(r'\\D'), '');

  // If the number is too short, we can't reliably find a mask
  if (cleanNumber.length < 3) {
    return message;
  }

  final last3 = cleanNumber.substring(cleanNumber.length - 3);

  final RegExp maskedPattern = RegExp(
    r'(?:\\+?\\d{1,4}[\\s\\-]*)?(?:[\\*Xx#]{1,4}[\\s\\-]*)+[\\d\\*Xx#\\s\\-]*' +
        last3 +
        r'\\b',
  );

  return message.replaceAll(maskedPattern, number);
}''');
  
  file.writeAsStringSync(newContent);
}
