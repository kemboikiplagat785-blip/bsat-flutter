import 'package:bsat/components/hero.dart';
import 'package:bsat/screens/onboarding/updated_toolkit.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../utils/constants.dart';
import '../dashboard/dashboard.dart';

class AutomatePageSplash extends StatefulWidget {
  const AutomatePageSplash({super.key});

  @override
  State<AutomatePageSplash> createState() => AutomatePageSplashState();
}

class AutomatePageSplashState extends State<AutomatePageSplash> {

  @override
  Widget build(BuildContext context) {
    var size = MediaQuery.of(context).size;
    var textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        children: [
          const Spacer(),
          myHeroWidget(context),
          const Spacer(),
          Image.asset('assets/images/automate.png'),
          const Spacer(),
          Hero(
            tag: 'next-btn',
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const UpdatedToolkitPageSplash(),
                    // StatsPage(),
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
                child: Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$interpunct Next $interpunct $interpunct $interpunct',
                        style: textTheme.titleLarge!.merge(
                          const TextStyle(
                            // color: kPrimaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: kPagePadding * 3),
        ],
      ),
    );
  }
}
