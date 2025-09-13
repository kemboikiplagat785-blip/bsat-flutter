class Numbers {
  static String formatNumber(int number, {int? leastK}) {
    if (number >= 1000000) {
      int millions = number ~/ 1000000;
      int remainder = (number % 1000000) ~/ 100000;
      return remainder == 0
          ? '${millions}M'
          : '${millions}.${remainder}M';
    } else if (number >= (leastK ?? 10000)) {
      int thousands = number ~/ 1000;
      int remainder = (number % 1000) ~/ 100;
      return remainder == 0
          ? '${thousands}k'
          : '${thousands}.${remainder}k';
    } else if (number >= 1000) {
      // Format with comma for 1,000 - 9,999
      return number.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]},',
      );
    } else {
      return number.toString();
    }
  }
}