import 'package:flutter/material.dart';

import '../../screens/settings/accessibility_setup.dart';

Future<String?> showAccessibilityPermissionDialog(BuildContext context) {

  return showDialog<String>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Text('Accessibility permission required'),
        content: Text(
          'Please enable the accessibility permission for the app to work properly.',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('Already enabled'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => AccessibilityTutorialScreen(),
                ),
              );
            },
            child: Text('Enable'),
          ),
        ],
      );
    },
  );
}
