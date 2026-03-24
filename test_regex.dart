void main() {
  String messageBody = "from 254712***345 John O'Doe í´© 0712345678";
  RegExp nameRegex = RegExp(r'from\s+(?:(?:254|0[17])[\d\*xX\s]+)?\s*([^\d]+?)\s+\d', caseSensitive: false);
  Match? nameMatch = nameRegex.firstMatch(messageBody);
  String name = nameMatch?.group(1)?.trim() ?? "";
  print(name);
  
  if (name.isEmpty) {
    nameRegex = RegExp(r'254[\dxX*]{9,12} ([^\d]+)');
    nameMatch = nameRegex.firstMatch(messageBody);
    name = nameMatch?.group(1)?.trim() ?? "";
  }
}
