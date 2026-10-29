import 'package:bsat/components/dialogs/show_confirm_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_local_identity.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/lan_forwarding_transport.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'lan_forwarding_rule_editor.dart';
import 'lan_pair_device_page.dart';

/// Everything LAN management reads and changes. All of it is local to this
/// phone (its database, preferences and LAN service); none of it needs an
/// Online account or the backend.
class LanManagementDependencies {
  final LanPeerStore peers;
  final LanForwardingRuleStore rules;

  /// Authenticated probe of a paired device.
  final Future<LanReachability> Function(String deviceName) probe;

  /// This phone's forwarding name (Online name, else local LAN name).
  final Future<String?> Function() deviceName;
  final Future<bool> Function() hasOnlineName;
  final Future<void> Function(String name) setLocalName;

  /// Whether this phone can run LAN at all (identity and listener).
  final bool Function() lanAvailable;

  /// Revokes ([revoke] true) or removes a pairing.
  final Future<void> Function(String fingerprint, {required bool revoke})
      unpair;

  /// LAN jobs per destination name whose receipt is not confirmed yet.
  final Future<Map<String, int>> Function() unconfirmedJobs;

  /// Opens LAN pairing, optionally for [deviceName].
  final Future<void> Function(BuildContext context, String? deviceName)
      openPairing;

  const LanManagementDependencies({
    required this.peers,
    required this.rules,
    required this.probe,
    required this.deviceName,
    required this.hasOnlineName,
    required this.setLocalName,
    required this.lanAvailable,
    required this.unpair,
    required this.unconfirmedJobs,
    required this.openPairing,
  });

  factory LanManagementDependencies.production() {
    final peers = LanPeerStore();
    return LanManagementDependencies(
      peers: peers,
      rules: LanForwardingRuleStore(peers: peers),
      probe: LanServiceRegistry.probe,
      deviceName: forwardingDeviceName,
      hasOnlineName: hasOnlineDeviceName,
      setLocalName: setLanLocalDeviceName,
      lanAvailable: () => LanForwardingService.instance != null,
      unpair: (fingerprint, {required revoke}) async {
        final service = LanForwardingService.instance;
        if (service != null) {
          revoke
              ? await service.revoke(fingerprint)
              : await service.remove(fingerprint);
        } else {
          revoke
              ? await peers.revoke(fingerprint)
              : await peers.remove(fingerprint);
        }
      },
      unconfirmedJobs: _unconfirmedLanJobs,
      openPairing: (context, deviceName) => Navigator.of(context).push(
        CupertinoPageRoute(
          builder: (_) => LanPairDevicePage(initialDeviceName: deviceName),
        ),
      ),
    );
  }

  static Future<Map<String, int>> _unconfirmedLanJobs() async {
    final rows = await SQLiteService().queryCustom(
      'transactions',
      "forwardingTransport = 'lan' AND status IN (?, ?) AND "
          'NOT EXISTS (SELECT 1 FROM forwardingDeliveryRetries r '
          'WHERE r.forwardingJobId = transactions.forwardingJobId '
          'AND r.acknowledged = 1)',
      [TransactionStatuses.error, TransactionStatuses.forwardedPending],
      columns: ['forwardingRecipientDeviceName'],
    );
    final counts = <String, int>{};
    for (final row in rows) {
      final name = row['forwardingRecipientDeviceName']?.toString() ?? '';
      if (name.isNotEmpty) counts[name] = (counts[name] ?? 0) + 1;
    }
    return counts;
  }
}

/// LAN forwarding management, opened from Forward SMS → LAN: this phone's
/// LAN name, its trusted LAN devices, and the forwarding rules whose jobs
/// go over LAN. Works without an Online account; jobs to a LAN destination
/// are never sent online or by SMS.
class LanManagementScreen extends StatefulWidget {
  /// Defaults to [LanManagementDependencies.production]; tests inject fakes.
  final LanManagementDependencies? dependencies;

  const LanManagementScreen({super.key, this.dependencies});

  @override
  State<LanManagementScreen> createState() => _LanManagementScreenState();
}

class _LanManagementScreenState extends State<LanManagementScreen> {
  late final LanManagementDependencies _deps =
      widget.dependencies ?? LanManagementDependencies.production();

  bool _loading = true;
  String? _loadError;
  String _deviceName = '';
  bool _onlineName = false;
  List<LanPeer> _peers = [];
  List<LanForwardingRule> _rules = [];
  Map<String, int> _unconfirmed = {};

  /// Latest authenticated probe per device name; absent while checking.
  final Map<String, LanReachability> _reachability = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final name = (await _deps.deviceName() ?? '').trim();
      final online = await _deps.hasOnlineName();
      final peers = await _deps.peers.all();
      final rules = await _deps.rules.all();
      final unconfirmed = await _deps.unconfirmedJobs();
      if (!mounted) return;
      setState(() {
        _deviceName = name;
        _onlineName = online;
        _peers = peers;
        _rules = rules;
        _unconfirmed = unconfirmed;
        _loadError = null;
        _loading = false;
      });
      _probeAll();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = 'Could not load LAN settings: $error';
        _loading = false;
      });
    }
  }

  void _probeAll() {
    for (final peer in _peers.where((peer) => peer.isTrusted)) {
      final name = peer.deviceName;
      _reachability.remove(name);
      _deps.probe(name).then((result) {
        if (mounted) setState(() => _reachability[name] = result);
      });
    }
    if (mounted) setState(() {});
  }

  LanPeer? _trustedPeer(String name) =>
      _peers.where((peer) => peer.deviceName == name && peer.isTrusted).firstOrNull;

  List<String> get _trustedNames =>
      [for (final peer in _peers) if (peer.isTrusted) peer.deviceName];

  // ------------------------------------------------------------- actions

  Future<void> _editName() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _LanNameDialog(initialName: _deviceName),
    );
    if (name == null || name == _deviceName || !mounted) return;
    if (_peers.isNotEmpty) {
      final confirmed = await showConfirmDialog(
        context,
        title: 'Rename this phone?',
        message: 'Phones already paired know this phone as "$_deviceName". '
            'After renaming they must pair with it again before LAN '
            'forwarding works.',
        btnText: 'Rename',
      );
      if (confirmed != true || !mounted) return;
    }
    try {
      await _deps.setLocalName(name);
    } catch (error) {
      if (mounted) showErrorDialog(context, 'Error', '$error');
      return;
    }
    await _load();
  }

  Future<void> _pair([String? deviceName]) async {
    if (_deviceName.isEmpty) {
      showErrorDialog(context, 'Name this phone first',
          'Set this phone\'s LAN name before pairing, so the other phone '
              'can recognise it.');
      return;
    }
    if (!_deps.lanAvailable()) {
      showErrorDialog(context, 'LAN unavailable',
          'LAN forwarding is not available on this phone right now. Reopen '
              'BSAT and try again.');
      return;
    }
    await _deps.openPairing(context, deviceName);
    await _load();
  }

  Future<void> _unpair(LanPeer peer, {required bool revoke}) async {
    final name = peer.deviceName;
    final confirmed = await showConfirmDialog(
      context,
      title: revoke ? 'Revoke LAN pairing?' : 'Remove LAN pairing?',
      message: revoke
          ? '$name\'s key will be refused over LAN from now on. Pair again '
              'to restore LAN forwarding.'
          : 'The LAN pairing with $name will be deleted. Pair again to '
              'restore LAN forwarding.',
      btnText: revoke ? 'Revoke' : 'Remove',
    );
    if (confirmed != true) return;
    try {
      await _deps.unpair(peer.fingerprint, revoke: revoke);
    } catch (error) {
      if (mounted) showErrorDialog(context, 'Error', 'Could not update: $error');
      return;
    }
    await _load();
  }

  Future<void> _openRule([LanForwardingRule? rule]) async {
    if (rule == null && _trustedNames.isEmpty) {
      showErrorDialog(context, 'No trusted LAN device',
          'Pair a LAN device first, then add a forwarding rule for it.');
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => LanForwardingRuleEditor(
          store: _deps.rules,
          trustedDeviceNames: _trustedNames,
          rule: rule,
        ),
      ),
    );
    await _load();
  }

  Future<void> _setEnabled(LanForwardingRule rule, bool enabled) async {
    try {
      await _deps.rules.setEnabled(rule.id, enabled);
    } catch (error) {
      if (mounted) showErrorDialog(context, 'Error', '$error');
    }
    await _load();
  }

  Future<void> _removeRule(LanForwardingRule rule) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Remove LAN rule?',
      message: 'New payments will no longer be forwarded to '
          '${rule.deviceName} over LAN. Jobs already sent keep their '
          'transport.',
      btnText: 'Remove',
    );
    if (confirmed != true) return;
    try {
      await _deps.rules.remove(rule.id);
    } catch (error) {
      if (mounted) showErrorDialog(context, 'Error', '$error');
    }
    await _load();
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              leading: IconButton(
                icon: const Icon(CupertinoIcons.back),
                onPressed: () => Navigator.pop(context),
              ),
              backgroundColor: theme.colorScheme.surface,
              elevation: 0,
              title: const Text(
                'LAN Forwarding',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              actions: [
                IconButton(
                  tooltip: 'Check connections',
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: _loading ? null : _load,
                ),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.all(kPagePadding),
              sliver: SliverList(
                delegate: SliverChildListDelegate(
                  _loading
                      ? [const Center(child: CircularProgressIndicator())]
                      : _loadError != null
                          ? [
                              Text(_loadError!,
                                  style:
                                      const TextStyle(color: Colors.redAccent)),
                            ]
                          : _content(theme),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _content(ThemeData theme) => [
        Text(
          'Forward payments to your own phones on the same Wi-Fi or hotspot. '
          'No Online account is needed, and jobs for a LAN device are never '
          'sent online or by SMS.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: kPagePadding),
        _sectionHeader('This Phone', Icons.smartphone_rounded),
        _thisPhoneCard(),
        const SizedBox(height: kPagePadding * 1.5),
        _sectionHeader('Trusted LAN Devices', Icons.wifi_rounded),
        Text(
          'Pair on both phones: one shows a QR code, the other scans it, and '
          'both confirm the same 6-digit code.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: kPagePadding / 2),
        if (_peers.isEmpty)
          _emptyState('No trusted LAN devices', Icons.wifi_off_rounded)
        else
          ..._peers.map(_peerCard),
        _addButton('Pair LAN device', () => _pair()),
        const SizedBox(height: kPagePadding * 1.5),
        _sectionHeader('LAN Forwarding Rules', Icons.shortcut),
        Text(
          'Forward MPESA payments of these amounts to a trusted LAN device.',
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: kPagePadding / 2),
        if (_rules.isEmpty)
          _emptyState('No LAN forwarding rules', Icons.alt_route_rounded)
        else
          ..._rules.map(_ruleCard),
        _addButton('Add LAN rule', () => _openRule()),
        const SizedBox(height: kPagePadding * 2),
      ];

  Widget _thisPhoneCard() {
    final named = _deviceName.isNotEmpty;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: kPrimaryColor.withValues(alpha: 0.1),
                child:
                    const Icon(Icons.smartphone_rounded, color: kPrimaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      named ? _deviceName : 'No name set',
                      key: const Key('lanThisPhoneName'),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      _onlineName
                          ? 'Your Online device name'
                          : named
                              ? 'Local LAN name (no Online account needed)'
                              : 'Set a name so other phones can pair with '
                                  'this one',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              if (!_onlineName)
                OutlinedButton(
                  onPressed: _editName,
                  child: Text(named ? 'Rename' : 'Set name'),
                ),
            ],
          ),
          if (!_deps.lanAvailable()) ...[
            const SizedBox(height: 8),
            _statusRow(
              Icons.error_outline_rounded,
              Colors.redAccent,
              'LAN is not running on this phone. Reopen BSAT; LAN needs '
              'Android with a secure key store.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _peerCard(LanPeer peer) {
    final name = peer.deviceName;
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: kPrimaryColor.withValues(alpha: 0.1),
                child: const Icon(Icons.wifi_rounded, color: kPrimaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text('Key ${peer.displayId.substring(0, 19)}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _peerStatus(peer),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (peer.isTrusted)
                OutlinedButton(
                  onPressed: _probeAll,
                  child: const Text('Check'),
                ),
              OutlinedButton(
                onPressed: () => _pair(name),
                child: const Text('Pair again'),
              ),
              if (peer.isTrusted)
                OutlinedButton(
                  onPressed: () => _unpair(peer, revoke: true),
                  child: const Text('Revoke'),
                ),
              OutlinedButton(
                onPressed: () => _unpair(peer, revoke: false),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _ruleCard(LanForwardingRule rule) {
    final name = rule.deviceName;
    final unconfirmed = _unconfirmed[name] ?? 0;
    final peer = _trustedPeer(name);
    return _card(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: kPrimaryColor.withValues(alpha: 0.1),
                child: const Icon(Icons.alt_route_rounded,
                    color: kPrimaryColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(
                      rule.enabled ? 'Forwarding over LAN' : 'Disabled',
                      style: TextStyle(
                        fontSize: 11,
                        color: rule.enabled ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                key: Key('lanRuleEnabled_$name'),
                value: rule.enabled,
                onChanged: (value) => _setEnabled(rule, value),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final amount in rule.amounts) _amountTag('Ksh $amount'),
            ],
          ),
          const SizedBox(height: 8),
          if (peer != null)
            _peerStatus(peer)
          else
            _statusRow(
              Icons.link_off_rounded,
              Colors.orange,
              '$name is not a trusted LAN device: it gets no new jobs until '
              'it is paired.',
            ),
          if (!rule.lanOnly)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _statusRow(
                Icons.cloud_outlined,
                Colors.grey,
                'Online device switched to LAN in Online management.',
              ),
            ),
          if (unconfirmed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$unconfirmed LAN job(s) not yet received by $name; they '
                'will be retried over LAN with the same job identity.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          const Divider(height: 24, thickness: 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _removeRule(rule),
                icon: const Icon(CupertinoIcons.trash, size: 16),
                label: const Text('Remove'),
                style: TextButton.styleFrom(foregroundColor: kErrorColor),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _openRule(rule),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _peerStatus(LanPeer peer) {
    final name = peer.deviceName;
    if (!peer.isTrusted) {
      return _statusRow(Icons.block_rounded, Colors.redAccent,
          'Pairing revoked · pair again to use LAN');
    }
    return switch (_reachability[name]) {
      null => _statusRow(Icons.sync_rounded, Colors.grey,
          'Paired · checking the local network…'),
      LanReachability.reachable => _statusRow(Icons.check_circle_rounded,
          Colors.green, 'Paired and authenticated · reachable on this network'),
      LanReachability.authenticationFailed => _statusRow(Icons.gpp_bad_rounded,
          Colors.redAccent, 'Paired, but authentication failed · pair again'),
      LanReachability.notConfigured => _statusRow(
          Icons.error_outline_rounded,
          Colors.redAccent,
          'LAN is not running on this phone · reopen the app'),
      _ => _statusRow(
          Icons.wifi_off_rounded,
          Colors.orange,
          'Paired · not reachable now (other network, or BSAT closed on '
          '$name). Jobs wait for retry; they are never sent online.'),
    };
  }

  Widget _statusRow(IconData icon, Color color, String text) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(text, style: TextStyle(fontSize: 12, color: color)),
          ),
        ],
      );

  Widget _card(Widget child) => Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        ),
        child: child,
      );

  Widget _sectionHeader(String title, IconData icon) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: [
            Icon(icon, size: 18, color: kPrimaryColor),
            const SizedBox(width: 8),
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
      );

  Widget _emptyState(String text, IconData icon) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.grey),
            const SizedBox(height: 8),
            Text(text, style: const TextStyle(color: Colors.grey)),
          ],
        ),
      );

  Widget _addButton(String label, VoidCallback onTap) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onTap,
          icon: const Icon(Icons.add),
          label: Text(label),
        ),
      );

  Widget _amountTag(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: kPrimaryColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text,
            style: const TextStyle(fontSize: 12, color: kPrimaryColor)),
      );
}

/// Asks for this phone's LAN name; pops the valid, trimmed name.
class _LanNameDialog extends StatefulWidget {
  final String initialName;

  const _LanNameDialog({required this.initialName});

  @override
  State<_LanNameDialog> createState() => _LanNameDialogState();
}

class _LanNameDialogState extends State<_LanNameDialog> {
  late final _controller = TextEditingController(text: widget.initialName);
  String? _problem;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final problem = lanDeviceNameProblem(_controller.text);
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, _controller.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text("This phone's LAN name"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Other phones pair with this name. It stays on this phone and '
              'needs no Online account.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('lanDeviceNameField'),
              controller: _controller,
              autofocus: true,
              maxLength: lanDeviceNameMaxChars,
              decoration: InputDecoration(
                labelText: 'Name',
                errorText: _problem,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(onPressed: _save, child: const Text('Save')),
        ],
      );
}
