import 'package:bsat/services/sms_sevice.dart';
import 'package:flutter/material.dart';

Future<String?> showForwardTextDialog(
  BuildContext context,
  String message,
  int toForward,
) {
  final TextEditingController textController = TextEditingController();

  textController.text = "0$toForward";

  message = message.substring(0, message.length > 160 ? 160 : message.length);

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
              if (textController.text.length < 10) return;
              if (textController.text.length == 12) {
                textController.text = textController.text
                    .substring(2, textController.text.length);
              }
              
              sendEvenInBackground(
                  '254${int.parse(textController.text)}', message);
              Navigator.of(context).pop(textController.text);
            },
            child: Text('Forward'),
          ),
        ],
      );
    },
  );
}
