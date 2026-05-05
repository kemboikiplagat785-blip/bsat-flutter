import 'package:bsat/controllers/transaction_controller.dart';

class ServiceLocator {
  static TransactionController? _transactionController;

  static void setTransactionController(TransactionController controller) {
    _transactionController = controller;
  }

  static TransactionController getTransactionController() {
    if (_transactionController == null) {
      throw Exception('TransactionController not initialized');
    }
    return _transactionController!;
  }
}
