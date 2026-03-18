import 'package:bsat/components/buildTextField.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/header.dart';
import '../../utils/constants.dart';

class ShareDataPage extends StatefulWidget {
  const ShareDataPage({super.key});

  @override
  State<ShareDataPage> createState() => _ShareDataPageState();
}

class _ShareDataPageState extends State<ShareDataPage> {
  String sendToPhone = '';
  
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

  void _sendRequest() {
    if (sendToPhone.isEmpty || sendToPhone.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter a valid phone number or email.")),
      );
      return;
    }

    // Call API here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text("Data request sent to \$sendToPhone!")),
    );
    
    setState(() {
      sendToPhone = '';
    });
  }

  void _handleRequest(int id, bool accept) {
    setState(() {
      incomingRequests.removeWhere((req) => req["id"] == id);
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(accept ? "Request accepted. Data will sync." : "Request denied.")),
    );
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
                    "Request clients and data from another BSAT user's phone. Enter their phone number or email.",
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 16),
                  
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      border: Border.all(color: Colors.grey.withOpacity(0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        buildTextField(
                          "Phone or Email", 
                          (val) => setState(() => sendToPhone = val),
                          keyboardType: TextInputType.emailAddress,
                          dontValidate: true,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _sendRequest,
                          icon: const Icon(CupertinoIcons.paperplane_fill),
                          label: const Text("Send Request"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimaryColor,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.all(16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(kBorderRadius)
                            )
                          ),
                        )
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Section 2: Incoming Requests
                  const Text(
                    "Incoming Requests",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Other phones asking to sync data with your device.",
                    style: TextStyle(color: Theme.of(context).hintColor),
                  ),
                  const SizedBox(height: 16),

                  if (incomingRequests.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      alignment: Alignment.center,
                      child: Text(
                        "No pending requests.",
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),

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
                                Text(
                                  request["senderName"],
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  request["date"],
                                  style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              request["senderPhone"],
                              style: TextStyle(color: kPrimaryColor, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => _handleRequest(request["id"], false),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: kErrorColor,
                                      side: const BorderSide(color: kErrorColor),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(kBorderRadius),
                                      )
                                    ),
                                    child: const Text("Deny"),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () => _handleRequest(request["id"], true),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: kPrimaryColor,
                                      foregroundColor: Colors.white,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(kBorderRadius),
                                      )
                                    ),
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
