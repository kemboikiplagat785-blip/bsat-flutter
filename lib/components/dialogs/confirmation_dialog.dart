import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<bool> confirmationDialog(BuildContext context, String text) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(text),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Continue'),
                Icon(CupertinoIcons.chevron_compact_right),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context, false);
            },
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  ).then((value) => value ?? false);
}
