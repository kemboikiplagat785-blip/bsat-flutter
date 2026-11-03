/// How My Offers is ordered. [custom] is the order the user dragged the offers
/// into.
enum OfferSort {
  amountAscending('Amount: low to high'),
  amountDescending('Amount: high to low'),
  name('Name: A to Z'),
  pausedLast('Paused last'),
  custom('My order');

  final String label;

  const OfferSort(this.label);

  static OfferSort fromName(String? name) => OfferSort.values.firstWhere(
        (sort) => sort.name == name,
        orElse: () => OfferSort.amountAscending,
      );
}

/// [rows] (offer rows of My Offers) in [sort] order. In [OfferSort.custom],
/// offers missing from [customOrder] (added since the last drag) come last.
List<Map<String, dynamic>> sortOfferRows(
  List<Map<String, dynamic>> rows,
  OfferSort sort,
  List<int> customOrder,
) {
  final position = {
    for (var index = 0; index < customOrder.length; index++)
      customOrder[index]: index,
  };
  num amount(Map<String, dynamic> row) =>
      num.tryParse(row['amount']?.toString() ?? '') ?? 0;
  String name(Map<String, dynamic> row) =>
      (row['offerName']?.toString() ?? '').toLowerCase();
  int paused(Map<String, dynamic> row) => (row['enabled'] ?? 1) == 1 ? 0 : 1;

  int primary(Map<String, dynamic> a, Map<String, dynamic> b) => switch (sort) {
        OfferSort.amountAscending => 0,
        OfferSort.amountDescending => amount(b).compareTo(amount(a)),
        OfferSort.name => name(a).compareTo(name(b)),
        OfferSort.pausedLast => paused(a).compareTo(paused(b)),
        OfferSort.custom => (position[a['id']] ?? customOrder.length)
            .compareTo(position[b['id']] ?? customOrder.length),
      };

  return [...rows]..sort((a, b) {
      var order = primary(a, b);
      if (order == 0) order = amount(a).compareTo(amount(b));
      if (order == 0) {
        order = (a['code']?.toString() ?? '')
            .compareTo(b['code']?.toString() ?? '');
      }
      return order;
    });
}

/// Whether [query] appears in the amount, name or USSD code of [row].
bool offerRowMatches(Map<String, dynamic> row, String query) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  return [row['amount'], row['offerName'], row['code']]
      .any((value) => value.toString().toLowerCase().contains(needle));
}
