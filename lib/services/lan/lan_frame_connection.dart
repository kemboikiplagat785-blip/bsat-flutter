import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'lan_framing.dart';

class ConnectionClosedException implements Exception {
  final String reason;

  const ConnectionClosedException(this.reason);

  @override
  String toString() => 'ConnectionClosedException: $reason';
}

/// A socket carrying length-prefixed frames, read with explicit timeouts.
/// One consumer at a time calls [next].
class FrameConnection {
  final Socket socket;
  final String remoteAddress;
  final int remotePort;
  final FrameDecoder _decoder = FrameDecoder();
  final Queue<Uint8List> _frames = Queue();
  Completer<void>? _signal;
  final Completer<void> _done = Completer<void>();
  Object? _failure;
  bool _closed = false;

  /// Completes once the connection is closed for any reason.
  Future<void> get done => _done.future;

  FrameConnection(this.socket)
      : remoteAddress = socket.remoteAddress.address,
        remotePort = socket.remotePort {
    try {
      socket.setOption(SocketOption.tcpNoDelay, true);
    } catch (_) {}
    socket.listen(
      _onData,
      onError: (Object error) {
        _failure ??= error;
        _markClosed();
      },
      onDone: _markClosed,
      cancelOnError: true,
    );
  }

  String get remote => '$remoteAddress:$remotePort';
  bool get isClosed => _closed;

  void _onData(Uint8List chunk) {
    if (_closed) return;
    try {
      _frames.addAll(_decoder.add(chunk));
    } on FrameException catch (error) {
      _failure ??= error;
      close();
      return;
    }
    _notify();
  }

  void _markClosed() {
    _closed = true;
    if (!_done.isCompleted) _done.complete();
    _notify();
  }

  void _notify() {
    final signal = _signal;
    _signal = null;
    if (signal != null && !signal.isCompleted) signal.complete();
  }

  /// Next frame payload. Throws [TimeoutException], [FrameException],
  /// [ConnectionClosedException] or the socket error.
  Future<Uint8List> next({Duration? timeout}) async {
    final deadline = timeout == null ? null : DateTime.now().add(timeout);
    while (_frames.isEmpty) {
      final failure = _failure;
      if (failure != null) throw failure;
      if (_closed) {
        throw const ConnectionClosedException('Connection closed by peer.');
      }
      final signal = _signal ??= Completer<void>();
      if (deadline == null) {
        await signal.future;
      } else {
        final remaining = deadline.difference(DateTime.now());
        if (remaining <= Duration.zero) {
          throw TimeoutException('No frame received in time.');
        }
        await signal.future.timeout(remaining);
      }
    }
    return _frames.removeFirst();
  }

  void sendPayload(List<int> payload) {
    if (_closed) throw const ConnectionClosedException('Connection closed.');
    try {
      socket.add(encodeFramePayload(payload));
    } on FrameException {
      rethrow;
    } catch (error) {
      _markClosed();
      throw ConnectionClosedException('Write failed: $error');
    }
  }

  /// Sends a JSON object and returns the exact payload bytes sent.
  Uint8List sendJson(Map<String, Object?> json) {
    final payload = Uint8List.fromList(utf8.encode(jsonEncode(json)));
    sendPayload(payload);
    return payload;
  }

  Future<void> flush() async {
    try {
      await socket.flush().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  void close() {
    socket.destroy();
    _markClosed();
  }
}
