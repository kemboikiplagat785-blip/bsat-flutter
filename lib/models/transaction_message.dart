class TransactionMessage {
  final String? body;
  final int? subscriptionId;
  final int? date;
  final String? address;

  TransactionMessage({
    this.body,
    this.subscriptionId,
    this.date,
    this.address,
  });
}
