import 'package:another_telephony/telephony.dart';
import 'package:bsat/services/background_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../components/hero.dart';
import '../../utils/constants.dart';
import './choose_cards.dart';

class PermissionsPage extends StatefulWidget {
  const PermissionsPage({super.key});

  @override
  State<PermissionsPage> createState() => _PermissionsPageState();
}

class _PermissionsPageState extends State<PermissionsPage> {
  final telephony = Telephony.instance;

  final _sharedPreferencesService = SharedPreferencesService();

  @override
  void initState() {
    super.initState();

    // checkAndProceed();
  }

  Future<bool> _requestPhoneAndSmsPermissions() async {
    try {
      return await telephony.requestPhoneAndSmsPermissions ?? false;
    } catch (e) {
      // The permission plugin throws instead of resolving to false when the
      // user denies the SMS/phone permission dialog. Treat that the same as
      // a denial rather than letting it crash the app.
      debugPrint("SMS/phone permission request failed: $e");
      return false;
    }
  }

  Future<void> askForDefaultSms() async {
    bool isRequestGranted = await _requestPhoneAndSmsPermissions();

    if (isRequestGranted) {
      print("App is now the default SMS app!");
    } else {
      print("User denied the request.");
    }
  }

  void checkAndProceed(BuildContext context) async {
    // await Permission.notification.isDenied.then((value) {
    //   if (value) return;
    // });
    await Permission.notification.request();
    if ((await _requestPhoneAndSmsPermissions()) &&
        (await Permission.notification.isGranted)) {
      await askForDefaultSms();
      initializeBackgroundService();

      _sharedPreferencesService.setRunningStatus(true);
      // _sharedPreferencesService.getRunningStatus().then((value) {
      // if (value ?? false) {
      // Navigator.pop(context);
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ChooseCardPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              const ChooseCardPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    // checkAndProceed();
    var size = MediaQuery.of(context).size;
    var textTheme = Theme.of(context).textTheme;
    return Scaffold(
      body: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          const MyHeroWidget(),
          const Spacer(
            flex: 1,
          ),
          const Padding(
            padding: kPagePaddingInsets,
            child: Text(
              'The following permissions are required for the app to work. Please enable them.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  // color: kDullColor,
                  ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(kPagePadding * (3 / 4)),
            child: Flex(
              direction: Axis.horizontal,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kPagePadding / 4,
                      vertical: kPagePadding,
                    ),
                    child: Container(
                      padding: kPagePaddingInsets / 2,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'SMS',
                                style: kTitleText,
                              ),
                              const Spacer(),
                              Icon(
                                CupertinoIcons.captions_bubble,
                                size: textTheme.labelMedium?.fontSize,
                                color: Theme.of(context).indicatorColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 4),
                          Text(
                            'To automate reading incoming Bingwa requests.',
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kPagePadding / 4,
                      vertical: kPagePadding,
                    ),
                    child: Container(
                      padding: kPagePaddingInsets / 2,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Phone',
                                style: (kTitleText),
                              ),
                              const Spacer(),
                              Icon(
                                CupertinoIcons.phone_arrow_up_right,
                                size: textTheme.labelMedium?.fontSize,
                                color: Theme.of(context).indicatorColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 4),
                          Text(
                            'To automatically recommend Bingwa requests.',
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kPagePadding / 4,
                      vertical: kPagePadding,
                    ),
                    child: Container(
                      padding: kPagePaddingInsets / 2,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Notifications',
                                style: (kTitleText),
                              ),
                              Icon(
                                CupertinoIcons.bell,
                                size: textTheme.labelMedium?.fontSize,
                                color: Theme.of(context).indicatorColor,
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 4),
                          Text(
                            'To keep the app active in the background.',
                            style: textTheme.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          Hero(
            tag: '',
            child: InkWell(
              onTap: () => checkAndProceed(context),
              child: Container(
                padding: kPagePaddingInsets,
                width: size.width - (kPagePadding * 2),
                child: Center(
                  child: Text(
                    '$interpunct $interpunct $interpunct Grant Permissions $interpunct',
                    style: textTheme.titleLarge!.merge(
                      const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
