import 'package:bsat/components/header.dart';
import 'package:bsat/components/profile_card.dart';
import 'package:bsat/screens/online_management/paired_devices.dart';
import 'package:bsat/screens/online_management/login.dart';
import 'package:bsat/screens/online_management/my_online_presence.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/screens/settings/coming_soon.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../components/dialogs/confirm_delete_dialog.dart';
import '../../services/auth_service.dart';

class OnlineManagementScreen extends StatefulWidget {
  const OnlineManagementScreen({super.key});

  @override
  State<OnlineManagementScreen> createState() => _OnlineManagementScreenState();
}

class _OnlineManagementScreenState extends State<OnlineManagementScreen> {
  // var myFirebaseAuth = MyFirebaseAuth();

  String name = "John Doe";
  String webLink = "www.johndoe.com";
  String email = "john.doe@example.com";
  int numberOfDevices = 3;

  bool isSignedIn = true;
  String myDeviceId = '';

  bool isOnline = true;

  @override
  void initState() {
    super.initState();

    checkIfLoggedIn();

    // setState(() => isSignedIn = myFirebaseAuth.isSignedIn());
  }

  void init() async {
    // SocketService().init();
  }

  void checkIfLoggedIn() async {
    // isSignedIn = await myFirebaseAuth.isSignedIn();
    isSignedIn = await AuthService().isLoggedIn();

    if (!isSignedIn && mounted) {
      // Navigate to login if not signed in
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(
          builder: (context) => LoginPage(),
        ),
      );
    } else {
      // Fetch user details if needed
      SharedPreferencesService sharedPreferencesService =
          SharedPreferencesService();

      name = await sharedPreferencesService.getUserName() ?? "Bingwa";
      webLink =
          "https://bingwa.bsat.co.ke/${await sharedPreferencesService.getLinkExtension()}" ??
              "bingwa";
      email = await sharedPreferencesService.getUserEmail() ?? "";
      setState(() {});
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, 'Online Management'),
            Padding(
              padding: kPagePaddingInsets,
              child: ProfileCard(
                name: name,
                webLink: webLink,
                numberOfDevices: numberOfDevices,
                email: email,
              ),
            ),
            Container(
              margin: kPagePaddingInsets,
              width: double.infinity,
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(kBorderRadius),
                image: DecorationImage(
                  image: AssetImage('assets/images/mesh.png'),
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.cover,
                  opacity: 0.1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Premium Subscription Expiry (online + offline features)",
                    style: TextStyle(
                        color: kPrimaryColor, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: kPagePadding),
                  Text(
                    "31${interpunct}02${interpunct}2025 12:00hrs",
                  ),
                ],
              ),
            ),
            _actionButton(
              context,
              title: 'Sell data online + buy for another number',
              subtitle: 'Online Presence',
              icon: Icon(CupertinoIcons.link, color: kIndigoColor),
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => MyOnlinePresencePage(),
                  ),
                );
              },
            ),
            _actionButton(
              context,
              title: 'share messages between trusted devices online',
              subtitle: 'Paired Devices',
              icon: Icon(CupertinoIcons.arrow_right_arrow_left,
                  color: kPrimaryColor),
              onTap: () async {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => ForwardReceiveOnlinePage(),
                  ),
                );
              },
            ),
            _actionButton(
              context,
              title: 'view/manage your phones through a common dashboard',
              subtitle: 'Remote Device Control',
              icon: Icon(CupertinoIcons.device_laptop, color: kErrorColor),
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => ComingSoonPage(),
                  ),
                );
              },
            ),
            _actionButton(
              context,
              title: 'End Session',
              subtitle: 'Sign out',
              icon: Icon(CupertinoIcons.power, color: kErrorColor),
              onTap: () async {
                bool confirmed = await showConfirmDeleteDialog(
                      context,
                      title: "Confirm Sign Out",
                      message:
                          "Are you sure you want to sign out from all devices ?",
                    ) ??
                    false;

                if (!confirmed) return;

                await AuthService().logout();

                Navigator.of(context).popUntil((route) => route.isFirst);
              },
            ),
            const SizedBox(height: kPagePadding * 5),
          ],
        ),
      ),
    );
  }

  InkWell _actionButton(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Function() onTap,
    required Icon icon,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: kPagePaddingInsets,
        margin: const EdgeInsets.only(
          top: kPagePadding,
          left: kPagePadding,
          right: kPagePadding,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      icon,
                      const SizedBox(width: kPagePadding / 2),
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      // fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 30,
            ),
          ],
        ),
      ),
    );
  }
}
