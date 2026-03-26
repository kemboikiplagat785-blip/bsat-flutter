void main() {
  String number = "0116675236";
  String message = "from 254116xxx236 name";
  String message2 = "from 0116xxx236 name";

  String? result2 = _test(number, message2);
  print("Result2: $result2");
}

String? _test(String number, String message) {
  final RegExp mpesaMaskedPattern = RegExp(
    r'(?:254|0|\+254)[17]\d*[\*xX]+[\d\*xX]*',
    caseSensitive: false,
  );

  Match? match = mpesaMaskedPattern.firstMatch(message);
  if (match != null) {
    String maskedToken = match.group(0)!;
    
    // Normalize both numbers for comparison
    String normNum = number.replaceAll('+', '');
    if (normNum.startsWith('254')) normNum = '0${normNum.substring(3)}';
    
    String normMask = maskedToken.replaceAll('+', '').replaceAll(RegExp(r'x|X|\*'), r'\d');
    if (normMask.startsWith('254')) normMask = '0${normMask.substring(3)}';
    
    // Check if the provided number actually matches this mask
    if (RegExp('^$normMask\$').hasMatch(normNum)) {
      return message.replaceFirst(maskedToken, number);
    }
  }
  return null; // Don't fall through to other logic if there's a M-PESA mask but doesn't match
}
