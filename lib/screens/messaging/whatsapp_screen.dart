import 'dart:typed_data';

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

  void startWhatsapp() async {
    await whatsappService.initWhatsapp(
      onQrCode: (String qrString, Uint8List? imageBytes) {
        qrImageNotifier.value = imageBytes;
        return imageBytes;
      },
      onConnectionEvent: (ConnectionEvent event) {
        if (event == ConnectionEvent.connected) {
          qrImageNotifier.value = null; // Hide QR once connected
        }
        print("Status: ${event.name}");
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Link WhatsApp Bot")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<Uint8List?>(
              valueListenable: qrImageNotifier,
              builder: (context, value, child) {
                if (value == null) {
                  return Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 10),
                      Text("Waiting for QR or Connected..."),
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
                          child: Image.memory(value, width: 250, height: 250),
                        ),
                        // Your custom Logo overlay
                        Container(
                          padding: EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors
                                .white, // White background to make the logo pop
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons
                                .circle, // Or use an Image.asset('assets/whatsapp_logo.png')
                            color: Color(0xFF25D366),
                            size: 50,
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
              child: Text("Generate Connection"),
            ),
          ],
        ),
      ),
    );
  }
}
