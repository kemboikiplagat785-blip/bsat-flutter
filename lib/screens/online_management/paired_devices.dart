import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_confirm_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/screens/online_management/edit_forwarder.dart';
import 'package:bsat/screens/online_management/lan/lan_pair_device_page.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/forwarding_transport_selection.dart';
import 'package:bsat/services/lan/lan_forwarding_rules.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/lan_forwarding_transport.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/shared_preferences_service.dart';
import '../../services/sqlite_service.dart';

class PairedDevices extends StatefulWidget {
  const PairedDevices({super.key});

  @override
  State<PairedDevices> createState() => _PairedDevicesState();
}

class _PairedDevicesState extends State<PairedDevices> {
  List<Map<String, dynamic>> pairedDevices = [];
  List<Map<String, dynamic>> forwardingDevices = [];

  List<dynamic> _pendingPairings = [];

  /// LAN pairing record per device name (trusted, revoked or none).
  Map<String, LanPeerLookup> _lanPeers = {};

  /// Every LAN pairing record on this phone, for the LAN section.
  List<LanPeer> _lanPairings = [];

  /// Result of the latest authenticated LAN probe per device name. Absent
  /// while checking: a past pairing alone never shows as reachable.
  final Map<String, LanReachability> _lanReachability = {};

  /// LAN jobs per device name whose receipt has not been confirmed.
  Map<String, int> _lanUnconfirmedJobs = {};

  BackendService backendService = BackendService();

  String myDeviceName = '';

  Future<void> _unlinkDevice(String targetDeviceName) async {
    bool confirmed = await showConfirmDeleteDialog(context,
            message: "Are you sure you want to unlink this device?") ??
        false;
    if (!confirmed) return;

    if (!mounted) return;
    showLoadingDialog(context, text: "Unlinking Device...");

    final response = await backendService.post('/api/device/unlink', body: {
      'myDeviceName': myDeviceName,
      'otherDeviceName': targetDeviceName,
    });

    if (mounted) Navigator.of(context).pop();

    if (response['success']) {
      await getData();
      if (mounted) showSuccessDialog(context, text: "Device unlinked");
    } else {
      if (mounted) {
        if (response['body'] != null &&
            response['body']['error'] == 'Pairing not found') {
          // delete device from local db
          await SQLiteService().deleteWhere(
              'whitelistedDevices', 'device_name = ?', [targetDeviceName]);
          await getData();
          if (mounted) showSuccessDialog(context, text: "Device unlinked");
        }
        showErrorDialog(context, "Error",
            response['message'] ?? "Failed to unlink device.");
      }
    }
  }

  void _editForwarder(dynamic id) async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => EditForwarder(dbId: id),
      ),
    );
    await getData();
  }

  /// Toggles the 'paused' state of a forwarding rule in the local database
  Future<void> _togglePause(Map<String, dynamic> device) async {
    bool isPaused = (device['paused'] ?? 0) == 1;
    final newStatus = isPaused ? 0 : 1;

    await SQLiteService().updateStuff(
      {'paused': newStatus},
      'id = ?',
      [device['id']],
      'forwardingDevices',
    );

    if (newStatus == 0) {
      try {
        await TransactionController().resumePausedForwardingTransactions(
          device['device_name']?.toString() ?? '',
        );
      } catch (e) {
        debugPrint('Error resuming paused forwarding transactions: $e');
        rethrow;
      }
    }

    // Refresh data and show a snackbar with modern styling
    await getData();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(newStatus == 1 ? "Forwarding Paused" : "Forwarding Resumed"),
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(kPagePadding),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  /// Removes a forwarding rule after user confirmation
  Future<void> _deleteForwarder(dynamic id) async {
    bool confirmed = await showConfirmDeleteDialog(
          context,
          message: "Are you sure you want to remove this forwarding rule?",
        ) ??
        false;

    if (!confirmed) return;
    if (!mounted) return;

    showLoadingDialog(context, text: "Removing rule...");

    try {
      await SQLiteService().deleteWhere(
        'forwardingDevices',
        'id = ?',
        [id],
      );

      if (mounted) Navigator.pop(context); // Close loading dialog
      await getData(); // Refresh UI
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        showErrorDialog(context, "Error", "Could not delete: $e");
      }
    }
  }

  Future<void> getData() async {
    // get data from endpoint /whitelisted
    // then update whitelistedDevices with the new data
    await _loadPendingPairings();
    showLoadingDialog(context, text: "Fetching paired devices...");
    pairedDevices = await backendService
        .get('/api/device/whitelisted')
        .then((response) async {
      if (response['success']) {
        final data = response['data'];
        final refreshed =
            await SQLiteService().refreshWhitelistedDevices(data);
        return refreshed ??
            await SQLiteService().queryAll('whitelistedDevices');
      } else {
        return await SQLiteService().queryAll('whitelistedDevices');
      }
    });

    // Rules created in LAN management have no Online device; they are
    // managed there (Forward SMS -> LAN) and not listed here.
    forwardingDevices = (await SQLiteService().queryAll('forwardingDevices'))
        .where((device) => !isLanOnlyForwardingRow(device))
        .toList();
    await _loadLanState();

    Navigator.of(context).pop(); // Hide loading

    setState(() {});
    _probeLanDevices();
  }

  Future<void> _loadLanState() async {
    final store = LanPeerStore();
    _lanPairings = await store.all();
    final names = <String>{
      for (final device in forwardingDevices)
        device['device_name']?.toString() ?? '',
      for (final device in pairedDevices) device['device_name']?.toString() ?? '',
      for (final peer in _lanPairings) peer.deviceName,
    }..remove('');
    _lanPeers = {
      for (final name in names) name: await store.lookupDevice(name),
    };
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
    _lanUnconfirmedJobs = counts;
  }

  /// Checks every paired LAN forwarding destination with an authenticated
  /// probe. Results arrive one by one; until then the device shows
  /// "checking".
  void _probeLanDevices() {
    for (final peer in _lanPairings) {
      final name = peer.deviceName;
      if (_lanPeers[name]?.state != LanPeerLookupState.trusted) continue;
      _lanReachability.remove(name);
      LanServiceRegistry.probe(name).then((result) {
        if (!mounted) return;
        setState(() => _lanReachability[name] = result);
      });
    }
    if (mounted) setState(() {});
  }

  /// Changes the transport for *new* jobs to [device]. Jobs that already
  /// exist keep the transport they were created with.
  Future<void> _changeTransport(
    Map<String, dynamic> device,
    ForwardingTransportKind kind,
  ) async {
    final name = device['device_name']?.toString() ?? 'this device';
    final paired = _lanPeers[name]?.state == LanPeerLookupState.trusted;
    final confirmed = await showConfirmDialog(
      context,
      title: kind == ForwardingTransportKind.lan
          ? 'Forward to $name over LAN?'
          : 'Forward to $name online?',
      message: kind == ForwardingTransportKind.lan
          ? 'New forwarding jobs for $name will be sent only over the local '
              'network, never online.'
              '${paired ? '' : ' $name is not paired yet: it will not receive new jobs until you pair it.'}'
              ' Jobs already sent keep their current transport.'
          : 'New forwarding jobs for $name will be sent online, as before. '
              'Jobs already sent keep their current transport.',
      btnText: 'Change',
    );
    if (confirmed != true) return;
    try {
      await SQLiteForwardingTransportPreferences().save(
        ForwardingDestination.fromDeviceRow(device),
        kind,
      );
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, 'Error', 'Could not save the transport: $e');
      }
      return;
    }
    await getData();
  }

  /// Opens "Pair Device over LAN" (the LAN counterpart of "Pair New
  /// Device"), optionally with [deviceName] preselected.
  Future<void> _openLanPairing([String? deviceName]) async {
    if (LanForwardingService.instance == null) {
      showErrorDialog(context, 'LAN unavailable',
          'LAN forwarding is not available on this device.');
      return;
    }
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => LanPairDevicePage(initialDeviceName: deviceName),
      ),
    );
    await getData();
  }

  /// Revoke keeps the record (shown as revoked) and refuses that phone's
  /// key from now on; remove deletes the record. Both need a new pairing to
  /// trust the phone again. Neither changes the backend pairing.
  Future<void> _unpairLan(String name, {required bool revoke}) async {
    final peer = _lanPeers[name]?.peer;
    final service = LanForwardingService.instance;
    if (peer == null) return;
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
      if (service != null) {
        revoke
            ? await service.revoke(peer.fingerprint)
            : await service.remove(peer.fingerprint);
      } else {
        final store = LanPeerStore();
        revoke
            ? await store.revoke(peer.fingerprint)
            : await store.remove(peer.fingerprint);
      }
    } catch (e) {
      if (mounted) showErrorDialog(context, 'Error', 'Could not update: $e');
      return;
    }
    await getData();
  }

  Future<void> _respondToPairing(String requestId, bool accept) async {
    showLoadingDialog(context, text: accept ? "Accepting..." : "Rejecting...");

    try {
      final backendService = BackendService();
      final response = await backendService.post(
        '/api/device/respond-pairing',
        body: {
          'id': requestId,
          'accept': accept,
        },
      );

      // Hide loading dialog
      if (mounted) Navigator.pop(context);

      if (response['success']) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(accept ? "Pairing Accepted" : "Pairing Rejected"),
            ),
          );
          // Refresh the list
          _loadPendingPairings();
          await getData();
        }
      } else {
        if (mounted) {
          showErrorDialog(context, "Error",
              response['message'] ?? "Failed to update pairing status.");
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Hide loading
        showErrorDialog(context, "Error", "An error occurred: $e");
      }
    }
  }

  Future<void> _loadPendingPairings() async {
    myDeviceName =
        await SharedPreferencesService().getDeviceName() ?? "Unknown";
    if (myDeviceName == "Loading..." || myDeviceName == "Unknown") return;

    showLoadingDialog(context, text: "Loading pending pairings...");

    try {
      final backendService = BackendService();
      final response = await backendService
          .get('/api/device/pending-pairings?myDeviceName=$myDeviceName');
      if (response['success'] && mounted) {
        setState(() {
          _pendingPairings = response['data']['requests'] ?? [];
        });
      }
    } catch (e) {
      debugPrint("Error loading pending pairings: $e");
    }

    Navigator.of(context).pop(); // Hide loading
    setState(() {}); // Refresh UI with new pending pairings
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      getData();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Modern Header
          SliverAppBar(
            expandedHeight: 120,
            floating: true,
            pinned: true,
            elevation: 0,
            backgroundColor: theme.colorScheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              titlePadding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              title: Text(
                "Paired Devices & Forwarding",
                style: TextStyle(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: kPagePadding),
                  _buildSectionHeader(
                      "Pending Requests", Icons.notification_important_rounded),
                  if (_pendingPairings.isEmpty)
                    _buildEmptyState(
                        "No pending requests", Icons.auto_awesome_rounded)
                  else
                    ..._pendingPairings
                        .map((pairing) => _buildModernPendingItem(pairing)),
                  const SizedBox(height: kPagePadding),
                  _buildSectionHeader(
                      "Paired Devices", Icons.devices_other_rounded),
                  Text(
                    "Phones which you trust to forward to you MPESA messages",
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  if (pairedDevices.isEmpty)
                    _buildEmptyState(
                        "No paired devices", Icons.phonelink_off_rounded)
                  else
                    ...pairedDevices
                        .map((device) => _buildModernDeviceCard(device)),
                  _buildAddButton(() => _navigateToPairPage()),
                  const SizedBox(height: kPagePadding),
                  _buildSectionHeader("LAN Paired Devices", Icons.wifi_rounded),
                  Text(
                    "Phones paired for forwarding over the local network "
                    "(same Wi-Fi or hotspot). Tap + on both phones.",
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  if (_lanPairings.isEmpty)
                    _buildEmptyState(
                        "No LAN paired devices", Icons.wifi_off_rounded)
                  else
                    ..._lanPairings.map(_buildLanPairingCard),
                  _buildAddButton(() => _openLanPairing()),
                  const SizedBox(height: kPagePadding),
                  _buildSectionHeader("Forwarding Rules", Icons.shortcut),
                  Text(
                    "Forward certain amounts from MPESA ",
                    style:
                        theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  if (forwardingDevices.isEmpty)
                    _buildEmptyState("No forwarding rules", Icons.rule_rounded)
                  else
                    ...forwardingDevices
                        .map((device) => _buildModernForwarderCard(device)),
                  _buildAddButton(() => _navigateToEditForwarder()),
                  const SizedBox(height: kPagePadding),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 20, color: kPrimaryColor),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 13,
            letterSpacing: 1.2,
            color: kPrimaryColor,
          ),
        ),
      ],
    );
  }

  Widget _buildModernDeviceCard(Map<String, dynamic> device) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: kPrimaryColor.withValues(alpha: 0.1),
          child: const Icon(Icons.smartphone_rounded, color: kPrimaryColor),
        ),
        title: Text(device['device_name'],
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle:
            Text(device['owner_email'], style: const TextStyle(fontSize: 12)),
        trailing: IconButton(
          icon:
              const Icon(CupertinoIcons.minus_circle, color: Colors.redAccent),
          onPressed: () => _unlinkDevice(device['device_name']),
        ),
      ),
    );
  }

  Widget _buildModernForwarderCard(Map<String, dynamic> device) {
    bool isPaused = (device['paused'] ?? 0) == 1;
    List amounts = device["amounts_to_forward"] != null
        ? (jsonDecode(device["amounts_to_forward"]) as List)
            .map((e) => e.toString())
            .toList()
        : [];

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(
          color: isPaused
              ? Colors.orange.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(device['device_name'] ?? 'Unknown',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 17)),
                    Text(device['owner_email'] ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              if (isPaused)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text("PAUSED",
                      style: TextStyle(
                          color: Colors.orange,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: amounts.map((amt) => _buildAmountTag(amt)).toList(),
          ),
          const SizedBox(height: 12),
          _buildTransportSection(device),
          const Divider(height: 32, thickness: 0.5),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildIconButton(Icons.edit_outlined, kPrimaryColor,
                  () => _editForwarder(device['id'])),
              const SizedBox(width: 8),
              _buildIconButton(
                isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                isPaused ? Colors.green : Colors.orange,
                () => _togglePause(device),
              ),
              const SizedBox(width: 8),
              _buildIconButton(Icons.delete_outline_rounded, Colors.redAccent,
                  () => _deleteForwarder(device['id'])),
            ],
          )
        ],
      ),
    );
  }

  Widget _buildTransportSection(Map<String, dynamic> device) {
    final name = device['device_name']?.toString() ?? '';
    final kind = parseForwardingTransportPreference(
      device['forwarding_transport'],
    );
    final lookup = _lanPeers[name];
    final unconfirmed = _lanUnconfirmedJobs[name] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Transport',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
            const Spacer(),
            SegmentedButton<ForwardingTransportKind>(
              segments: const [
                ButtonSegment(
                  value: ForwardingTransportKind.online,
                  label: Text('Online'),
                  icon: Icon(Icons.cloud_outlined, size: 16),
                ),
                ButtonSegment(
                  value: ForwardingTransportKind.lan,
                  label: Text('LAN'),
                  icon: Icon(Icons.wifi_rounded, size: 16),
                ),
              ],
              selected: {kind},
              showSelectedIcon: false,
              onSelectionChanged: (selection) {
                if (selection.first != kind) {
                  _changeTransport(device, selection.first);
                }
              },
            ),
          ],
        ),
        if (kind == ForwardingTransportKind.lan) ...[
          const SizedBox(height: 8),
          _buildLanStatus(name, lookup),
          if (unconfirmed > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '$unconfirmed LAN job(s) not yet received by $name; they will '
                'be retried over LAN.',
                style: const TextStyle(fontSize: 12, color: Colors.orange),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              OutlinedButton.icon(
                onPressed: () => _openLanPairing(name),
                icon: const Icon(Icons.qr_code_scanner_rounded, size: 16),
                label: Text(lookup?.state == LanPeerLookupState.trusted
                    ? 'Pair again'
                    : 'Pair over LAN'),
              ),
              if (lookup?.state == LanPeerLookupState.trusted) ...[
                OutlinedButton(
                  onPressed: _probeLanDevices,
                  child: const Text('Check'),
                ),
                OutlinedButton(
                  onPressed: () => _unpairLan(name, revoke: true),
                  child: const Text('Revoke'),
                ),
              ],
              if (lookup?.peer != null)
                OutlinedButton(
                  onPressed: () => _unpairLan(name, revoke: false),
                  child: const Text('Remove pairing'),
                ),
            ],
          ),
        ],
      ],
    );
  }

  /// One LAN pairing: the BSAT device, its key fingerprint, its state and
  /// Check / Pair again / Revoke / Remove. Shown on both phones.
  Widget _buildLanPairingCard(LanPeer peer) {
    final name = peer.deviceName;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.1)),
      ),
      child: Column(
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
          _buildLanStatus(name, _lanPeers[name]),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              if (peer.isTrusted)
                OutlinedButton(
                  onPressed: _probeLanDevices,
                  child: const Text('Check'),
                ),
              OutlinedButton(
                onPressed: () => _openLanPairing(name),
                child: const Text('Pair again'),
              ),
              if (peer.isTrusted)
                OutlinedButton(
                  onPressed: () => _unpairLan(name, revoke: true),
                  child: const Text('Revoke'),
                ),
              OutlinedButton(
                onPressed: () => _unpairLan(name, revoke: false),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanStatus(String name, LanPeerLookup? lookup) {
    final (IconData icon, Color color, String text) = switch (lookup?.state) {
      LanPeerLookupState.trusted => switch (_lanReachability[name]) {
          null => (
              Icons.sync_rounded,
              Colors.grey,
              'Paired · checking the local network…'
            ),
          LanReachability.reachable => (
              Icons.check_circle_rounded,
              Colors.green,
              'Paired and authenticated · reachable on this network'
            ),
          LanReachability.authenticationFailed => (
              Icons.gpp_bad_rounded,
              Colors.redAccent,
              'Paired, but authentication failed · pair again'
            ),
          LanReachability.notConfigured => (
              Icons.error_outline_rounded,
              Colors.redAccent,
              'LAN is not running on this phone · reopen the app'
            ),
          _ => (
              Icons.wifi_off_rounded,
              Colors.orange,
              'Paired · not reachable now (other network, or BSAT closed on '
                  '$name). Jobs wait for retry; they are never sent online.'
            ),
        },
      LanPeerLookupState.revoked => (
          Icons.block_rounded,
          Colors.redAccent,
          'Pairing revoked · pair again to use LAN'
        ),
      LanPeerLookupState.unavailable => (
          Icons.error_outline_rounded,
          Colors.redAccent,
          'Pairing record unreadable · remove it and pair again'
        ),
      _ => (
          Icons.link_off_rounded,
          Colors.orange,
          'Not paired · $name gets no new jobs until it is paired'
        ),
    };
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(fontSize: 12, color: color)),
        ),
      ],
    );
  }

  Widget _buildAmountTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "KES $text",
        style: const TextStyle(
            color: kPrimaryColor, fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildIconButton(IconData icon, Color color, VoidCallback onPressed) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.all(8.0),
          child: Icon(icon, size: 20, color: color),
        ),
      ),
    );
  }

  Widget _buildAddButton(VoidCallback onTap) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(15),
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: kPrimaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(15),
            ),
            child:
                const Icon(Icons.add_rounded, color: kPrimaryColor, size: 30),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String message, IconData icon) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(icon, color: Colors.grey.withValues(alpha: 0.3), size: 40),
            const SizedBox(height: 8),
            Text(message,
                style: const TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildModernPendingItem(Map<String, dynamic> pairing) {
    final status = pairing['status'] ?? 'Pending';
    final requesterName = pairing['requester_name'] ?? 'Unknown';
    final targetName = pairing['recipient_name'] ?? 'Unknown';
    final isSentByMe = requesterName == myDeviceName;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(
            isSentByMe ? Icons.outbox_rounded : Icons.move_to_inbox_rounded,
            color: kPrimaryColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSentByMe ? "To: $targetName" : "From: $requesterName",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Status: $status",
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
          Row(
            children: [
              if (!isSentByMe)
                _buildIconButton(Icons.check_rounded, Colors.green, () {
                  _respondToPairing(pairing['id'].toString(), true);
                }),
              const SizedBox(width: 8),
              _buildIconButton(Icons.close_rounded, Colors.redAccent, () {
                _respondToPairing(pairing['id'].toString(), false);
              }),
            ],
          ),
        ],
      ),
    );
  }

  // Navigation Wrappers for cleaner code
  void _navigateToPairPage() async {
    await Navigator.of(context)
        .push(CupertinoPageRoute(builder: (_) => const PairDevicePage()));
    getData();
  }

  void _navigateToEditForwarder() async {
    await Navigator.of(context)
        .push(CupertinoPageRoute(builder: (_) => const EditForwarder()));
    getData();
  }
}
