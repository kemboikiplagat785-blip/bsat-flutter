import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';

Future<bool?> showConfirmDeleteDialog(BuildContext context,
    {String? title, String? message, String? btnText}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title ?? 'Confirm'),
      content: Text(message ?? 'Are you sure you want to delete this item?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: kErrorColor.withValues(alpha: .1),
          ),
          child: Text(
            btnText ?? 'Ok',
            style: const TextStyle(
              color: kErrorColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    ),
  );
}
