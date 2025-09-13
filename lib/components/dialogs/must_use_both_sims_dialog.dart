import 'package:flutter/material.dart';


Future<void> mustUseBothSimsDialog(BuildContext context) {
  var textTheme = Theme.of(context).textTheme;
  return showDialog<void>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Important!',
              style: textTheme.titleLarge,
            ),
          ],
        ),
        content: const Text(
            'Due to Android\'s Privacy Rules, it isn\'t possible to know a text message\'s sim card. Both sim carrds have to be selected.'),
        actions: [
          TextButton(
            onPressed: () {
               Navigator.of(context).pop();
            },
            child: const Text('Okay'),
          ),
        ],
      );
    },
  );
}
