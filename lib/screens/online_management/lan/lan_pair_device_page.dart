import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_local_identity.dart';
import 'package:bsat/services/lan/lan_pairing_candidates.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'lan_pairing_page.dart';

/// "Pair device over LAN": the LAN counterpart of "Pair New Device".
///
/// Open it on BOTH phones and choose the other phone. Then one phone shows
/// its pairing QR and the other scans it; either phone may take either side,
/// whichever forwards to the other. Both phones then compare the same
/// 6-digit code and confirm.
///
/// The other phone is either a BSAT device this phone already knows (its
/// Online paired devices and forwarding rules) or one typed by name, for
/// phones without an Online account. Choosing or typing a name trusts
/// nothing: the other phone must present that name inside the authenticated
/// pairing session, and both users must confirm the same code, before
/// anything is saved.
class LanPairDevicePage extends StatefulWidget {
  /// Device to preselect (for example from a forwarding rule).
  final String? initialDeviceName;

  const LanPairDevicePage({super.key, this.initialDeviceName});

  @override
  State<LanPairDevicePage> createState() => _LanPairDevicePageState();
}

class _LanPairDevicePageState extends State<LanPairDevicePage> {
  List<Map<String, String>> _devices = [];
  Map<String, String>? _selected;
  bool _loading = true;

  /// The other phone's name typed by the user (a LAN-only device).
  final _manualController = TextEditingController();

  /// This phone's name as the other phone will see it.
  String _ownName = '';

  @override
  void initState() {
    super.initState();
    _manualController.addListener(_manualChanged);
    _load();
  }

  @override
  void dispose() {
    _manualController.dispose();
    super.dispose();
  }

  /// Typing a name replaces the chosen known device.
  void _manualChanged() {
    if (!mounted) return;
    setState(() {
      if (_manualController.text.trim().isNotEmpty) _selected = null;
    });
  }

  /// The device to pair with: the chosen known device, else the typed name.
  Map<String, String>? get _target {
    if (_selected != null) return _selected;
    final typed = _manualController.text.trim();
    if (typed.isEmpty || lanDeviceNameProblem(typed) != null) return null;
    return {'device_name': typed, 'device_id': ''};
  }

  /// Known BSAT devices: paired (whitelisted) devices and forwarding rule
  /// targets, read from this phone's database only (no network).
  Future<void> _load() async {
    final devices = [
      for (final candidate in await loadLanPairingCandidates())
        {
          'device_name': candidate.deviceName,
          'device_id': candidate.deviceId,
        },
    ];
    final ownName = (await forwardingDeviceName() ?? '').trim();
    if (!mounted) return;
    setState(() {
      _devices = devices;
      _ownName = ownName;
      _selected = devices
          .where((d) => d['device_name'] == widget.initialDeviceName)
          .firstOrNull;
      _loading = false;
    });
    // A LAN-only device (for "Pair again") is not a known device: it is
    // prefilled by name instead.
    final initial = widget.initialDeviceName?.trim() ?? '';
    if (_selected == null && initial.isNotEmpty) {
      _manualController.text = initial;
    }
  }

  void _explain(String title, String message) => showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  Future<void> _start(LanPairingRole role) async {
    final device = _target;
    if (device == null) return;
    if (_ownName.isEmpty) {
      _explain(
          'Name this phone first',
          "Set this phone's LAN name in Forward SMS → LAN before pairing, "
              'so the other phone can recognise it.');
      return;
    }
    if (device['device_name'] == _ownName) {
      _explain('Choose the other phone',
          '"$_ownName" is this phone. Enter the name the other phone shows.');
      return;
    }
    if (LanForwardingService.instance == null) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('LAN unavailable'),
          content: const Text(
              'LAN forwarding is not available on this phone right now. '
              'Reopen BSAT and try again.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }
    final paired = await Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        builder: (_) => LanPairingPage(
          role: role,
          deviceName: device['device_name']!,
          deviceId: device['device_id']!,
        ),
      ),
    );
    if (paired == true && mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
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
              'Pair Device over LAN',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.all(kPagePadding),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _infoCard(),
                const SizedBox(height: kPagePadding * 2),
                _label('1. TARGET DEVICE'),
                const SizedBox(height: kPagePadding),
                Text(
                  _ownName.isEmpty
                      ? 'This phone has no name yet: set it in Forward SMS → '
                          'LAN first.'
                      : 'This phone appears to the other phone as "$_ownName".',
                  style: TextStyle(
                    fontSize: 12,
                    color: _ownName.isEmpty ? Colors.orange : Colors.grey,
                  ),
                ),
                const SizedBox(height: kPagePadding),
                _deviceList(),
                const SizedBox(height: kPagePadding / 2),
                TextField(
                  key: const Key('lanPairManualName'),
                  controller: _manualController,
                  maxLength: lanDeviceNameMaxChars,
                  decoration: InputDecoration(
                    labelText: _devices.isEmpty
                        ? "Other phone's LAN name"
                        : "Or type the other phone's LAN name",
                    helperText: 'Exactly as shown on the other phone under '
                        'Forward SMS → LAN → This Phone.',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: kPagePadding * 2),
                _label('2. ONE PHONE SHOWS, THE OTHER SCANS'),
                const SizedBox(height: kPagePadding),
                _actionButton(
                  icon: Icons.qr_code_2_rounded,
                  title: 'Show my pairing QR',
                  subtitle: 'The other phone scans this phone',
                  onTap: () => _start(LanPairingRole.invite),
                ),
                const SizedBox(height: kPagePadding),
                _actionButton(
                  icon: Icons.qr_code_scanner_rounded,
                  title: 'Scan the other phone\'s QR',
                  subtitle: 'Opens the camera (or type the code)',
                  onTap: () => _start(LanPairingRole.join),
                ),
                const SizedBox(height: kPagePadding * 2),
                Text(
                  'Both phones must be on the same Wi-Fi or hotspot. After '
                  'the scan, both phones show the same 6-digit code: compare '
                  'them and tap "Codes match: trust" on both. Nothing is '
                  'saved until both phones confirm.',
                  style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard() => Container(
        padding: const EdgeInsets.all(kPagePadding),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kPrimaryColor, kPrimaryColor.withValues(alpha: 0.7)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: const Row(
          children: [
            Icon(Icons.wifi_rounded, color: Colors.white, size: 32),
            SizedBox(width: 12),
            Expanded(
              child: Text(
                'Open this page on both phones and choose each other. One '
                'phone shows its QR code, the other scans it.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
          ],
        ),
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          letterSpacing: 1.2,
          color: kPrimaryColor,
        ),
      );

  Widget _deviceList() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_devices.isEmpty) {
      return const Text(
        lanNoPairingCandidatesHelp,
        style: TextStyle(color: Colors.grey),
      );
    }
    return Column(
      children: [
        for (final device in _devices)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(kBorderRadius),
              border: Border.all(
                color: identical(device, _selected)
                    ? kPrimaryColor
                    : Colors.grey.withValues(alpha: 0.15),
                width: identical(device, _selected) ? 2 : 1,
              ),
            ),
            child: ListTile(
              leading: Icon(
                identical(device, _selected)
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: kPrimaryColor,
              ),
              title: Text(device['device_name']!,
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              onTap: () {
                _manualController.clear();
                setState(() => _selected = device);
              },
            ),
          ),
      ],
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final enabled = _target != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
        color: kPrimaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(kBorderRadius),
        child: InkWell(
          borderRadius: BorderRadius.circular(kBorderRadius),
          onTap: enabled ? onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: kPrimaryColor, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(subtitle,
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey)),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_right, size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
