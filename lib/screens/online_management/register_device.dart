import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/hero.dart';
import 'package:bsat/screens/online_management/online_management.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class RegisterDevicePage extends StatefulWidget {
  const RegisterDevicePage({super.key});

  @override
  State<RegisterDevicePage> createState() => _RegisterDevicePageState();
}

class _RegisterDevicePageState extends State<RegisterDevicePage> {
  final _formKey = GlobalKey<FormState>();
  String deviceName = '';
  String error = '';
  bool isLoading = false;
  List<Map<String, dynamic>> loggedOutDevices = [];

  @override
  void initState() {
    super.initState();
    _loadDeviceName();
    getLoggedOutDevices();
  }

  Future<void> _loadDeviceName() async {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    setState(() {
      deviceName = androidInfo.device; // Default to device model/name
    });
  }

  void getLoggedOutDevices() async {
    try {
      final response = await BackendService().get(
        '/api/devices/logged-out-devices',
      );
      if (response['success']) {
        // print('Logged out devices: ${response['data']['devices']}');
        setState(() {
          loggedOutDevices = List<Map<String, dynamic>>.from(
              response['data']['devices'] ?? []);
        });
      } else {
        print('Failed to fetch logged out devices: ${response}');
      }
    } catch (e) {
      print('Error fetching logged out devices: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: kPagePadding * 3),
            Container(
              // height: 150,
              child: const MyHeroWidget(),
            ),
            IconButton(
                onPressed: () => getLoggedOutDevices(),
                icon: Icon(Icons.refresh)),
            const SizedBox(height: kPagePadding * 2),
            Container(
              decoration: const BoxDecoration(
                // color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      const Text(
                        'Register Device',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: kPagePadding),
                      if (error != '')
                        Container(
                          padding: kPagePaddingInsets,
                          margin: const EdgeInsets.only(bottom: kPagePadding),
                          decoration: BoxDecoration(
                            color: kErrorColor.withAlpha(20),
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                          child: Text(
                            error,
                            style: TextStyle(color: kErrorColor),
                          ),
                        ),
                      const SizedBox(height: kPagePadding),
                      const Text(
                        'Pick a unique name for this device.',
                      ),
                      const SizedBox(height: kPagePadding / 2),
                      TextFormField(
                        initialValue: deviceName,
                        decoration: InputDecoration(
                          labelText: 'Device Name',
                          hintText: 'e.g. My Phone',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                        ),
                        onChanged: (value) => deviceName = value,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter a device name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: kPagePadding * 2),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            padding: kPagePaddingInsets,
                            elevation: 0,
                            backgroundColor: kPrimaryColorLight,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                          ),
                          onPressed: _handleDeviceRegistration,
                          child: Text(
                            'REGISTER DEVICE',
                            style: TextStyle(
                              color: kPrimaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: kPagePadding * 2),
                      // continue with a logged out device option
                      if (loggedOutDevices.isNotEmpty) ...[
                        const Text(
                          'Or continue with a previously logged out device:',
                          style: TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: kPagePadding),
                        Column(
                          children: loggedOutDevices.map((device) {
                            return GestureDetector(
                              onTap: () async {
                                await SharedPreferencesService()
                                    .setDeviceName(device['device_name']);
                                await SharedPreferencesService()
                                    .setDeviceId(device['device_id']);

                                String? fcmToken =
                                    await FirebaseMessaging.instance.getToken();

                                print(await BackendService().post(
                                  '/api/devices/update-fcm-token',
                                  body: {
                                    'deviceName': device['device_name'],
                                    'fcmToken': fcmToken,
                                  },
                                ));

                                Navigator.of(context).pushReplacement(
                                  CupertinoPageRoute(
                                    builder: (context) =>
                                        OnlineManagementScreen(),
                                  ),
                                );
                              },
                              child: ListTile(
                                title: Text(
                                    device['device_name'] ?? 'Unknown Device'),
                                subtitle: Text('ID: ${device['device_id']}'),
                                trailing: const Text('Continue'),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleDeviceRegistration() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        isLoading = true;
        error = '';
      });
      showLoadingDialog(context, text: "Registering $deviceName");

      try {
        final response = await AuthService().registerDeviceInfo(
          deviceName,
        );

        Navigator.of(context).pop(); // Close loading dialog
        if (!response['success']) {
          setState(() {
            error = response['error'] ??
                response['message'] ??
                'Failed to register device';
            isLoading = false;
          });
          return;
        }

        // Navigate to main screen
        Navigator.of(context).pushReplacement(
          CupertinoPageRoute(
            builder: (context) => OnlineManagementScreen(),
          ),
        );
      } catch (e) {
        Navigator.of(context).pop(); // Close loading dialog
        setState(() {
          error = 'Failed to register device: ${e.toString()}';
          isLoading = false;
        });
      }
    }
  }
}
