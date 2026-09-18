import 'package:flutter/material.dart';

Future<String?> showForwardTextDialog(
  BuildContext context,
  int toForward,
) {
  final TextEditingController textController = TextEditingController();

  textController.text = "0$toForward";

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Number'),
        content: TextField(
          controller: textController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: '07...',
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(textController.text);
            },
            child: Text('Forward'),
          ),
        ],
      );
    },
  );
}
