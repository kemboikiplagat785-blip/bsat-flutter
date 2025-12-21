import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';

class SocketService {
  IO.Socket? socket;
  final String serverUrl = 'https://api.bsat.co.ke';

  // Callbacks for different message types
  Function(Map<String, dynamic>)? onMessage;
  Function(Map<String, dynamic>)? onError;
  Function()? onConnect;
  Function()? onDisconnect;

  void connect({required String token, required String deviceDbId}) {
    try {
      print('🔌 Connecting to: $serverUrl');
      print('🔑 Token: ${token.substring(0, 20)}...');
      print('📱 Device ID: $deviceDbId');

      // 1. Build the options map first
      final Map<String, dynamic> options = IO.OptionBuilder()
          .setPath('/socket.io/')
          .setTransports(['polling', 'websocket']) // Polling and WebSocket
          .enableAutoConnect()
          .setTimeout(20000)
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(5000)
          .setReconnectionAttempts(5)
          .enableReconnection()
          .setAuth({
            'token': token,
            'deviceId': deviceDbId,
          })
          .setExtraHeaders({
            'Authorization': 'Bearer $token',
          })
          .build();

      // 2. Explicitly disable upgrade to prevent WebSocket attempts
      options['upgrade'] = false;

      // 3. Initialize socket with modified options
      socket = IO.io(serverUrl, options);

      socket?.onConnect((_) {
        print('✅ Socket CONNECTED!');
        print('   Socket ID: ${socket?.id}');
        print('   Transport: polling');
        if (onConnect != null) onConnect!();
      });

      socket?.onDisconnect((reason) {
        print('❌ Socket disconnected: $reason');
        if (onDisconnect != null) onDisconnect!();
      });

      socket?.onConnectError((error) {
        print('⚠️ Connection error: $error');
        if (onError != null) {
          onError!({'type': 'connection_error', 'message': error.toString()});
        }
      });

      socket?.onError((error) {
        // Silently ignore websocket/upgrade errors
        if (error.toString().toLowerCase().contains('websocket') ||
            error.toString().toLowerCase().contains('upgrade')) {
          return;
        }

        print('⚠️ Socket error: $error');
        if (onError != null) {
          onError!({'type': 'error', 'message': error.toString()});
        }
      });

      socket?.onReconnect((attempt) {
        print('🔄 Reconnected (attempt $attempt)');
      });

      socket?.onReconnectAttempt((attempt) {
        print('🔄 Reconnect attempt $attempt...');
      });

      socket?.onReconnectError((error) {
        print('⚠️ Reconnect error: $error');
      });

      socket?.onReconnectFailed((_) {
        print('❌ Reconnect failed after all attempts');
        if (onError != null) {
          onError!({'type': 'reconnect_failed', 'message': 'Failed to reconnect'});
        }
      });

      _setupMessageListeners();
    } catch (e) {
      print('❌ Error initializing socket: $e');
      if (onError != null) {
        onError!({'type': 'init_error', 'message': e.toString()});
      }
    }
  }

  void _setupMessageListeners() {
    // Listen for incoming messages from other devices
    socket?.on('message', (data) {
      print('📥 Message received: $data');
      if (onMessage != null) {
        final messageData = data is Map
            ? data.cast<String, dynamic>()
            : jsonDecode(data.toString());
        onMessage!(messageData);
      }
    });

    // Listen for errors (e.g., unpaired devices)
    socket?.on('error', (data) {
      print('⚠️ Error event: $data');
    });

    // Add a ping event to test connection
    socket?.on('pong', (_) {
      print('🏓 Pong received - connection alive');
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
      print('📤 Message sent to device $toDeviceId');
    } else {
      print('❌ Socket not connected. Cannot send message.');
    }
  }

  // Generic send method
  void sendMessage(String event, Map<String, dynamic> data) {
    if (socket?.connected ?? false) {
      socket?.emit(event, data);
      print('📤 Event sent: $event');
    } else {
      print('❌ Socket not connected. Cannot send event.');
    }
  }

  bool isConnected() {
    final connected = socket?.connected ?? false;
    print('🔍 Socket connection check: $connected');
    return connected;
  }

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
    socket = null;
    print('🔌 Socket disconnected and disposed');
  }
}
