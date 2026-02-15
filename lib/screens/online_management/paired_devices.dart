import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/edit_forwarder.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/device_card.dart';
import '../../services/sqlite_service.dart';
import 'search_device.dart';

class ForwardReceiveOnlinePage extends StatefulWidget {
  const ForwardReceiveOnlinePage({super.key});

  @override
  State<ForwardReceiveOnlinePage> createState() =>
      _ForwardReceiveOnlinePageState();
}

class _ForwardReceiveOnlinePageState extends State<ForwardReceiveOnlinePage> {
  List<Map<String, dynamic>> pairedDevices = [];
  List<Map<String, dynamic>> forwardingDevices = [];

  int pendingPairs = 0;

  BackendService backendService = BackendService();

  Future<void> _unlinkDevice(String targetDeviceId) async {
    bool confirmed = await showConfirmDeleteDialog(context,
            message: "Are you sure you want to unlink this device?") ??
        false;
    if (!confirmed) return;

    if (!mounted) return;
    showLoadingDialog(context, text: "Unlinking Device...");

    String? myDeviceId = await AuthService().getDeviceId();
    final response = await backendService.post('/api/device/unlink', body: {
      'myDeviceId': myDeviceId,
      'otherDeviceId': targetDeviceId,
    });

    if (mounted) Navigator.of(context).pop();

    if (response['success']) {
      await getData();
      if (mounted) showSuccessDialog(context, text: "Device unlinked");
    } else {
      if (mounted) {
        showErrorDialog(context, "Error",
            response['message'] ?? "Failed to unlink device.");
      }
    }
  }

  Future<void> getData() async {
    // get data from endpoint /whitelisted
    // then update whitelistedDevices with the new data
    showLoadingDialog(  context, text: "Fetching paired devices...");
    pairedDevices = await backendService
        .get('/api/device/whitelisted')
        .then((response) async {
      if (response['success']) {
        print("Whitelisted devices from server: ${response['data']}");
        final data = response['data'];
        if (data != null && data['devices'] != null) {
          List<Map<String, dynamic>> devices =
              List<Map<String, dynamic>>.from(data['devices']);
          await SQLiteService().clearTable('whitelistedDevices');
          print("Cleared local whitelistedDevices table, ${SQLiteService().getCount('whitelistedDevices')} records now.");
          for (var device in devices) {
            await SQLiteService().insertStuff(device, 'whitelistedDevices');
          }
          return devices;
        }
        return <Map<String, dynamic>>[];
      } else {
        print("Failed to fetch whitelisted devices: ${response['message']}");
        return <Map<String, dynamic>>[];
      }
    });

    pendingPairs = await backendService
        .get('/api/device/pending-pairings?myDeviceId=${await AuthService().getDeviceId()}')
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

    if (pairedDevices.isEmpty) {
      // If we couldn't fetch from server, fallback to local database
      pairedDevices = await SQLiteService().queryAll('whitelistedDevices');
    }

    forwardingDevices = await SQLiteService().queryAll('forwardingDevices');

    Navigator.of(context).pop(); // Hide loading

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getData();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, "Paired Devices"),
            const SizedBox(height: kPagePadding * 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                // spacing: kPagePadding / 2,
                children: [
                  Text("Send and receive MPESA messages online between paired devices"),
                  const SizedBox(height: kPagePadding),
                  Divider(),
                  const SizedBox(height: kPagePadding * 2),
                  Text("Paired Devices", style: TextStyle(fontWeight: FontWeight.bold),),

                  Text("Process messages from the following devices"),
                  const SizedBox(height: kPagePadding),
                  pendingPairs > 0
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            GestureDetector(
                              onTap: () {
                                Navigator.of(context).push(
                                  PageRouteBuilder(
                                    pageBuilder: (context, animation,
                                            secondaryAnimation) =>
                                        PairDevicePage(),
                                    transitionsBuilder: (context, animation,
                                        secondaryAnimation, child) {
                                      return CupertinoPageTransition(
                                        primaryRouteAnimation: animation,
                                        secondaryRouteAnimation:
                                            secondaryAnimation,
                                        linearTransition: true,
                                        child: child,
                                      );
                                    },
                                  ),
                                ).then((_) => getData());
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
                                              "$pendingPairs pending pairing request${pendingPairs != 1 ? 's' : ''}",
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

                  if (pairedDevices.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: kPagePadding),
                      child: Text(
                        "No receiving devices added yet.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...pairedDevices.map((device) {
                      return InkWell(
                        onTap: () async {
                          await _unlinkDevice(device['device_id']);
                        },
                        child: deviceCard(
                          context: context,
                          deviceName: device['device_name'],
                          deviceDetails: "${device['owner_email']}",
                          iconData: Icons.devices,
                          trailing: IconButton(
                            onPressed: () async {
                              await _unlinkDevice(device['device_id']);
                            },
                            icon: Icon(
                              CupertinoIcons.xmark_circle,
                              color: Colors.redAccent,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: InkWell(
                      onTap: () async {
                        await Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    PairDevicePage(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        );
                        await getData();
                      },
                      child: Container(
                        padding: kPagePaddingInsets,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          color: Theme.of(context).cardColor,
                        ),
                        child: Icon(Icons.add),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: kPagePadding),
            Divider(),
            const SizedBox(height: kPagePadding * 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Forwarding",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  // const SizedBox(height: kPagePadding / 2),
                  Text("Messages will be forwarded to the following devices:"),
                  const SizedBox(height: kPagePadding),
                  if (forwardingDevices.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: kPagePadding),
                      child: Center(
                        child: Text(
                          "No forwarding devices added yet.",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ...forwardingDevices.map((device) {
                      List amounts = device["amounts_to_forward"] != null
                          ? (jsonDecode(device["amounts_to_forward"]) as List)
                              .map((e) => e.toString())
                              .toList()
                          : [];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: kPagePadding),
                        child: InkWell(
                          onTap: () async {
                            await Navigator.of(context).push(
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        EditForwarder(
                                  dbId: device['id'],
                                ),
                                transitionsBuilder: (context, animation,
                                    secondaryAnimation, child) {
                                  return CupertinoPageTransition(
                                    primaryRouteAnimation: animation,
                                    secondaryRouteAnimation: secondaryAnimation,
                                    linearTransition: true,
                                    child: child,
                                  );
                                },
                              ),
                            );
                            await getData();
                          },
                          child: deviceCard(
                            context: context,
                            deviceName: device['device_name'],
                            deviceDetails: device['owner_email'],
                            iconData: Icons.devices,
                            trailing: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("Amounts"),
                                Wrap(children: [
                                  ...amounts.map(
                                    (amt) => Chip(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: kPagePadding / 4,
                                          vertical: 0),
                                      labelPadding: EdgeInsets.symmetric(
                                          horizontal: 0, vertical: 0),
                                      label: Text(amt),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ),
                                ])
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: InkWell(
                      onTap: () async {
                        await Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    EditForwarder(),
                            transitionsBuilder: (context, animation,
                                secondaryAnimation, child) {
                              return CupertinoPageTransition(
                                primaryRouteAnimation: animation,
                                secondaryRouteAnimation: secondaryAnimation,
                                linearTransition: true,
                                child: child,
                              );
                            },
                          ),
                        );
                        await getData();
                      },
                      child: Container(
                        padding: kPagePaddingInsets,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          color: Theme.of(context).cardColor,
                        ),
                        child: Icon(Icons.add),
                      ),
                    ),
                  ),
                  const SizedBox(height: kPagePadding * 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
