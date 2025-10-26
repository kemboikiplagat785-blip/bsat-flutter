import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/edit_forwarder.dart';
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
  List<Map<String, dynamic>> receivingDevices = [];
  List<Map<String, dynamic>> forwardingDevices = [];

  Future<void> getData() async {
    List<Map<String, dynamic>> recvDevices =
        await SQLiteService().queryAll('whitelistedDevices');

    List<Map<String, dynamic>> fwdDevices =
        await SQLiteService().queryAll('forwardingDevices');

    setState(() {
      receivingDevices = recvDevices;
      forwardingDevices = fwdDevices;
    });
  }

  @override
  void initState() {
    super.initState();
    getData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, "Online Forwarder"),
            const SizedBox(height: kPagePadding * 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                // spacing: kPagePadding / 2,
                children: [
                  Text(
                    "Receiving",
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text("Always process messages from the following devices:"),
                  const SizedBox(height: kPagePadding),
                  if (receivingDevices.isEmpty)
                    Padding(
                      padding:
                          const EdgeInsets.symmetric(vertical: kPagePadding),
                      child: Text(
                        "No receiving devices added yet.",
                        style: TextStyle(color: Colors.grey),
                      ),
                    )
                  else
                    ...receivingDevices.map((device) {
                      return InkWell(
                        onTap: () async {
                          bool confirmed =
                              await showConfirmDeleteDialog(context) ?? false;

                          if (confirmed) {
                            showLoadingDialog(
                              context,
                              text: "Removing Device...",
                            );
                            int deleteId = await SQLiteService().deleteWhere(
                              'whitelistedDevices',
                              'device_id = ?',
                              [device['device_id']],
                            );
                            Navigator.of(context).pop();
                            getData();
                            if (deleteId >= 0) {
                              showSuccessDialog(
                                context,
                                text: "Deleted device",
                              );
                            } else {
                              showErrorDialog(
                                context,
                                "Error",
                                "Failed to delete device.",
                              );
                            }
                          }
                        },
                        child: deviceCard(
                          context: context,
                          deviceName: device['device_name'],
                          deviceDetails: "${device['owner_email']}",
                          iconData: Icons.devices,
                        ),
                      );
                    }).toList(),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: InkWell(
                      onTap: () async {
                        Map deviceDetails = await Navigator.of(context).push(
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    SearchDevicePage(),
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
                        Map<String, dynamic> deviceToInsert = {
                          'device_name': deviceDetails['device_name'],
                          'device_id': deviceDetails['device_id'],
                          'owner_email': deviceDetails['owner_email'],
                          'user_id': deviceDetails['user_id'],
                        };

                        // Insert the device into the database
                        await SQLiteService().insertStuff(
                          deviceToInsert,
                          'whitelistedDevices',
                        );

                        await getData();

                        //print("Selected Device Details: $deviceDetails");
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
                                          horizontal: kPagePadding / 4, vertical: 0),
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
