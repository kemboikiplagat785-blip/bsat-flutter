import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<bool?> deleteUssdDialog(
  BuildContext context,
  int id,
  String table,
) {
  var sqliteService = SQLiteService();
  return showDialog<bool>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Delete'),

        actions: [
          IconButton(
            onPressed: () async {
              sqliteService.deleteStuff(id, table).then((value) {
                Navigator.pop(context, true);
              });
            },
            icon: const Icon(
              CupertinoIcons.delete,
              color: kErrorColor,
            ),
          ),
        ],
      );
    },
  );
}
