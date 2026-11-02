// Which network interfaces LAN forwarding listens on and puts in pairing
// invitations: Wi-Fi/hotspot first; never mobile data or VPN tunnels, whose
// private 10.x addresses another phone cannot reach.
import 'dart:io';

import 'package:bsat/services/lan/lan_net_util.dart';
import 'package:flutter_test/flutter_test.dart';

CandidateAddress _c(String name, String ip) =>
    CandidateAddress(name, InternetAddress(ip));

void main() {
  test('mobile data and VPN interfaces are never used', () {
    for (final name in [
      'rmnet_data0',
      'rmnet0',
      'ccmni1',
      'v4-rmnet_data0',
      'clat4',
      'tun0',
      'ipsec0',
      'wg0',
      'dummy0',
    ]) {
      expect(lanInterfaceRank(name), isNull, reason: name);
    }
  });

  test('Wi-Fi, hotspot and wired interfaces are preferred', () {
    for (final name in ['wlan0', 'wlan1', 'swlan0', 'ap0', 'softap0', 'eth0']) {
      expect(lanInterfaceRank(name), 0, reason: name);
    }
    expect(lanInterfaceRank('br0'), 1, reason: 'unknown: allowed, not first');
  });

  test('a carrier 10.x address listed first never becomes the invitation '
      'address; Wi-Fi does', () {
    final ranked = rankLanAddresses([
      _c('rmnet_data2', '10.120.33.7'),
      _c('tun0', '10.8.0.2'),
      _c('br0', '192.168.50.1'),
      _c('wlan0', '192.168.1.240'),
      _c('wlan1', '8.8.8.8'),
    ]);
    expect(ranked.map((c) => c.label), [
      '192.168.1.240 (wlan0)',
      '192.168.50.1 (br0)',
    ]);
  });

  test('order is kept within a rank', () {
    final ranked = rankLanAddresses([
      _c('wlan0', '192.168.1.5'),
      _c('ap0', '192.168.43.1'),
    ]);
    expect(ranked.map((c) => c.interfaceName), ['wlan0', 'ap0']);
  });
}
