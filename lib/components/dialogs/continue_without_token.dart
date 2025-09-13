import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../screens/onboarding/permissions.dart';

Future<void> continueWithoutCodeDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: const Text('Continue without code?'),
        actions: [
          TextButton(
            onPressed: () async {
              // sqliteService
              //     .deleteStuff(id, table)
              //     .then((value) => Navigator.pop(context));
              Navigator.pop(context);
              Navigator.of(context).push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const PermissionsPage(),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    // Define your custom animation here
                    // return FadeTransition(opacity: animation, child: child);
                    return CupertinoPageTransition(
                      primaryRouteAnimation: animation,
                      secondaryRouteAnimation: secondaryAnimation,
                      linearTransition: true,
                      child: child,
                    );
                  },
                ),
              );
            },
            child: const Row(
            mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('Continue'),
                Icon(CupertinoIcons.chevron_compact_right),
              ],
            ),
          ),
        ],
      );
    },
  );
}
