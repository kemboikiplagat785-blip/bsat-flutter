import 'package:bsat/screens/subscriptions/subscription.dart';
import 'package:bsat/screens/dashboard.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<void> chargesDialog(BuildContext context) {
  var textTheme = Theme.of(context).textTheme;
  return showDialog<void>(
    barrierDismissible: false,
    context: context,
    builder: (BuildContext context) {
      return AlertDialog(
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Important!',
              style: textTheme.titleLarge,
            ),
          ],
        ),
        content: const Text(
            'The app autoatically deducts airtime worth KSH 15 / day to function. '),
        actions: [
          TextButton(
            onPressed: () {
              // Navigator.of(context).pop();
              // editUSSDEntry(context);
              // Navigator.pop(context);
              Navigator.of(context)
                  .push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const SubscriptionPage(),
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
              )
                  .then((value) {
                // Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
                // Navigator.pop(context);
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const DashBoardPage(),
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
              });
            },
            child: const Text(
              'See other packages',
              style: TextStyle(color: kPrimaryColor),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.popUntil(context, (route) => route.isFirst);
              // Navigator.pop(context);
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const DashBoardPage(),
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
              ).then((value) => Navigator.of(context).pop());
            },
            child: const Text('Okay'),
          ),
        ],
      );
    },
  );
}
