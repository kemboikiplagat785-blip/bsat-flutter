import 'package:flutter/material.dart';

import 'package:flutter_accessibility_service/flutter_accessibility_service.dart';

Future<String?> showAskDeviceNameDialog(BuildContext context, String initialName) {
  TextEditingController _deviceNameController =
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
              controller: _deviceNameController,
              decoration: InputDecoration(
                hintText: 'Device Name',
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              if(_deviceNameController.text.isEmpty){
                return;
              }
              Navigator.of(context).pop(_deviceNameController.text);
            },
            child: Text('Save'),
          ),
        ],
      );
    },
  );
}
