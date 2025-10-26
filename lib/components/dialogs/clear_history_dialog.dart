import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../screens/onboarding/permissions.dart';
import 'loading_dialog.dart';
import 'success_dialog.dart';

class ClearHistoryDialog extends StatefulWidget {
  const ClearHistoryDialog({super.key});

  @override
  State<ClearHistoryDialog> createState() => _ClearHistoryDialogState();
}

class _ClearHistoryDialogState extends State<ClearHistoryDialog> {
  DateTime startDate = DateTime.now();
  DateTime endDate = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Clear history'),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Select Timeline'),
          const SizedBox(height: kPagePadding),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: startDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && picked != startDate) {
                    startDate = picked;
                    setState(() {});
                  }
                },
                child: Text(
                  "From: ${startDate.day}/${startDate.month}/${startDate.year}",
                  style: TextStyle(
                    color: kPrimaryColor,
                  ),
                ),
              ),
              InkWell(
                onTap: () async {
                  DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: endDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null && picked != endDate) {
                    endDate = picked;
                    setState(() {});
                  }
                },
                child: Text(
                  "To: ${endDate.day}/${endDate.month}/${endDate.year}",
                  style: TextStyle(
                    color: kPrimaryColor,
                  ),
                ),
              ),
            ],
          )
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            Navigator.of(context).pop();
          },
          child: Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            showLoadingDialog(context);
            await SQLiteService().deleteWhere(
              'transactions',
              'timeStamp > ? AND timeStamp < ?',
              [
                startDate.millisecondsSinceEpoch,
                endDate.millisecondsSinceEpoch
              ],
            );
            Navigator.pop(context);
            Navigator.pop(context);
            showSuccessDialog(context, text: 'History cleared successfuly');
          },
          child: Text('Clear History'),
        ),
      ],
    );
  }
}
