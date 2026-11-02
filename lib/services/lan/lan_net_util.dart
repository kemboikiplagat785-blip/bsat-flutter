import 'dart:io';

/// Default BSAT LAN listening port. Distinct from the BSAT Local Lab
/// prototype's 47321 so both apps can run on one phone.
const int defaultLanForwardingPort = 47331;

/// Ports tried, in order, when the default is already in use.
const int lanForwardingPortAttempts = 10;

/// True for 10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16.
bool isPrivateIPv4(InternetAddress address) {
  if (address.type != InternetAddressType.IPv4) return false;
  final b = address.rawAddress;
  return b[0] == 10 ||
      (b[0] == 172 && b[1] >= 16 && b[1] <= 31) ||
      (b[0] == 192 && b[1] == 168);
}

/// LAN forwarding only talks to loopback or private LAN addresses, so a
/// misconfigured host can never reach the public internet.
bool isAllowedLanAddress(InternetAddress address) =>
    address.isLoopback || isPrivateIPv4(address);

class CandidateAddress {
  final String interfaceName;
  final InternetAddress address;

  const CandidateAddress(this.interfaceName, this.address);

  String get label => '${address.address} ($interfaceName)';
}

/// Interface name prefixes that never carry LAN forwarding: mobile data
/// (carriers often hand out private 10.x addresses on these) and VPN
/// tunnels. Another phone can never reach this one through them, and a
/// carrier or VPN middlebox may accept the connection and then stay silent.
const List<String> _nonLanInterfacePrefixes = [
  'rmnet', 'ccmni', 'pdp', 'clat', 'v4-', 'seth', 'dummy', 'ppp', //
  'tun', 'tap', 'ipsec', 'wg', 'utun',
];

/// Wi-Fi, hotspot and wired interfaces, preferred for LAN forwarding.
const List<String> _preferredLanInterfacePrefixes = [
  'wlan', 'swlan', 'ap', 'softap', 'wifi', 'eth', 'rndis', 'bt-pan', //
];

/// How suitable [interfaceName] is for LAN forwarding: 0 for Wi-Fi, hotspot
/// and wired, 1 for anything unrecognised, null for mobile data and VPN
/// interfaces, which are never used.
int? lanInterfaceRank(String interfaceName) {
  final name = interfaceName.toLowerCase();
  if (_nonLanInterfacePrefixes.any(name.startsWith)) return null;
  if (_preferredLanInterfacePrefixes.any(name.startsWith)) return 0;
  return 1;
}

/// Private IPv4 addresses of this device on LAN interfaces, best first
/// (Wi-Fi and hotspot before anything unrecognised), for binding the
/// receiver; the first one is put in pairing invitations. Mobile data and
/// VPN interfaces are left out.
Future<List<CandidateAddress>> listLanAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
    includeLoopback: false,
  );
  return rankLanAddresses([
    for (final interface in interfaces)
      for (final address in interface.addresses)
        CandidateAddress(interface.name, address),
  ]);
}

/// Keeps the private addresses of LAN interfaces from [candidates], ordered
/// by [lanInterfaceRank] (stable within a rank).
List<CandidateAddress> rankLanAddresses(List<CandidateAddress> candidates) {
  final ranked = [
    for (final (index, candidate) in candidates.indexed)
      if (isPrivateIPv4(candidate.address))
        if (lanInterfaceRank(candidate.interfaceName) case final rank?)
          (rank, index, candidate),
  ]..sort((a, b) =>
      a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2));
  return [for (final (_, _, candidate) in ranked) candidate];
}

/// Parses a literal IPv4 address. Hostnames are refused so the sender never
/// performs DNS lookups or resolves to an internet host.
InternetAddress? parseLanHost(String text) {
  final address = InternetAddress.tryParse(text.trim());
  if (address == null || address.type != InternetAddressType.IPv4) {
    return null;
  }
  return isAllowedLanAddress(address) ? address : null;
}

/// Why the last connection attempt or session ended. Network categories are
/// retried with backoff; security and protocol categories are not.
enum ConnectionErrorCategory {
  none,
  refused,
  noRoute,
  timeout,
  closedByPeer,
  heartbeatLost,
  networkOther,
  authenticationFailed,
  untrustedPeer,
  identityMismatch,
  incompatibleProtocol,
  protocolViolation,
  handshakeTimeout;

  bool get isRetryable => switch (this) {
        refused ||
        noRoute ||
        timeout ||
        closedByPeer ||
        heartbeatLost ||
        networkOther ||
        handshakeTimeout ||
        // A corrupted or injected record closes the session; a fresh
        // authenticated session is safe to attempt.
        protocolViolation =>
          true,
        _ => false,
      };

  bool get isAuthentication =>
      this == authenticationFailed ||
      this == untrustedPeer ||
      this == identityMismatch;
}

ConnectionErrorCategory categorizeSocketError(Object error) {
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    final message = (error.osError?.message ?? error.message).toLowerCase();
    if (message.contains('refused') || code == 111 || code == 10061) {
      return ConnectionErrorCategory.refused;
    }
    if (message.contains('no route') ||
        message.contains('unreachable') ||
        code == 113 ||
        code == 101 ||
        code == 10065 ||
        code == 10051) {
      return ConnectionErrorCategory.noRoute;
    }
    if (message.contains('timed out') || code == 110 || code == 10060) {
      return ConnectionErrorCategory.timeout;
    }
  }
  return ConnectionErrorCategory.networkOther;
}

/// Human-readable classification of a connection failure.
String describeConnectError(Object error) {
  if (error is SocketException) {
    final code = error.osError?.errorCode;
    final message = (error.osError?.message ?? error.message).toLowerCase();
    if (message.contains('refused') || code == 111 || code == 10061) {
      return 'Connection refused: receiver is reachable but not listening '
          'on that port.';
    }
    if (message.contains('no route') ||
        message.contains('unreachable') ||
        code == 113 ||
        code == 101 ||
        code == 10065 ||
        code == 10051) {
      return 'Receiver unreachable: no route to host (different network, '
          'Wi-Fi off, or client isolation).';
    }
    if (message.contains('timed out') || code == 110 || code == 10060) {
      return 'Receiver unreachable: connection timed out.';
    }
    return 'Socket error: ${error.osError?.message ?? error.message}';
  }
  return 'Connection failed: $error';
}
