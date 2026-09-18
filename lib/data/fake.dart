import 'package:bsat/utils/constants.dart';
import 'package:another_telephony/telephony.dart';

import '../services/sqlite_service.dart';
import '../utils/date_ops.dart';

class DummyDataInserter {
  final SQLiteService _sqliteService = SQLiteService();

  Future<void> insertFakeTransactions(int count) async {
    final subscriptions = await Telephony.instance.getSubscriptionList();
    for (int i = 0; i < count; i++) {
      Map<String, dynamic> fakeTransaction = {
        'initialMessage': 'Sample initial message',
        'transactionId': 'sample-transaction-id-$i',
        'number': 729286254,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': '*144#',
        'ussdReply': 'Sample $i USSD reply',
        'amount': (i % 4 == 0)
            ? 20
            : (i % 4 == 1)
                ? 19
                : (i % 4 == 2)
                    ? 55
                    : 99,
        'smsDate': getNormalDate(DateTime.now()),
        'smsTime': getNormalTime(DateTime.now()),
        'status':
            i % 2 == 0 ? TransactionStatuses.done : TransactionStatuses.error,
        'simSubId':
            subscriptions.isNotEmpty ? subscriptions.first.subscriptionId : -1,
        'source': i % 2 == 0 ? 'online' : 'offline',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry': 1,
      };

      await _sqliteService.insertStuff(fakeTransaction, 'transactions');
    }
  }
}
