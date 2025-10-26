import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<void> showSuccessDialog(BuildContext context, {required String text}) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Center(
            // child: Text("Success"),
            ),
        // backgroundColor: Colors.white,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: kPagePadding * 2),
            const Icon(
              CupertinoIcons.checkmark_alt,
              size: 30,
              color: kPrimaryColor,
            ),
            const SizedBox(height: kPagePadding * 2),
            Text(
              text,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    },
  );
}
