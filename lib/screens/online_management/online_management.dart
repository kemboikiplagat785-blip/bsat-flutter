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
        print("Pending pairing requests: ${response['data']}");
        final data = response['data'];
        if (data != null && data['requests'] != null) {
          return (data['requests'] as List).length;
        }
      } else {
        print(
            "Failed to fetch pending pairing requests: ${response['message']}");
      }
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
            Padding(
              padding: kPagePaddingInsets,
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
            Padding(
              padding: kPagePaddingInsets,
              child: pendingPairs > 0
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: () {
                            Navigator.of(context).push(
                              CupertinoPageRoute(
                                builder: (context) => PairedDevices(),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              // color: Colors.white,
                              color: Theme.of(context).cardColor,
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                              border: Border(
                                bottom: BorderSide(
                                  // color: Theme.of(context).hintColor,
                                  color: kIndigoColor,
                                  width: 4,
                                ),
                                right: BorderSide(
                                  // color: Theme.of(context).hintColor,
                                  color: kIndigoColor,
                                  width: 4,
                                ),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "Pending Pairing Requests",
                                  style: TextStyle(
                                      // fontSize: 14,
                                      // color: Colors.grey,
                                      ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(
                                            CupertinoIcons
                                                .exclamationmark_triangle,
                                            color: Colors.orangeAccent),
                                        const SizedBox(width: 10),
                                        Text(
                                          "$pendingPairs",
                                          style: const TextStyle(
                                            // fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                    Icon(CupertinoIcons.chevron_right,
                                        color: kIndigoColor),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: kPagePadding),
                      ],
                    )
                  : SizedBox.shrink(),
            ),
            buttonDescriptive(
              context,
              title: 'Buy for another number + Sell data online (${webLink})',
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
                // Navigator.of(context).push(
                //   CupertinoPageRoute(
                //     builder: (context) => PortalPage(),
                //   ),
                // );
                // open url in browser
                var url = 'https://portal.bsat.co.ke';
                if (await canLaunch(url)) {
                  await launch(url);
                } else {
                  throw 'Could not launch $url';
                }
              },
            ),
            buttonDescriptive(
              context,
              title: 'End Session',
              subtitle: 'Sign out',
              icon: Icon(CupertinoIcons.power, color: kErrorColor),
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
            ),
            const SizedBox(height: kPagePadding * 5),
          ],
        ),
      ),
    );
  }
}
