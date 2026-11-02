import 'dart:async';

import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_pairing.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/material.dart';

import 'lan_qr_view.dart';
import 'lan_scan_page.dart';

enum LanPairingRole {
  /// This phone receives forwarded jobs from [deviceName]: it shows the
  /// invitation.
  invite,

  /// This phone forwards jobs to [deviceName]: it scans the invitation.
  join,
}

/// Pairs this phone with one BSAT device for LAN forwarding, using the
/// prototype's QR pairing: a one-time invitation, an authenticated
/// handshake, the same 6-digit code on both phones, and confirmation on
/// both. Trust is saved only when the other phone proves it is
/// [deviceName] and both users confirmed. Scanning trusts nothing by itself.
class LanPairingPage extends StatefulWidget {
  final LanPairingRole role;
  final String deviceName;
  final String deviceId;

  const LanPairingPage({
    super.key,
    required this.role,
    required this.deviceName,
    required this.deviceId,
  });

  @override
  State<LanPairingPage> createState() => _LanPairingPageState();
}

class _LanPairingPageState extends State<LanPairingPage> {
  final _codeController = TextEditingController();
  PairingInvitation? _invitation;
  String? _error;
  bool _busy = false;
  Timer? _ticker;

  LanForwardingService? get _service => LanForwardingService.instance;

  @override
  void initState() {
    super.initState();
    // Start clean: a pairing left from another screen (possibly with another
    // device) is never shown or confirmed here.
    _service?.abandonPairing();
    _service?.addListener(_changed);
    if (widget.role == LanPairingRole.invite) _createInvitation();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _codeController.dispose();
    final service = _service;
    service?.removeListener(_changed);
    // An invitation is valid only while it is shown, and a pairing only while
    // its codes are shown: leaving this screen cancels an unconfirmed one.
    service?.abandonPairing();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _createInvitation() async {
    final service = _service;
    if (service == null) {
      setState(() => _error = 'LAN forwarding is not available on this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _invitation = await service.createInvitation(
        expectedDeviceName: widget.deviceName,
        expectedDeviceId: widget.deviceId,
      );
    } catch (error) {
      _error = error is StateError ? error.message : '$error';
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _join(String code, {required bool scanned}) async {
    final service = _service;
    if (service == null) {
      setState(() => _error = 'LAN forwarding is not available on this device.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    await service.joinWithInvitation(
      code,
      expectedDeviceName: widget.deviceName,
      expectedDeviceId: widget.deviceId,
      scanned: scanned,
    );
    if (mounted) {
      setState(() {
        _busy = false;
        _error = service.pairingError;
      });
    }
  }

  Future<void> _scan() async {
    final text = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const ScanInvitationPage()),
    );
    if (text != null && mounted) await _join(text, scanned: true);
  }

  @override
  Widget build(BuildContext context) {
    final pairing = _service?.pairing;
    return Scaffold(
      appBar: AppBar(title: Text('LAN pairing: ${widget.deviceName}')),
      body: ListView(
        padding: const EdgeInsets.all(kPagePadding),
        children: [
          Text(
            widget.role == LanPairingRole.invite
                ? 'On ${widget.deviceName}: Forward SMS → LAN → Pair LAN '
                    'device → choose this phone → "Scan the other phone\'s '
                    'QR", and scan this code.'
                : 'On ${widget.deviceName}: Forward SMS → LAN → Pair LAN '
                    'device → choose this phone → "Show my pairing QR". Then '
                    'scan that QR code here.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: kPagePadding),
          const Text(
            'Both phones must be on the same Wi-Fi or hotspot. Pairing is '
            'complete only after you compare the 6-digit code on both phones '
            'and confirm on both.',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: kPagePadding),
          if (pairing != null)
            _confirmation(pairing)
          else if (widget.role == LanPairingRole.invite)
            _inviteBody()
          else
            _joinBody(),
          if (_error != null) ...[
            const SizedBox(height: kPagePadding),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }

  Widget _inviteBody() {
    final invitation = _invitation;
    final service = _service;
    if (_busy) return const Center(child: CircularProgressIndicator());
    if (invitation == null || service == null) {
      return FilledButton(
        onPressed: _createInvitation,
        child: const Text('Create invitation'),
      );
    }
    final expiresAt = service.invitations.expiresAt;
    final remaining = expiresAt?.difference(DateTime.now());
    final active = service.invitations.invitation != null;
    return Column(
      children: [
        if (active) Center(child: LanQrView(data: invitation.qrText)),
        const SizedBox(height: kPagePadding),
        SelectableText(
          active ? invitation.code : 'This invitation is no longer valid.',
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 16),
        ),
        const SizedBox(height: 8),
        Text(
          active && remaining != null
              ? 'Valid once, for ${remaining.inMinutes}:${(remaining.inSeconds % 60).toString().padLeft(2, '0')} more.'
              : 'Create a new invitation to pair.',
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        if (active)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              // Lets the user compare it with this phone's Wi-Fi IP address
              // (Settings → Wi-Fi) when the other phone cannot connect.
              'Address in this QR: ${invitation.host.address}:'
              '${invitation.port}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        if (!active)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FilledButton(
              onPressed: _createInvitation,
              child: const Text('New invitation'),
            ),
          ),
      ],
    );
  }

  Widget _joinBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: _busy ? null : _scan,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan pairing QR'),
        ),
        const SizedBox(height: kPagePadding),
        TextField(
          controller: _codeController,
          decoration: const InputDecoration(
            labelText: 'Or type the pairing code',
            border: OutlineInputBorder(),
          ),
          maxLength: 60,
        ),
        OutlinedButton(
          onPressed: _busy
              ? null
              : () => _join(_codeController.text, scanned: false),
          child: _busy
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Connect and verify'),
        ),
      ],
    );
  }

  Widget _confirmation(PairingSession pairing) {
    final peer = pairing.peerIdentity;
    final finished = pairing.isFinished;
    final String status = switch (pairing.phase) {
      PairingPhase.awaitingConfirmation => peer == null
          ? 'Checking the other phone\'s identity…'
          : 'Compare the code with the one on ${widget.deviceName}.',
      PairingPhase.waitingForPeer =>
        'Confirmed here. Waiting for ${widget.deviceName} to confirm…',
      PairingPhase.completed =>
        'Paired. ${widget.deviceName} is now trusted for LAN forwarding.',
      PairingPhase.rejectedLocally => 'Pairing rejected. Nothing was saved.',
      PairingPhase.rejectedByPeer =>
        '${widget.deviceName} rejected pairing. Nothing was saved.',
      PairingPhase.cancelled => 'Pairing cancelled. Nothing was saved.',
      PairingPhase.failed =>
        '${pairing.failure ?? 'Pairing failed.'} Nothing was saved.',
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kPrimaryColor.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(kBorderRadius),
        border: Border.all(color: kPrimaryColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            pairing.sas,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w800,
              letterSpacing: 6,
              color: kPrimaryColor,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Device key: ${pairing.session.peerFingerprint.substring(0, 16).toUpperCase()}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Text(status, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          if (!finished) ...[
            FilledButton(
              onPressed: pairing.peerAccepted &&
                      pairing.phase == PairingPhase.awaitingConfirmation
                  ? pairing.confirm
                  : null,
              child: const Text('Codes match: trust'),
            ),
            OutlinedButton(
              onPressed: pairing.reject,
              child: const Text('Codes differ: reject'),
            ),
          ] else
            FilledButton(
              onPressed: () => Navigator.of(context).pop(
                pairing.phase == PairingPhase.completed,
              ),
              child: const Text('Done'),
            ),
        ],
      ),
    );
  }
}
