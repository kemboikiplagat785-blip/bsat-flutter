import 'package:bsat/screens/onboarding/permissions.dart';
import 'package:bsat/screens/stats/statistics.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/hero.dart';
import '../../utils/constants.dart';
import '../home/dashboard/dashboard.dart';

class UpdatedToolkitPageSplash extends StatefulWidget {
  const UpdatedToolkitPageSplash({super.key});

  @override
  State<UpdatedToolkitPageSplash> createState() =>
      UpdatedToolkitPageSplashState();
}

class UpdatedToolkitPageSplashState extends State<UpdatedToolkitPageSplash> {
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
          Image.asset('assets/images/suite.png'),
          const Spacer(),
          Hero(
            tag: 'next-btn',
            child: InkWell(
              onTap: () {
                Navigator.of(context).push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        // const FreeCodePage(),
                        const PermissionsPage(),
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
                        '$interpunct $interpunct Next $interpunct $interpunct',
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
