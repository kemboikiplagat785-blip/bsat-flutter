import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<bool?> checkOffersDialog(
  BuildContext context,
) {
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text(
          '! Important',
          style: TextStyle(color: kErrorColor),
        ),
        content: const Text(
            'Offers might have changed. Please check them and proceed.'),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.pop(context, true);
            },
            child: Text(
              'Continue',
            ),
          ),
        ],
      );
    },
  );
}
