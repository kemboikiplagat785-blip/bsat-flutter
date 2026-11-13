/// LAN address discovery for paired devices.
///
/// A paired phone is only reachable at the address and port it was last seen
/// on. Without discovery, a DHCP renewal, a router restart or (on Android 11+)
/// a hotspot restart, which picks a new random subnet, leaves both phones
/// dialling stale addresses forever.
///
/// Each phone that is listening broadcasts a small UDP announcement with its
/// identity fingerprint and TCP listening port. A phone that hears an
/// announcement from a *trusted* fingerprint at an address or port it does
/// not have on record verifies it with a normal authenticated probe before
/// saving it. An announcement therefore never changes anything by itself: a
/// forged one only costs a failed handshake.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_net_util.dart';

/// UDP port for announcements. Next to the TCP listening port.
const int lanDiscoveryPort = 47330;

const String _announceType = 'bsat-lan-announce';
const int _announceVersion = 1;

/// Upper bound for a valid announcement datagram.
const int _maxAnnouncementBytes = 256;

class LanAnnouncement {
  final String fingerprint;
  final int port;
  final InternetAddress address;

  const LanAnnouncement(this.fingerprint, this.port, this.address);
}

/// Encodes an announcement. Contains only the public-key fingerprint and the
/// listening port: no device name, no ID, nothing secret.
List<int> encodeLanAnnouncement(String fingerprint, int port) =>
    utf8.encode(jsonEncode({
      't': _announceType,
      'v': _announceVersion,
      'fp': fingerprint,
      'port': port,
    }));

/// Parses a datagram from [from]; null for anything that is not a well-formed
/// announcement from a private LAN address.
LanAnnouncement? decodeLanAnnouncement(List<int> bytes, InternetAddress from) {
  if (bytes.isEmpty || bytes.length > _maxAnnouncementBytes) return null;
  if (!isAllowedLanAddress(from)) return null;
  try {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) return null;
    if (decoded['t'] != _announceType || decoded['v'] != _announceVersion) {
      return null;
    }
    final fingerprint = decoded['fp'];
    final port = decoded['port'];
    if (fingerprint is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(fingerprint)) {
      return null;
    }
    if (port is! int || port <= 0 || port > 65535) return null;
    return LanAnnouncement(fingerprint, port, from);
  } catch (_) {
    return null;
  }
}

/// Broadcast targets for this device's LAN addresses: the limited broadcast
/// address plus the /24 directed broadcast of each address. Dart does not
/// expose prefix lengths; /24 covers home routers and Android hotspots, and
/// the limited broadcast covers the rest of a directly attached network.
List<InternetAddress> lanBroadcastTargets(Iterable<InternetAddress> own) {
  final targets = <String, InternetAddress>{
    '255.255.255.255': InternetAddress('255.255.255.255'),
  };
  for (final address in own) {
    if (address.type != InternetAddressType.IPv4 || address.isLoopback) {
      continue;
    }
    final b = address.rawAddress;
    final directed = '${b[0]}.${b[1]}.${b[2]}.255';
    targets[directed] = InternetAddress(directed);
  }
  return targets.values.toList();
}

/// Sends and receives announcements on one UDP socket.
class LanDiscovery {
  /// UDP port this phone listens on for announcements.
  final int port;

  /// UDP port announcements are sent to. The same as [port] on real phones;
  /// tests running two phones on one machine use different ports.
  final int announcePort;

  /// Where announcements are sent. Defaults to [lanBroadcastTargets] of the
  /// addresses passed to [announce]; tests pass loopback.
  final List<InternetAddress> Function(List<InternetAddress> own) targets;

  RawDatagramSocket? _socket;
  void Function(LanAnnouncement announcement)? _onAnnouncement;

  LanDiscovery({
    this.port = lanDiscoveryPort,
    int? announcePort,
    List<InternetAddress> Function(List<InternetAddress> own)? targets,
  })  : announcePort = announcePort ?? port,
        targets = targets ?? lanBroadcastTargets;

  bool get isRunning => _socket != null;

  /// Binds the socket (once) and delivers valid announcements to
  /// [onAnnouncement]. Failure to bind leaves discovery off; LAN still works
  /// with the addresses on record.
  Future<void> start(
    void Function(LanAnnouncement announcement) onAnnouncement,
  ) async {
    _onAnnouncement = onAnnouncement;
    if (_socket != null) return;
    try {
      final socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        port,
        reuseAddress: true,
      );
      socket.broadcastEnabled = true;
      socket.listen(
        (event) {
          if (event != RawSocketEvent.read) return;
          Datagram? datagram;
          while ((datagram = socket.receive()) != null) {
            final announcement =
                decodeLanAnnouncement(datagram!.data, datagram.address);
            if (announcement != null) _onAnnouncement?.call(announcement);
          }
        },
        onError: (Object _) => _lost(socket),
        onDone: () => _lost(socket),
        cancelOnError: true,
      );
      _socket = socket;
    } catch (error) {
      debugPrint('LAN DISCOVERY: could not bind UDP $port ($error)');
    }
  }

  void _lost(RawDatagramSocket socket) {
    if (identical(_socket, socket)) _socket = null;
  }

  /// Sends one announcement to every target. Errors (no route on one
  /// interface, broadcast refused) are ignored per target.
  void announce({
    required String fingerprint,
    required int listenPort,
    required List<InternetAddress> ownAddresses,
  }) {
    final socket = _socket;
    if (socket == null) return;
    final payload = encodeLanAnnouncement(fingerprint, listenPort);
    for (final target in targets(ownAddresses)) {
      try {
        socket.send(payload, target, announcePort);
      } catch (_) {}
    }
  }

  void stop() {
    final socket = _socket;
    _socket = null;
    _onAnnouncement = null;
    socket?.close();
  }
}
