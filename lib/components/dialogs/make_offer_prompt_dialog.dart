import 'package:bsat/components/dialogs/make_offer_tutorial_dialog.dart';
import 'package:bsat/screens/dashboard/dashboard.dart';
import 'package:bsat/screens/dashboard/home.dart';
import 'package:bsat/screens/offers/edit_offer.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';

Future<void> makeOfferPromptDialog(BuildContext context) {
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
            InkWell(
              onTap: () => Navigator.pop(context),
              child: Row(
                children: [
                  Text('Skip'),
                  const SizedBox(width: kPagePadding / 4),
                  Icon(CupertinoIcons.forward),
                ],
              ),
            )
          ],
        ),
        content: const Text(
            'You have to make offers and rules for the app to work.\n\nYou can add/edit them from the Settings page.'),
        actions: [
          TextButton(
            onPressed: () {
              makeOfferTutorialDialog(context);
            },
            child: const Text('How to make offers'),
          ),
          TextButton(
            onPressed: () {
              // Navigator.of(context).pop();
              // editUSSDEntry(context);
              // Navigator.pop(context);
              Navigator.of(context)
                  .push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      const EditOfferPage(),
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
                // )
                //     .then((value) {
                //   Navigator.of(context).push(
                // PageRouteBuilder(
                //   pageBuilder: (context, animation, secondaryAnimation) =>
                //       const DashBoardPage(),
                //   transitionsBuilder:
                //       (context, animation, secondaryAnimation, child) {
                //     return CupertinoPageTransition(
                //       primaryRouteAnimation: animation,
                //       secondaryRouteAnimation: secondaryAnimation,
                //       linearTransition: true,
                //       child: child,
                //     );
                //   },
                // ),
                //   );
                // }
              )
                  .then((value) {
                // Navigator.pop(context);
                Navigator.popUntil(context, (route) => route.isFirst);
                // Navigator.pop(context);
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const HomePage(),
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
              'Make an offer',
              style: TextStyle(color: kPrimaryColor),
            ),
          ),
        ],
      );
    },
  );
}
