import 'package:flutter/material.dart';

Future<String?> showAskDeviceNameDialog(
    BuildContext context, String initialName) {
  TextEditingController deviceNameController =
      TextEditingController(text: initialName);

  return showDialog<String>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Device Name'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Please enter a name for your device.',
            ),
            TextField(
              controller: deviceNameController,
              decoration: InputDecoration(
                hintText: 'Device Name',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              if (deviceNameController.text.isEmpty) {
                return;
              }
              Navigator.of(context).pop(deviceNameController.text);
            },
            child: Text('Save'),
          ),
        ],
      );
    },
  );
}
