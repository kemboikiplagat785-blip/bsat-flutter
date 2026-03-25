void main() {
  String text1 = "from 254702xxx783 name";
  String text2 = "from 0742xxx297 name";
  String num1 = "0742342297";
  
  final RegExp mpesaMaskedPattern = RegExp(
    r'(?:254|0|\+254)[17]\d*[\*xX]+[\d\*xX]*',
    caseSensitive: false,
  );
  
  print(text1.replaceAll(mpesaMaskedPattern, num1));
  print(text2.replaceAll(mpesaMaskedPattern, num1));
}
