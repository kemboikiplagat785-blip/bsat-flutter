import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:convert';

class SocketService {
  IO.Socket? socket;
  final String serverUrl = 'https://bsat.co.ke'; // Your server URL
  
  // Callbacks for different message types
  Function(Map<String, dynamic>)? onNewTransaction;
  Function(Map<String, dynamic>)? onOfferUpdate;
  Function(String)? onNotification;
  Function(Map<String, dynamic>)? onCustomMessage;

  void connect({required String userId}) {
    socket = IO.io(serverUrl, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'query': {'userId': userId}, // Send user ID on connection
    });

    socket?.connect();

    // Connection events
    socket?.onConnect((_) {
      //print('Socket connected');
      // Join user-specific room
      socket?.emit('join', {'userId': userId});
    });

    socket?.onDisconnect((_) {
      //print('Socket disconnected');
    });

    socket?.onConnectError((error) {
      //print('Socket connection error: $error');
    });

    // Listen for incoming messages
    _setupMessageListeners();
  }

  void _setupMessageListeners() {
    // Generic message handler
    socket?.on('message', (data) {
      //print('Received message: $data');
      _handleIncomingMessage(data);
    });

    // New transaction notification
    socket?.on('new_transaction', (data) {
      //print('New transaction: $data');
      if (onNewTransaction != null) {
        onNewTransaction!(data is Map ? data.cast<String, dynamic>() : jsonDecode(data));
      }
    });

    // Offer updates
    socket?.on('offer_update', (data) {
      //print('Offer update: $data');
      if (onOfferUpdate != null) {
        onOfferUpdate!(data is Map ? data.cast<String, dynamic>() : jsonDecode(data));
      }
    });

    // General notifications
    socket?.on('notification', (data) {
      //print('Notification: $data');
      if (onNotification != null) {
        onNotification!(data.toString());
      }
    });

    // Custom message type
    socket?.on('custom_message', (data) {
      //print('Custom message: $data');
      if (onCustomMessage != null) {
        onCustomMessage!(data is Map ? data.cast<String, dynamic>() : jsonDecode(data));
      }
    });

    // Broadcast messages to all clients
    socket?.on('broadcast', (data) {
      //print('Broadcast message: $data');
      _handleBroadcast(data);
    });
  }

  void _handleIncomingMessage(dynamic data) {
    try {
      Map<String, dynamic> message = data is Map 
          ? data.cast<String, dynamic>() 
          : jsonDecode(data);

      // Route message based on type
      switch (message['type']) {
        case 'transaction':
          onNewTransaction?.call(message['data']);
          break;
        case 'offer':
          onOfferUpdate?.call(message['data']);
          break;
        case 'notification':
          onNotification?.call(message['message']);
          break;
        default:
          //print('Unknown message type: ${message['type']}');
      }
    } catch (e) {
      //print('Error handling message: $e');
    }
  }

  void _handleBroadcast(dynamic data) {
    // Handle broadcast messages (announcements, updates, etc.)
    //print('Processing broadcast: $data');
  }

  // Send message to server
  void sendMessage(String event, Map<String, dynamic> data) {
    if (socket?.connected ?? false) {
      socket?.emit(event, data);
    } else {
      //print('Socket not connected. Message not sent.');
    }
  }

  void disconnect() {
    socket?.disconnect();
    socket?.dispose();
  }
}