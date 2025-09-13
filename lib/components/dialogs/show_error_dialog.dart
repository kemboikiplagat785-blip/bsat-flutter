import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<void> showErrorDialog(
  BuildContext context,
  String title,
  String message,
) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              CupertinoIcons.clear_circled,
              size: 40,
              color: kErrorColor,
            ),
            const SizedBox(height: kPagePadding),
            Text(message),
          ],
        ),
      );
    },
  );
}
