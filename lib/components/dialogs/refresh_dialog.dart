import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<bool?> refreshDialog(
  BuildContext context,
  Function callBack,
) {
  return showDialog<bool>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Refresh'),
        actions: [
          IconButton(
            onPressed: () => callBack(),
            icon: const Icon(
              CupertinoIcons.refresh,
              color: kPrimaryColor,
            ),
          ),
        ],
      );
    },
  );
}
