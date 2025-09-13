import 'package:bsat/screens/settings/settings.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

Widget appPausedButton(BuildContext context, {String? text, Function()? onTap}) {
  return Column(
    children: [
      OutlinedButton(
        style: OutlinedButton.styleFrom(
            // foregroundColor: kErrorColor,
            // primary: kErrorColor,
            ),
        onPressed: onTap ??
         () {
          Navigator.of(context).push(
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) =>
                  const SettingsPage(),
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
        child: Text(
          text ?? 'Some features paused. Resume?',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: kErrorColor,
          ),
        ),
      ),
      const SizedBox(height: kPagePadding),
    ],
  );
}
