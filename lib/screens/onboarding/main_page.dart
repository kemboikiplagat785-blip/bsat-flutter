import 'package:bsat/screens/dashboard/home.dart';
import 'package:bsat/screens/onboarding/automate_splash.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/hero.dart';
import '../../utils/constants.dart';
import '../dashboard/dashboard.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => OnboardingPageState();
}

class OnboardingPageState extends State<OnboardingPage> {
  final _sharedPreferencesService = SharedPreferencesService();

  void toDashBoard(BuildContext context) {
    Navigator.pop(context);
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            const HomePage(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return CupertinoPageTransition(
            primaryRouteAnimation: animation,
            secondaryRouteAnimation: secondaryAnimation,
            linearTransition: true,
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _sharedPreferencesService
        .getRunningStatus()
        .then((value) => value ?? false ? toDashBoard(context) : value);

    var size = MediaQuery.of(context).size;
    var textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        children: [
          const Spacer(),
          myHeroWidget(context),
          const Spacer(),
          Hero(
            tag: 'next-btn',
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        // const FreeCodePage(),
                        const AutomatePageSplash(),
                    // const OnboardingPage(),
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
                        'Next $interpunct $interpunct $interpunct $interpunct',
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
