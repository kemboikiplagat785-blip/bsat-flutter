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
    };
  }
}
