import 'package:bsat/controllers/transaction_controller.dart';
import 'package:flutter/material.dart';

Future<String?> showRetryDialog(BuildContext context) {
  final TextEditingController textController = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        // alignment: Alignment.center,
        title: Text('Retry Transactions'),
        content: null,
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(); // Close the dialog without saving
            },
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              TransactionController()
                  .addNumberToBlacklist(int.parse(textController.text));
              Navigator.of(context)
                  .pop(textController.text); // Return the entered text
            },
            child: Text('Save'),
          ),
        ],
      );
    },
  );
}
