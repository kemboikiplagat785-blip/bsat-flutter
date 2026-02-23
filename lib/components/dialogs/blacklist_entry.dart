import 'package:bsat/controllers/transaction_controller.dart';
import 'package:flutter/material.dart';

Future<String?> showBlacklistEntryDialog(BuildContext context) {
  final TextEditingController textController = TextEditingController();

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Number'),
        content: TextField(
          controller: textController,
          // keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '07...',
          ),
        ),
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
                  .changeBlackListStatus(int.parse(textController.text));
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
