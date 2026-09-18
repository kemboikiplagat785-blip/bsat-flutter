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

// {messageId: UE8B93OUYS,
// body: UE8B93OUYS Confirmed.You have received Ksh9.00 from ANTONY  NJAU 0790133279 on 8/5/26 at 4:41 PM  New M-PESA balance is Ksh41,826.70. To view the Full Number, forward this message to 334.,
// type: forwarded_sms,
// title: Forwarded Message}
