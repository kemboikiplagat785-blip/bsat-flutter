class MyTransaction {
  late int id;
  final String initialMessage;
  final String transactionId;
  final int number;
  final DateTime dateTime;
  final String ussdDialed;
  final String ussdReply;
  final int amount;
  final String status;
  final int simSubId;
  final String source;
  final int timeStamp;
  final int canRetry;
  final String smsDate;
  final String smsTime;
  String? forwardingJobId;
  String? forwardingSenderDeviceName;
  String? forwardingRecipientDeviceName;
  final int? parentTransactionId;
  final int? requiredTopUp;
  final int? targetAmount;
  final int? targetOfferId;
  final bool awaitingTopUp;
  final String? topUpTransactionId;

  MyTransaction({
    required this.id,
    required this.initialMessage,
    required this.transactionId,
    required this.number,
    required this.dateTime,
    required this.ussdDialed,
    required this.ussdReply,
    required this.amount,
    required this.status,
    required this.simSubId,
    required this.source,
    required this.timeStamp,
    required this.canRetry,
    required this.smsDate,
    required this.smsTime,
    this.forwardingJobId,
    this.forwardingSenderDeviceName,
    this.forwardingRecipientDeviceName,
    this.parentTransactionId,
    this.requiredTopUp,
    this.targetAmount,
    this.targetOfferId,
    this.awaitingTopUp = false,
    this.topUpTransactionId,
  });

  factory MyTransaction.fromMap(Map<String, dynamic> map) {
    return MyTransaction(
      id: map['id'],
      initialMessage: map['initialMessage'],
      transactionId: map['transactionId'],
      number: map['number'],
      dateTime: DateTime.fromMillisecondsSinceEpoch(map['timeStamp']),
      ussdDialed: map['ussdDialed'],
      ussdReply: map['ussdReply'],
      amount: map['amount'],
      status: map['status'],
      simSubId: map['simSubId'],
      source: map['source'],
      timeStamp: map['timeStamp'],
      canRetry: map['canRetry'],
      smsDate: map['smsDate'],
      smsTime: map['smsTime'],
      forwardingJobId: map['forwardingJobId']?.toString(),
      forwardingSenderDeviceName: map['forwardingSenderDeviceName']?.toString(),
      forwardingRecipientDeviceName:
          map['forwardingRecipientDeviceName']?.toString(),
      parentTransactionId: int.tryParse(map['parentTransactionId']?.toString() ?? ''),
      requiredTopUp: int.tryParse(map['requiredTopUp']?.toString() ?? ''),
      targetAmount: int.tryParse(map['targetAmount']?.toString() ?? ''),
      targetOfferId: int.tryParse(map['targetOfferId']?.toString() ?? ''),
      awaitingTopUp: int.tryParse(map['awaitingTopUp']?.toString() ?? '') == 1 ||
          map['awaitingTopUp'] == true,
      topUpTransactionId: map['topUpTransactionId']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'initialMessage': initialMessage,
      'transactionId': transactionId,
      'number': number,
      'ussdDialed': ussdDialed,
      'ussdReply': ussdReply,
      'amount': amount,
      'status': status,
      'simSubId': simSubId,
      'source': source,
      'timeStamp': timeStamp,
      'canRetry': canRetry,
      'smsDate': smsDate,
      'smsTime': smsTime,
      'date': smsDate,
      'time': smsTime,
      'forwardingJobId': forwardingJobId,
      'forwardingSenderDeviceName': forwardingSenderDeviceName,
      'forwardingRecipientDeviceName': forwardingRecipientDeviceName,
      'parentTransactionId': parentTransactionId,
      'requiredTopUp': requiredTopUp,
      'targetAmount': targetAmount,
      'targetOfferId': targetOfferId,
      'awaitingTopUp': awaitingTopUp ? 1 : 0,
      'topUpTransactionId': topUpTransactionId,
    };
  }
}
