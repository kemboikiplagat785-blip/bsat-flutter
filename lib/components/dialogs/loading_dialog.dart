import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showLoadingDialog(BuildContext context, {String? text}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) {
      return SimpleDialog(
        // backgroundColor: Colors.white,
        children: [
          const SizedBox(height: kPagePadding),
          Text(""),
          const Center(
            child: CupertinoActivityIndicator(),
          ),
          const SizedBox(height: kPagePadding),
          Center(
            child: Text(
              text ?? "",
              style: const TextStyle(
                // color: Colors.black,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      );
    },
  );
}
