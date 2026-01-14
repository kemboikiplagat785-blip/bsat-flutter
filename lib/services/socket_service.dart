import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'dart:async';

class SocketService {
  IO.Socket? _socket;
  final _messageController = StreamController<dynamic>.broadcast();
  final _connectionStateController = StreamController<bool>.broadcast();
  
  static const String _defaultServerUrl = "http://api.bsat.co.ke/socket.io/";
  bool _isConnected = false;
  
  Stream<dynamic> get messageStream => _messageController.stream;
  Stream<bool> get connectionState => _connectionStateController.stream;
  bool get isConnected => _isConnected;

  // Connect to Socket.IO server
  Future<void> connect({
    required String token, 
    required String deviceId,
    String? serverUrl,
  }) async {
    // Disconnect existing connection if any
    if (_socket != null) {
      await disconnect();
    }

    try {
      final url = serverUrl ?? _defaultServerUrl;
      
      _socket = IO.io(
        url,
        IO.OptionBuilder()
          .setTransports(['polling', 'websocket']) // Start with polling, upgrade to websocket
          .disableAutoConnect() // Manual connection for better control
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(5000)
          .setAuth({
            'token': token,
            'deviceId': deviceId,
          })
          .build(),
      );

      _socket!.onConnect((_) {
        _isConnected = true;
        _connectionStateController.add(true);
        print('✅ Socket.IO connected');
        print('   Transport: ${_socket!.io.engine?.transport?.name}');
      });

      _socket!.on('message', (data) {
        print('📥 Message received: $data');
        _messageController.add(data);
      });

      _socket!.onDisconnect((_) {
        _isConnected = false;
        _connectionStateController.add(false);
        print('❌ Socket.IO disconnected');
      });

      _socket!.onError((error) {
        _isConnected = false;
        print('⚠️ Socket.IO error: $error');
      });

      _socket!.onConnectError((error) {
        _isConnected = false;
        _connectionStateController.add(false);
        print('❌ Socket.IO connection error: $error');
      });

      // Listen for transport upgrades
      _socket!.io.engine?.on('upgrade', (data) {
        print('🔄 Transport upgraded to: ${_socket!.io.engine?.transport?.name}');
      });

      _socket!.connect();
      
    } catch (e) {
      _isConnected = false;
      print('Failed to initialize socket: $e');
      rethrow;
    }
  }

  // Send message to another device
  void sendMessage({required String toDeviceId, required dynamic payload}) {
    if (_socket != null && _isConnected) {
      _socket!.emit('message', {
        'to': toDeviceId,
        'payload': payload,
      });
      print('📤 Sent message to device $toDeviceId');
    } else {
      print('❌ Socket not connected');
    }
  }

  // Disconnect from server
  Future<void> disconnect() async {
    _socket?.disconnect();
    _socket?.dispose();
    _isConnected = false;
    print('Disconnected from Socket.IO server');
  }

  // Dispose resources
  void dispose() {
    disconnect();
    _messageController.close();
    _connectionStateController.close();
  }
}