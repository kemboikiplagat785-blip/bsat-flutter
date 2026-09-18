import 'package:bsat/components/device_card.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/components/profile_card.dart';
import 'package:bsat/screens/online_management/paired_devices.dart';
import 'package:bsat/screens/online_management/login.dart';
import 'package:bsat/screens/online_management/my_online_presence.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/screens/settings/coming_soon.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'package:battery_plus/battery_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import '../../components/button_descriptive.dart';
import '../../components/dialogs/confirm_delete_dialog.dart';
import '../../services/auth_service.dart';
import 'portal.dart';
import 'register_device.dart';
import 'package:url_launcher/url_launcher.dart';

import 'webview.dart';

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
  String myDeviceName = 'Unknown Device';
  String? deviceDetails; // Made nullable as it might not be used now
  String? androidVersion;
  String? model;
  int? batteryLevel;

  int pendingPairs = 0;

  bool isOnline = true;

  @override
  void initState() {
    super.initState();

    checkIfLoggedIn();
    init();

    // setState(() => isSignedIn = myFirebaseAuth.isSignedIn());
  }

  void init() async {
    // SocketService().init();

    myDeviceName =
        await SharedPreferencesService().getDeviceName() ?? "Unknown Device";

    DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    if (Platform.isAndroid) {
      AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
      androidVersion = androidInfo.version.release;
      model = androidInfo.model;
    }

    Battery battery = Battery();
    try {
      batteryLevel = await battery.batteryLevel;
    } catch (e) {
      debugPrint("Failed to get battery level: $e");
    }

    pendingPairs = await BackendService()
        .get('/api/device/pending-pairings?myDeviceName=$myDeviceName')
        .then((response) {
      if (response['success']) {
        final data = response['data'];
        if (data != null && data['requests'] != null) {
          return (data['requests'] as List).length;
        }
      } else {}
      return 0;
    });

    setState(() {});
  }

  void checkIfLoggedIn() async {
    // isSignedIn = await myFirebaseAuth.isSignedIn();
    isSignedIn = await AuthService().isLoggedIn();
    myDeviceName =
        await SharedPreferencesService().getDeviceName() ?? "Unknown Device";

    if (!isSignedIn && mounted) {
      // Navigate to login if not signed in
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(
          builder: (context) => LoginPage(),
        ),
      );
    } else if (myDeviceName == "Unknown Device") {
      // If signed in but no device registered, navigate to device registration
      Navigator.of(context).pushReplacement(
        CupertinoPageRoute(
          builder: (context) => RegisterDevicePage(),
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

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(
        left: kPagePadding + 4,
        right: kPagePadding,
        top: kPagePadding * 1.25,
        bottom: 8,
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: kIndigoColor,
        ),
      ),
    );
  }

  Widget _pendingPairsBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
      child: InkWell(
        borderRadius: BorderRadius.circular(kBorderRadius),
        onTap: () {
          Navigator.of(context).push(
            CupertinoPageRoute(
              builder: (context) => PairedDevices(),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kPagePadding,
            vertical: kPagePadding / 1.3,
          ),
          decoration: BoxDecoration(
            color: kWarningColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(kBorderRadius),
            border: Border.all(color: kWarningColor.withValues(alpha: 0.4)),
          ),
          child: Row(
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: kWarningColor,
                size: 20,
              ),
              const SizedBox(width: kPagePadding / 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Pending Pairing Requests",
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "$pendingPairs device${pendingPairs == 1 ? '' : 's'} waiting for approval",
                      style: TextStyle(
                          fontSize: 12, color: Theme.of(context).hintColor),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(CupertinoIcons.chevron_right,
                  size: 18, color: kIndigoColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _signOutButton(BuildContext context) {
    return InkWell(
      onTap: () async {
        bool confirmed = await showConfirmDeleteDialog(
              context,
              title: "",
              message: "Sign out of this device?",
            ) ??
            false;

        if (!confirmed) return;
        showLoadingDialog(
          context,
          text: "Signing out...",
        );

        await AuthService().logout();

        Navigator.of(context).popUntil((route) => route.isFirst);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: kPagePadding),
        padding: kPagePaddingInsets,
        decoration: BoxDecoration(
          color: kErrorColorLight,
          borderRadius: BorderRadius.circular(kBorderRadius),
          border: Border.all(color: kErrorColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(CupertinoIcons.power, color: kErrorColor),
            const SizedBox(width: kPagePadding / 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Sign out',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: kErrorColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'End session on this device',
                    style: TextStyle(
                        fontSize: 12, color: Theme.of(context).hintColor),
                  ),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right,
                size: 20, color: kErrorColor),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'Online Management'),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: ProfileCard(
                name: name,
                webLink: webLink,
                numberOfDevices: numberOfDevices,
                email: email,
              ),
            ),
            _sectionLabel('This Device'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: deviceCard(
                context: context,
                deviceName: myDeviceName,
                deviceDetails: deviceDetails,
                androidVersion: androidVersion,
                model: model,
                batteryLevel: batteryLevel,
                iconData: CupertinoIcons.phone_solid,
              ),
            ),
            if (pendingPairs > 0) ...[
              const SizedBox(height: kPagePadding / 1.5),
              _pendingPairsBanner(context),
            ],
            _sectionLabel('Manage'),
            buttonDescriptive(
              context,
              title: 'Buy for another number + Sell data online ($webLink)',
              subtitle: 'My Link (Online Presence)',
              icon: Icon(CupertinoIcons.link, color: kIndigoColor),
              onTap: () {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => MyOnlinePresencePage(),
                  ),
                );
              },
            ),
            buttonDescriptive(
              context,
              title: 'share messages between trusted devices online',
              subtitle: 'Paired Devices',
              icon: Icon(CupertinoIcons.arrow_right_arrow_left,
                  color: kPrimaryColor),
              onTap: () async {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => PairedDevices(),
                  ),
                );
              },
            ),
            buttonDescriptive(
              context,
              title: 'view/manage your phones (https://portal.bsat.co.ke)',
              subtitle: 'Remote Device Control',
              icon: Icon(CupertinoIcons.device_laptop, color: kErrorColor),
              onTap: () async {
                Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (context) => MyWebsitePage(),
                  ),
                );
              },
            ),
            _sectionLabel('Session'),
            _signOutButton(context),
            const SizedBox(height: kPagePadding * 3),
          ],
        ),
      ),
    );
  }
}
