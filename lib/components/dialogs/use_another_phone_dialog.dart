import 'package:bsat/screens/foward_sms.dart';
import 'package:bsat/screens/online_management/online_management.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Future<void> showUseAnotherPhoneDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: false, // User must tap button!
    builder: (BuildContext context) {
      return AlertDialog(
        // backgroundColor: Theme.of(context).cardColor,
        title: const Text('Use Another Phone'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const OnlineManagementScreen(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
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
              child: Container(
                padding: kPagePaddingInsets,
                margin: kPagePaddingInsets / 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Online",
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          "Extra costs apply",
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    Spacer(),
                    Icon(CupertinoIcons.chevron_right),
                  ],
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const ForwardSmsPage(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
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
              child: Container(
                padding: kPagePaddingInsets,
                margin: kPagePaddingInsets / 2,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Offline (sms)",
                          style: TextStyle(fontSize: 18),
                        ),
                        Text(
                          "Carrier costs apply",
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    Spacer(),
                    Icon(CupertinoIcons.chevron_right),
                  ],
                ),
              ),
            ),
          ],
        ),
        actions: <Widget>[
          TextButton(
            child: const Text('Cancel'),
            onPressed: () {
              Navigator.of(context).pop();
            },
          ),
        ],
      );
    },
  );
}
