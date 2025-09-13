import 'package:bsat/screens/subscriptions/subscription.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget noBalanceButton(BuildContext context) {
  return Column(
    children: [
      OutlinedButton(
      style: OutlinedButton.styleFrom(
      // foregroundColor: kErrorColor,
        // primary: kErrorColor,
      ),
        onPressed: () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const SubscriptionPage(),
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
        child: Text('Subscription expired. Click to renew', style: TextStyle(fontWeight: FontWeight.bold, color: kErrorColor,),),
      ),
      const SizedBox(height: kPagePadding * 1.5),
    ],
  );
}
