void main() {
  String number = "0742342297";
  String message = "from 254702xxx783 name";
  String message2 = "from 0742xxx297 name";

  // First check if the masked string matches the provided number
  // Normalize number
  String normNum = number.replaceAll('+', '');
  if (normNum.startsWith('254')) normNum = '0${normNum.substring(3)}';
  
  // print("Norm num: $normNum");

  final RegExp mpesaMaskedPattern = RegExp(
    r'(?:254|0|\+254)[17]\d*[\*xX]+[\d\*xX]*',
    caseSensitive: false,
  );
  
  Match? match = mpesaMaskedPattern.firstMatch(message);
  if (match != null) {
    String maskedToken = match.group(0)!;
    String normMask = maskedToken.replaceAll('+', '').replaceAll(RegExp(r'x|X|\*'), r'\d');
    if (normMask.startsWith('254')) normMask = '0${normMask.substring(3)}';
    
    // print("Match 1: $maskedToken -> $normMask");
    // print("Regex match: ${RegExp('^$normMask\$').hasMatch(normNum)}");
  }
}
