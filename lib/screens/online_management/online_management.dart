import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/forward_receive.dart';
import 'package:bsat/screens/online_management/login.dart';
import 'package:bsat/screens/online_management/my_online_presence.dart';
import 'package:bsat/screens/settings/coming_soon.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../services/auth_service.dart';

class OnlineManagementScreen extends StatefulWidget {
  const OnlineManagementScreen({super.key});

  @override
  State<OnlineManagementScreen> createState() => _OnlineManagementScreenState();
}

class _OnlineManagementScreenState extends State<OnlineManagementScreen> {
  // var myFirebaseAuth = MyFirebaseAuth();

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
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          header(context, 'Online Management'),
          Container(
            padding: kPagePaddingInsets,
            child: Row(
              // spacing: kPagePadding / 2,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    backgroundColor: kPrimaryColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                    ),
                  ),
                  child: Text(
                    "Subscription expiry: ",
                    style: TextStyle(color: kIndigoColor),
                  ),
                ),
                Row(
                  children: [
                    IconButton(
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        backgroundColor: kIndigoColor.withOpacity(.1),
                      ),
                      onPressed: () {},
                      icon: Icon(CupertinoIcons.person, color: kIndigoColor),
                    ),
                    IconButton(
                      style: IconButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        backgroundColor: Theme.of(context).cardColor,
                      ),
                      onPressed: () async {
                        await AuthService().logout();
                      },
                      icon: Icon(CupertinoIcons.gear),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _actionButton(
            context,
            title: 'Sell data online + buy for another number',
            subtitle: 'My link',
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
            subtitle: 'Forward/receive requests',
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
        ],
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
