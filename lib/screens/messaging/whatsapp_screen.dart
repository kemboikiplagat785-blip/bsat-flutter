import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:whatsapp_bot_flutter/whatsapp_bot_flutter.dart';

import 'whatsapp.dart';

class WhatsappScreen extends StatefulWidget {
  const WhatsappScreen({super.key});

  @override
  State<WhatsappScreen> createState() => _WhatsappScreenState();
}

class _WhatsappScreenState extends State<WhatsappScreen> {
  // Use a ValueNotifier to track the QR image
  ValueNotifier<Uint8List?> qrImageNotifier = ValueNotifier<Uint8List?>(null);

  bool whatsappConnected = false;
  bool connectionInProgress = false;

  void startWhatsapp() async {
    // if (whatsappService.isConnected) {
    //   setState(() {
    //     whatsappConnected = true;
    //     connectionInProgress = false;
    //     qrImageNotifier.value = null;
    //   });
    //   return;
    // }

    setState(() {
      connectionInProgress = true;
      whatsappConnected = false;
    });
    try {
      print("Initializing WhatsApp connection...");
      await whatsappService.initWhatsapp(
        onQrCode: (String qrString, Uint8List? imageBytes) {
          qrImageNotifier.value = imageBytes;
          return imageBytes;
        },
        onConnectionEvent: (ConnectionEvent event) {
          if (event == ConnectionEvent.connected) {
            qrImageNotifier.value = null; // Hide QR once connected
            if (mounted) {
              setState(() {
                whatsappConnected = true;
              });
            }
          } else {
            if (mounted) {
              setState(() {
                whatsappConnected = false;
              });
            }
          }
          print("Status: ${event.name}");
        },
      );
    } catch (e) {
      print("Error initializing WhatsApp: $e");
    }

    setState(() {
      connectionInProgress = false;
    });
  }

  @override
  void initState() {
    super.initState();
    whatsappConnected = whatsappService.isConnected;
    startWhatsapp();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Link WhatsApp Bot")),
      body: Column(
        // crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // procedure to scan code and connect to whatsapp
          const Spacer(),
          if (!whatsappConnected)
            Text(
              "To link your WhatsApp account, \n\n\t1. Open WhatsApp on your phone\n\t2. Go to Settings > Linked Devices > Link a Device\n\t3. Scan the QR code below",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
          const Spacer(),
          SizedBox(height: 20),
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ValueListenableBuilder<Uint8List?>(
                  valueListenable: qrImageNotifier,
                  builder: (context, value, child) {
                    if (value == null) {
                      return Column(
                        children: [
                          if (!whatsappConnected && connectionInProgress)
                            CircularProgressIndicator(),
                          SizedBox(height: 10),
                          Text(
                            whatsappConnected
                                ? "WhatsApp connected"
                                : connectionInProgress
                                ? "Waiting for QR..."
                                : "Not connected",
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        Text("Scan with WhatsApp",
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        SizedBox(height: 20),
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // The raw QR code from the plugin
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              padding: EdgeInsets.all(16),
                              child:
                              Image.memory(value, width: 250, height: 250),
                            ),
                            // Your custom Logo overlay
                            Container(
                              padding: EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(40),
                              ),
                              child: Image.asset(
                                "assets/icons/whatsapp.png",
                                width: 40,
                                height: 40,
                              ),
                            ),
                          ],
                        )
                      ],
                    );
                  },
                ),
                ElevatedButton(
                  onPressed: startWhatsapp,
                  child: Text(
                    whatsappConnected
                        ? "Connected"
                        : (connectionInProgress
                        ? "Reconnecting..."
                        : "Reconnect WhatsApp"),
                  ),
                ),
                if (whatsappConnected)
                  ElevatedButton(
                    onPressed: () {
                      if (whatsappConnected) {
                        whatsappService.whatsappClient?.disconnect();
                        setState(() {
                          whatsappConnected = false;
                          qrImageNotifier.value = null;
                        });
                      }
                    },
                    child: Text("Disconnect"),
                  ),
                ElevatedButton(
                    onPressed: () {
                      // if (whatsappConnected) {
                      whatsappService.sendMessage(
                        "254702015937", // Replace with a valid number
                        "bsat app test message at ${DateTime.now()}",
                      );
                      // }
                    },
                    child: Text("Send sample message"))
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
