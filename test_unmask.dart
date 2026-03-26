void main() {
  String text = "UCOB9AI5VK Confirmed.You have received Ksh2.00 from ANTONY  NJAU 0790***279 on 24/3/26 at 11:59 PM  New M-PESA balance is Ksh9,133.00. To view the Full Number, forward this message to 334.";
  String number = "0790133279";
  
  final RegExp mpesaMaskedPattern = RegExp(r'(?:254|0|\+254)[17]\d*[\*xX]+[\d\*xX]*', caseSensitive: false);
  // print(text.replaceAll(mpesaMaskedPattern, number));
}
