import 'dart:convert';

String? getAmount(String input) {
  // Remove commas and make lowercase for easier matching
  final cleaned = input.replaceAll(',', '').toLowerCase();

  // Regular expression to match numbers before or after currency text
  final regex = RegExp(
    r'(?:(((K?)sh(s?)[\s:]?)|kes[\s:]?)(\d{1,6}(?:,\d{3})*(?:\.\d+)?))|(\d{1,6}(?:,\d{3})*(?:\.\d+)?)[\s:]?((K?)sh(s?)|kes)',
    caseSensitive: false,
  );

  final match = regex.firstMatch(cleaned);
  if (match != null) {
    // Return the numeric part only (as string)
    // //print(match.groups());
    return match.group(0)!.replaceAll(RegExp(r'[^0-9.]'), '');
  }
  return null;
}

// Examples:
void main() {
  List<int> testList = [1, 2, 3, 4, 5];
  //print(testList);
  //print(jsonDecode(testList.toString()));
}
