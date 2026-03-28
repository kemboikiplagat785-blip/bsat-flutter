import 'dart:convert';
import 'dart:io';

import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../../components/device_card.dart';
import '../../components/header.dart';
import '../../services/backend_service.dart';
import '../../services/shared_preferences_service.dart';
import '../../services/sqlite_service.dart';
import '../../utils/constants.dart';
import '../online_management/search_device.dart';

class ShareDataPage extends StatefulWidget {
  const ShareDataPage({super.key});

  @override
  State<ShareDataPage> createState() => _ShareDataPageState();
}

class _ShareDataPageState extends State<ShareDataPage> {
  String sendToPhone = '';
  List<Map<String, dynamic>> pairedDevices = [];

  // Mock requests from other phones
  List<Map<String, dynamic>> incomingRequests = [
    {
      "id": 1,
      "senderName": "John Doe",
      "senderPhone": "0712345678",
      "status": "pending",
      "date": "Today, 10:30 AM"
    },
    {
      "id": 2,
      "senderName": "Jane's Samsung",
      "senderPhone": "0798765432",
      "status": "pending",
      "date": "Yesterday, 4:15 PM"
    }
  ];

  void _sendRequest(Map<String, dynamic> device) async {
    showLoadingDialog(context, text: "Sending request...");
    var response = await BackendService().post(
      '/api/device/request',
      body: {
        "device_id": device['id'],
      },
    );
    Navigator.of(context).pop();
    if (response['success']) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Data request sent to ${device['device_name']}!")),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Failed to send request: ${response['message']}")),
      );
    }
  }

  void _handleRequest(int id, bool accept) async {
    if (accept) {
      showLoadingDialog(context, text: "Preparing data...");

      try {
        var clients = await SQLiteService().queryAll('clients');
        String jsonContent = jsonEncode(clients);

        var prefs = SharedPreferencesService();
        String email = await prefs.getUserEmail() ?? 'noemail';
        String deviceName = await prefs.getDeviceName() ?? 'nodevice';
        String dateStr = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
        String filename = '${email}_${deviceName}_$dateStr.json';

        Directory tempDir = await getTemporaryDirectory();
        File file = File('${tempDir.path}/$filename');
        await file.writeAsString(jsonContent);

        // Send to server
        var response = await BackendService().post(
          '/api/device/share',
          body: {
            'filename': filename,
            'data': jsonContent,
            'request_id': id,
          },
        );

        if (mounted) Navigator.of(context).pop();

        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Request accepted. Data sent to server.")),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to send data: ${response['message']}")),
          );
        }
      } catch (e) {
        if (mounted) Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error processing request: $e")),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Request denied.")),
      );
    }

    setState(() {
      incomingRequests.removeWhere((req) => req["id"] == id);
    });
  }

  void loadPairedDevices() async {
    pairedDevices = await BackendService()
        .get('/api/device/whitelisted')
        .then((response) async {
      if (response['success']) {
        await SQLiteService().deleteWhere('whitelistedDevices', '1=1', []);
        final data = response['data'];
        if (data != null && data['devices'] != null) {
          List<Map<String, dynamic>> devices =
              List<Map<String, dynamic>>.from(data['devices']);
          await SQLiteService().clearTable('whitelistedDevices');
          for (var device in devices) {
            await SQLiteService().insertStuff(device, 'whitelistedDevices');
          }
          return devices;
        }
        return <Map<String, dynamic>>[];
      } else {
        pairedDevices = await SQLiteService().queryAll('whitelistedDevices');
        return <Map<String, dynamic>>[];
      }
    });

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    loadPairedDevices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            header(context, "Share Data"),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                children: [
                  const SizedBox(height: kPagePadding),

                  // Section 1: Send Request
                  const Text(
                    "Send Data Request",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Request clients and data from another BSAT user's phone. Enter their device name.",
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 16),

                  if (pairedDevices.isNotEmpty)
                    ...pairedDevices.map((device) => GestureDetector(
                        onTap: () {
                          _sendRequest(device);
                        },
                        child: deviceCard(
                          context: context,
                          deviceName: device['device_name'],
                          iconData: Icons.check_circle_outline_rounded,
                        ))),

                  Padding(
                    padding: kPagePaddingInsets,
                    child: GestureDetector(
                        onTap: () async {
                          // Navigate to search device page
                          Map<String, dynamic> device =
                              await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => SearchDevicePage(query: ''),
                            ),
                          );

                          if (device != null) {
                            _sendRequest(device);
                          }
                        },
                        child: Icon(
                          CupertinoIcons.plus_rectangle,
                          color: kPrimaryColor,
                          size: 80,
                        )),
                  ),

                  const SizedBox(height: 32),

                  const Text("Incoming Requests",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      )),
                  const SizedBox(height: 8),
                  Text("Other phones asking to sync data with your device.",
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                      )),
                  const SizedBox(height: 16),

                  if (incomingRequests.isEmpty)
                    Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        alignment: Alignment.center,
                        child: Text(
                          "No pending requests.",
                          style: TextStyle(color: Colors.grey[500]),
                        )),

                  ...incomingRequests.map((request) {
                    return Card(
                      elevation: 0,
                      color: Theme.of(context).cardColor,
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        side: BorderSide(color: Colors.grey.withOpacity(0.2)),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(request["senderName"],
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    )),
                                Text(request["date"],
                                    style: TextStyle(
                                      color: Theme.of(context).hintColor,
                                      fontSize: 12,
                                    )),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(request["senderPhone"],
                                style: TextStyle(
                                  color: kPrimaryColor,
                                  fontWeight: FontWeight.w600,
                                )),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () =>
                                        _handleRequest(request["id"], false),
                                    style: OutlinedButton.styleFrom(
                                        foregroundColor: kErrorColor,
                                        side: const BorderSide(
                                            color: kErrorColor),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              kBorderRadius),
                                        )),
                                    child: const Text("Deny"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () =>
                                        _handleRequest(request["id"], true),
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor: kPrimaryColor,
                                        foregroundColor: Colors.white,
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                              kBorderRadius),
                                        )),
                                    child: const Text("Accept"),
                                  ),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                    );
                  }).toList(),

                  const SizedBox(height: 48),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
