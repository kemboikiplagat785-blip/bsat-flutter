// LAN management (Forward SMS → LAN) without an Online account: every
// dependency is a local fake, so the screen provably needs no backend, no
// login and no Online device record. Widget tests only; synthetic data.
import 'dart:typed_data';

import 'package:bsat/screens/online_management/lan/lan_management.dart';
import 'package:bsat/services/lan/lan_device_identity.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

LanPeer _peer(String name, int seed, {bool trusted = true}) {
  final key =
      Uint8List.fromList(List<int>.generate(32, (i) => (seed * 17 + i) & 0xff));
  return LanPeer(
    fingerprint: fingerprintOf(key),
    publicKey: key,
    deviceName: name,
    deviceId: '',
    status: trusted ? LanPeerStatus.trusted : LanPeerStatus.revoked,
    pairedAt: DateTime(2026, 10, 1),
  );
}

class _FakePeers implements LanPeerStore {
  final List<LanPeer> peers;
  _FakePeers(this.peers);

  @override
  Future<List<LanPeer>> all() async => [...peers];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// In-memory rules with the same rules as [LanForwardingRuleStore].
class _FakeRules implements LanForwardingRuleStore {
  final List<String> trusted;
  final List<LanForwardingRule> rules = [];
  int _nextId = 1;
  _FakeRules(this.trusted);

  @override
  Future<List<LanForwardingRule>> all() async => [...rules];

  @override
  Future<LanForwardingRule> create({
    required String deviceName,
    required List<int> amounts,
  }) async {
    if (!trusted.contains(deviceName)) {
      throw LanRuleException('$deviceName is not a trusted LAN device.');
    }
    if (amounts.isEmpty) {
      throw const LanRuleException('Add at least one amount to forward.');
    }
    final rule = LanForwardingRule(
      id: _nextId++,
      deviceName: deviceName,
      deviceId: 'lan:$deviceName',
      amounts: [...amounts]..sort(),
      enabled: true,
    );
    rules.add(rule);
    return rule;
  }

  @override
  Future<LanForwardingRule> update(
    int id, {
    required String deviceName,
    required List<int> amounts,
  }) async {
    final index = rules.indexWhere((rule) => rule.id == id);
    final old = rules[index];
    final rule = LanForwardingRule(
      id: id,
      deviceName: deviceName,
      deviceId: old.deviceId,
      amounts: [...amounts]..sort(),
      enabled: old.enabled,
    );
    rules[index] = rule;
    return rule;
  }

  @override
  Future<void> setEnabled(int id, bool enabled) async {
    final index = rules.indexWhere((rule) => rule.id == id);
    final old = rules[index];
    rules[index] = LanForwardingRule(
      id: id,
      deviceName: old.deviceName,
      deviceId: old.deviceId,
      amounts: old.amounts,
      enabled: enabled,
    );
  }

  @override
  Future<void> remove(int id) async => rules.removeWhere((r) => r.id == id);
}

class _Env {
  String? localName;
  final bool online;
  final _FakePeers peers;
  final _FakeRules rules;
  final probes = <String>[];
  final unpaired = <(String, bool)>[];
  final pairingOpened = <String?>[];
  final resumed = <String>[];
  LanReachability reachability = LanReachability.reachable;

  _Env({
    this.localName,
    this.online = false,
    List<LanPeer> peers = const [],
  })  : peers = _FakePeers([...peers]),
        rules = _FakeRules([
          for (final peer in peers)
            if (peer.isTrusted) peer.deviceName,
        ]);

  LanManagementDependencies get deps => LanManagementDependencies(
        peers: peers,
        rules: rules,
        probe: (name) async {
          probes.add(name);
          return reachability;
        },
        deviceName: () async => localName,
        hasOnlineName: () async => online,
        setLocalName: (name) async => localName = name,
        lanAvailable: () => true,
        unpair: (fingerprint, {required revoke}) async {
          unpaired.add((fingerprint, revoke));
          peers.peers.removeWhere((peer) => peer.fingerprint == fingerprint);
        },
        unconfirmedJobs: () async => const {},
        openPairing: (context, deviceName) async =>
            pairingOpened.add(deviceName),
        resumePausedJobs: (deviceName) async => resumed.add(deviceName),
      );
}

Future<void> _show(WidgetTester tester, _Env env) async {
  tester.view.physicalSize = const Size(1080, 4000);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      MaterialApp(home: LanManagementScreen(dependencies: env.deps)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('opens without an Online account; the phone can be named '
      'locally, then pairing opens', (tester) async {
    final env = _Env();
    await _show(tester, env);

    expect(find.text('LAN Forwarding'), findsOneWidget);
    expect(find.text('No name set'), findsOneWidget);
    expect(find.text('No trusted LAN devices'), findsOneWidget);
    expect(find.text('No LAN forwarding rules'), findsOneWidget);

    // Pairing needs this phone's name first.
    await tester.tap(find.text('Pair LAN device'));
    await tester.pumpAndSettle();
    expect(find.text('Name this phone first'), findsOneWidget);
    expect(env.pairingOpened, isEmpty);
    // The error dialog has no button: it is dismissed by tapping outside.
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Set name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('lanDeviceNameField')), 'Till 1');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(env.localName, 'Till 1');
    expect(find.text('Till 1'), findsOneWidget);
    expect(find.text('Local LAN name (no Online account needed)'),
        findsOneWidget);

    await tester.tap(find.text('Pair LAN device'));
    await tester.pumpAndSettle();
    expect(env.pairingOpened, [null]);
  });

  testWidgets('an Online device name is shown and is not renamed here',
      (tester) async {
    await _show(tester, _Env(localName: 'Online Phone', online: true));
    expect(find.text('Online Phone'), findsOneWidget);
    expect(find.text('Your Online device name'), findsOneWidget);
    expect(find.text('Rename'), findsNothing);
    expect(find.text('Set name'), findsNothing);
  });

  testWidgets('trusted devices show their checked LAN status; unreachable '
      'devices explain that jobs wait for LAN', (tester) async {
    final env = _Env(localName: 'Till 1', peers: [
      _peer('Shop Phone', 1),
      _peer('Old Phone', 2, trusted: false),
    ]);
    env.reachability = LanReachability.unreachable;
    await _show(tester, env);

    expect(find.text('Shop Phone'), findsOneWidget);
    expect(find.text('Old Phone'), findsOneWidget);
    expect(env.probes, ['Shop Phone'], reason: 'only trusted devices probed');
    expect(find.textContaining('not reachable now'), findsOneWidget);
    expect(find.textContaining('Jobs wait for retry; they are never sent '
        'online'), findsOneWidget);
    expect(find.text('Pairing revoked · pair again to use LAN'),
        findsOneWidget);

    env.reachability = LanReachability.reachable;
    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();
    expect(find.text('Paired and authenticated · reachable on this network'),
        findsOneWidget);
  });

  testWidgets('a trusted device can be revoked or removed', (tester) async {
    final shop = _peer('Shop Phone', 1);
    final env = _Env(localName: 'Till 1', peers: [shop]);
    await _show(tester, env);
    await tester.tap(find.text('Revoke'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Revoke').last);
    await tester.pumpAndSettle();
    expect(env.unpaired, [(shop.fingerprint, true)]);
    expect(find.text('No trusted LAN devices'), findsOneWidget);
  });

  testWidgets('LAN rules: add, edit, disable, enable and remove',
      (tester) async {
    final env = _Env(localName: 'Till 1', peers: [_peer('Shop Phone', 1)]);
    await _show(tester, env);

    // Add.
    await tester.tap(find.text('Add LAN rule'));
    await tester.pumpAndSettle();
    expect(find.text('Add LAN Rule'), findsOneWidget);
    final amountField = find.descendant(
        of: find.byKey(const Key('lanRuleAmounts')),
        matching: find.byType(TextField));
    await tester.enterText(amountField, '100');
    await tester.tap(find.byKey(const Key('lanRuleSave')));
    await tester.pumpAndSettle();
    expect(env.rules.rules.single.deviceName, 'Shop Phone');
    expect(env.rules.rules.single.amounts, [100]);
    expect(find.text('Ksh 100'), findsOneWidget);
    expect(find.text('Forwarding over LAN'), findsOneWidget);

    // Edit.
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(amountField, '250');
    await tester.tap(find.byKey(const Key('lanRuleSave')));
    await tester.pumpAndSettle();
    expect(env.rules.rules.single.amounts, [100, 250]);
    expect(find.text('Ksh 250'), findsOneWidget);

    // Disable, then enable.
    await tester.tap(find.byKey(const Key('lanRuleEnabled_Shop Phone')));
    await tester.pumpAndSettle();
    expect(env.rules.rules.single.enabled, isFalse);
    expect(find.text('Disabled'), findsOneWidget);
    expect(env.resumed, isEmpty, reason: 'disabling sends nothing');
    await tester.tap(find.byKey(const Key('lanRuleEnabled_Shop Phone')));
    await tester.pumpAndSettle();
    expect(env.rules.rules.single.enabled, isTrue);
    // Enabling sends the payments held while the rule was disabled.
    expect(env.resumed, ['Shop Phone']);

    // Remove.
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove').last);
    await tester.pumpAndSettle();
    expect(env.rules.rules, isEmpty);
    expect(find.text('No LAN forwarding rules'), findsOneWidget);
  });

  testWidgets('a rule cannot be added before a LAN device is trusted',
      (tester) async {
    final env = _Env(localName: 'Till 1');
    await _show(tester, env);
    await tester.tap(find.text('Add LAN rule'));
    await tester.pumpAndSettle();
    expect(find.text('No trusted LAN device'), findsOneWidget);
    expect(find.text('Add LAN Rule'), findsNothing);
  });

  testWidgets('saving a rule without amounts shows the error and saves '
      'nothing', (tester) async {
    final env = _Env(localName: 'Till 1', peers: [_peer('Shop Phone', 1)]);
    await _show(tester, env);
    await tester.tap(find.text('Add LAN rule'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('lanRuleSave')));
    await tester.pumpAndSettle();
    expect(find.text('Add at least one amount to forward.'), findsOneWidget);
    expect(env.rules.rules, isEmpty);
  });
}
