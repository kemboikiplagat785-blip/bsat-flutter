import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';

class SocketService {
  IO.Socket? socket;
  final String serverUrl = 'https://bsat.co.ke';

  // Callbacks for different message types
  Function(Map<String, dynamic>)? onMessage;
  Function(Map<String, dynamic>)? onError;
  Function()? onConnect;
  Function()? onDisconnect;

  void connect({required String token, required String deviceDbId}) {
    socket = IO.io(
        serverUrl,
        IO.OptionBuilder()
            .setTransports(['websocket']) // for Flutter or Dart VM
            .disableAutoConnect() // disable auto-connection
            .setAuth({
              'token': token,
              'deviceId': deviceDbId,
            })
            .setExtraHeaders({
              'Authorization': 'Bearer $token', // Optional: additional header
            })
            .build());

    socket?.connect();

    socket?.onConnect((_) {
      print('Socket connected - Device ID: $deviceDbId');
      if (onConnect != null) onConnect!();
    });

    socket?.onDisconnect((_) {
      print('Socket disconnected');
      if (onDisconnect != null) onDisconnect!();
    });

    socket?.onConnectError((error) {
      // print('Socket connection error: $error');
      if (onError != null) {
        onError!({'type': 'connection_error', 'message': error.toString()});
      }
    });

    socket?.onReconnect((_) {
      print('Socket reconnected');
    });

    _setupMessageListeners();
  }

  void _setupMessageListeners() {
    // Listen for incoming messages from other devices
    socket?.on('message', (data) {
      print('Message received: $data');
      if (onMessage != null) {
        final messageData =
            data is Map ? data.cast<String, dynamic>() : jsonDecode(data);
        onMessage!(messageData);
      }
    });

    // Listen for errors (e.g., unpaired devices)
    socket?.on('error', (data) {
      print('Socket error: $data');
      if (onError != null) {
        final errorData = data is Map
            ? data.cast<String, dynamic>()
            : {'message': data.toString()};
        onError!(errorData);
      }
    });
  }

  // Send message to another device
  void sendMessageToDevice(
      {required int toDeviceId, required dynamic payload}) {
    if (socket?.connected ?? false) {
      socket?.emit('message', {
        'to': toDeviceId,
        'payload': payload,
      });
      print('Message sent to device $toDeviceId');
    } else {
      print('Socket not connected. Message not sent.');
    }
  }

  // Generic send method
  void sendMessage(String event, Map<String, dynamic> data) {
    if (socket?.connected ?? false) {
      socket?.emit(event, data);
    } else {
      print('Socket not connected. Message not sent.');
    }
  }

  bool isConnected() {
    return socket?.connected ?? false;
  }

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
  }
}
