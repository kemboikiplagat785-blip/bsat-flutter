import 'package:flutter/material.dart';

Future<void> showLoadingDialog(BuildContext context, {String? text}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return SimpleDialog(
        // backgroundColor: Colors.white,
        children: [
          Text(""),
          const Center(
            child: CircularProgressIndicator(),
          ),
          Text(
            text ?? "",
            style: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      );
    },
  );
}
