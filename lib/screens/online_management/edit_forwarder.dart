import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/confirmation_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/chip_input_field.dart';
import '../../components/device_card.dart';
import '../../components/dialogs/loading_dialog.dart';
import '../../components/dialogs/show_error_dialog.dart';
import '../../services/shared_preferences_service.dart';
import '../../services/sqlite_service.dart';
import 'search_device.dart';

class EditForwarder extends StatefulWidget {
  final int? dbId;
  const EditForwarder({super.key, this.dbId});

  @override
  State<EditForwarder> createState() => _EditForwarderState();
}

class _EditForwarderState extends State<EditForwarder> {
  Map deviceToReceive = {};
  List<int> amountsToForward = [];
  String myDeviceName = '';

  final TextEditingController _amountsToForwardTextController =
      TextEditingController();

  void fetchData() async {
    myDeviceName =
        await SharedPreferencesService().getDeviceName() ?? "Unknown Device";
    if (widget.dbId != null) {
      List<Map<String, dynamic>> results = await SQLiteService().rawQueryInput(
        'SELECT * FROM forwardingDevices WHERE id = ?',
        [widget.dbId],
      );

      if (results.isNotEmpty) {
        setState(() {
          deviceToReceive = results.first;
          amountsToForward = List<int>.from(
              jsonDecode(deviceToReceive['amounts_to_forward'] ?? '[]'));
        });
      }
    }
  }

  Future<void> postData() async {
    showLoadingDialog(context, text: "Saving...");

    final backendService = BackendService();

    try {
      final backendService = BackendService();

      // Using a likely endpoint. Update if the server expects a different one.
      final response =
          await backendService.post('/api/devices/request-pairing', body: {
        'myDeviceName': myDeviceName,
        'targetDeviceName': deviceToReceive['device_name'],
      });

      if (!response['success']) {
        if (mounted) {
          Navigator.pop(context);
          String errorMessage =
              response['message'] ?? "Failed to save settings.";

          if (response['error'] != null && response['error'] is Map) {
            errorMessage = response['error']['error'] ??
                response['error']['message'] ??
                errorMessage;
          }

          showErrorDialog(context, "Error", errorMessage);
        }
        // return;
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Hide loading
        showErrorDialog(context, "Error", "An error occurred: $e");
      }
      return;
    }

    if (widget.dbId != null) {
      Map<String, dynamic> updatedData = {
        'device_id': deviceToReceive['device_id'],
        'device_name': deviceToReceive['device_name'],
        'owner_email': deviceToReceive['owner_email'],
        'user_id': deviceToReceive['user_id'],
        'amounts_to_forward': jsonEncode(amountsToForward),
      };

      int updatedId = await SQLiteService().updateStuff(
        updatedData,
        'id = ?',
        [widget.dbId],
        'forwardingDevices',
      );
    } else {
      Map<String, dynamic> newData = {
        'device_id': deviceToReceive['device_id'],
        'device_name': deviceToReceive['device_name'],
        'owner_email': deviceToReceive['owner_email'],
        'user_id': deviceToReceive['user_id'],
        'amounts_to_forward': jsonEncode(amountsToForward),
      };

      int newId = await SQLiteService().insertStuff(
        newData,
        'forwardingDevices',
      );

      //print("New Forwarded Device ID: $newId");
    }
    Navigator.of(context).pop(); // Close loading dialog
  }

  void _processAmountsToForward() {
    setState(() {
      amountsToForward
          .add(int.parse(_amountsToForwardTextController.text.trim()));
      _amountsToForwardTextController.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    fetchData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          spacing: kPagePadding,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, "Forward MPESA Messages"),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                spacing: kPagePadding / 2,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    "Forward To",
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (deviceToReceive.isEmpty)
                    Center(
                      child: InkWell(
                        onTap: () async {
                          deviceToReceive = await Navigator.of(context).push(
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

                          setState(() {});
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
                    )
                  else
                    InkWell(
                      onTap: () async {
                        deviceToReceive = await Navigator.of(context).push(
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

                        setState(() {});
                      },
                      child: deviceCard(
                        context: context,
                        deviceName: deviceToReceive['device_name'],
                        deviceDetails: deviceToReceive['owner_email'],
                        iconData: Icons.devices,
                      ),
                    ),
                  const SizedBox(height: kPagePadding),
                  Text("Amounts to forward (Ksh)"),
                  // SizedBox(height: kPagePadding / 3),
                  ChipInputField(
                    chips: amountsToForward.map((e) => e).toList(),
                    controller: _amountsToForwardTextController,
                    onAddChip: () {
                      setState(() {
                        _processAmountsToForward();
                      });
                    },
                    onRemoveChip: (chip) {
                      setState(() {
                        amountsToForward.remove(int.parse(chip));
                        //print(amountsToForward);
                      });
                    },
                    keyboardType: TextInputType.number,
                    spacing: kPagePadding / 3,
                    borderRadius: kBorderRadius,
                    addIconColor: kPrimaryColor,
                  ),
                  const SizedBox(height: kPagePadding * 3),
                  // row with 3 buttons: cancel, delete
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.dbId != null)
                        IconButton(
                          onPressed: () async {
                            bool delete = await showConfirmDeleteDialog(
                                  context,
                                  title: "Delete",
                                  message: "Are you sure you want to delete?",
                                ) ??
                                false;

                            if (!delete) return;
                            int deletedId = await SQLiteService().deleteWhere(
                              'forwardingDevices',
                              'id = ?',
                              [widget.dbId],
                            );
                            //print("Deleted Forwarded Device ID: $deletedId");
                            Navigator.of(context).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            // shape:
                            backgroundColor: kErrorColor.withValues(alpha: .1),
                          ),
                          icon: Icon(
                            CupertinoIcons.trash,
                            color: kErrorColor,
                          ),
                        ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Text("Cancel"),
                      ),
                      const SizedBox(width: kPagePadding),
                      OutlinedButton(
                        onPressed: () async {
                          bool save =
                              await confirmationDialog(context, "Add device?");
                          if (!save) return;
                          showLoadingDialog(context);
                          await postData();
                          Navigator.of(context).pop();
                          Navigator.of(context).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          // backgroundColor: kPrimaryColor,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
                        ),
                        child: const Text("Save",
                            style: TextStyle(color: kPrimaryColor)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
