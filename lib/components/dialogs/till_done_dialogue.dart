import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';


Future<bool?> tillDoneDialogue(
  BuildContext context,
  Widget content,
  Future Function() action, // Ensuring that the action returns a Future
) async {
  // Show the dialog and run the action asynchronously
  showDialog<bool>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        content: content,
      );
    },
  );

  // Wait for the action to complete
  await action();

  // After the action is completed, dismiss the dialog
  Navigator.of(context).pop(true); // Dismiss with a positive result

  return true; // Optionally return a value indicating completion
}
