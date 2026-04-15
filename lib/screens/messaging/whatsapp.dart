import 'dart:typed_data';

import 'package:whatsapp_bot_flutter/whatsapp_bot_flutter.dart';
import 'package:whatsapp_bot_flutter_mobile/whatsapp_bot_flutter_mobile.dart';

final whatsappService = WhatsappService();

class WhatsappService {
  WhatsappClient? whatsappClient;

  bool get isConnected => whatsappClient?.isConnected ?? false;

  Future<bool> ensureConnected({
    dynamic Function(String qrString, Uint8List? imageBytes)? onQrCode,
    void Function(ConnectionEvent event)? onConnectionEvent,
  }) async {
    if (isConnected) return true;
    await initWhatsapp(
      onQrCode: onQrCode,
      onConnectionEvent: onConnectionEvent,
    );
    return isConnected;
  }

  Future<void> initWhatsapp({
    dynamic Function(String qrString, Uint8List? imageBytes)? onQrCode,
    void Function(ConnectionEvent event)? onConnectionEvent,
  }) async {
    // WhatsappBotUtils.enableLogs(true);

    // if (isConnected) {
    //   print("Already connected to WhatsApp.");
    //   return;
    // }

    whatsappClient = await WhatsappBotFlutterMobile.connect(
      onQrCode: (String qrString, Uint8List? imageBytes) {
        print("Scan this QR code in WhatsApp: $qrString");
        return onQrCode?.call(qrString, imageBytes) ?? imageBytes;
      },
      onConnectionEvent: (ConnectionEvent event) {
        print("Connection Status: ${event.name}");
        onConnectionEvent?.call(event);
      },
    );

    whatsappClient?.connectionEventStream.listen((event) {
      print("Connection Event: ${event.name}");
    });
  }

  Future<void> sendMessage(String number, String text) async {
    if (isConnected) {
      print("sending message to $number: $text");
      try {
        print(await whatsappClient!.profile.getMyStatus());
        // check if still connected before sending
        print(await whatsappClient!.isReadyToChat);
        await whatsappClient!.chat.sendTextMessage(
          phone: "$number@c.us", // Example: 254712345678@c.us
          message: text,
        );
        print("Message sent to $number");
      } catch (e) {
        print("Error sending message: $e");
      }
    } else {
      print("Client not connected. Please scan QR first.");
    }
  }
}
