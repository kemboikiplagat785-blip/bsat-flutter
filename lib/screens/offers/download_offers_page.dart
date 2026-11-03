import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/screens/online_management/lan/lan_management.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/lan/lan_forwarding_bootstrap.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_local_identity.dart';
import 'package:bsat/services/lan/lan_offers_transfer.dart';
import 'package:bsat/services/lan/lan_peer_store.dart';
import 'package:bsat/services/offers_transfer_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class DownloadOffersPage extends StatefulWidget {
  const DownloadOffersPage({super.key});

  @override
  State<DownloadOffersPage> createState() => _DownloadOffersPageState();
}

class _DownloadOffersPageState extends State<DownloadOffersPage> {
  final BackendService _backendService = BackendService();
  final OffersTransferService _offersTransferService = OffersTransferService();

  List<Map<String, dynamic>> _pairedDevices = [];
  String? _selectedDeviceName;
  bool _isLoadingDevices = true;
  bool _isRequesting = false;

  bool _overLan = false;
  List<LanPeer> _lanPeers = [];
  String? _selectedLanDeviceName;
  bool _isLoadingLanPeers = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPairedDevices();
      _loadLanPeers();
    });
  }

  Future<void> _loadLanPeers() async {
    if (!mounted) return;
    setState(() => _isLoadingLanPeers = true);
    final peers = await LanPeerStore().all();
    if (!mounted) return;
    setState(() {
      _lanPeers = peers.where((peer) => peer.isTrusted).toList();
      if (!_lanPeers.any((p) => p.deviceName == _selectedLanDeviceName)) {
        _selectedLanDeviceName = null;
      }
      _isLoadingLanPeers = false;
    });
  }

  Future<void> _openLanPairing() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(builder: (context) => const LanManagementScreen()),
    );
    await _loadLanPeers();
  }

  Future<void> _downloadOverLan() async {
    final deviceName = _selectedLanDeviceName;
    if (deviceName == null) {
      showErrorDialog(context, 'Error', 'Please select a paired phone first.');
      return;
    }
    if (_isRequesting) return;

    if (!(await SharedPreferencesService().getDownloadOffers() ?? true)) {
      if (!mounted) return;
      showErrorDialog(
        context,
        'Error',
        'Turn on "Download offers" in Settings first.',
      );
      return;
    }
    final service = LanForwardingService.instance;
    if (service == null) {
      if (!mounted) return;
      showErrorDialog(context, 'Error', 'LAN is not available on this phone.');
      return;
    }
    if (!mounted) return;
    final confirmed = await showConfirmDeleteDialog(
      context,
      message: 'Replace all offers on this phone with the offers from '
          '$deviceName?',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRequesting = true);
    showLoadingDialog(context, text: 'Downloading offers...');
    try {
      await refreshLanForwarding();
      final imported = await downloadOffersOverLan(
        client: service,
        ownDeviceName: (await forwardingDeviceName() ?? '').trim(),
        deviceName: deviceName,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      await showSuccessDialog(
        context,
        text: 'Downloaded $imported offers from $deviceName.',
      );
    } on LanOffersDownloadException catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showErrorDialog(context, 'Error', error.message);
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      showErrorDialog(context, 'Error', 'Failed to download offers: $error');
    } finally {
      if (mounted) setState(() => _isRequesting = false);
    }
  }

  List<Widget> _buildLanSection() => [
        Text(
          'Download offers directly from a phone paired over LAN, on the same '
          'network. No internet is needed. BSAT must be open on that phone. '
          'Incoming offers replace local offers.',
          style: TextStyle(color: Colors.grey[600]),
        ),
        const SizedBox(height: kPagePadding),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LAN paired phones',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            TextButton.icon(
              onPressed: _openLanPairing,
              icon: const Icon(CupertinoIcons.link),
              label: const Text('Pair a phone'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingLanPeers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CupertinoActivityIndicator()),
          )
        else if (_lanPeers.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            alignment: Alignment.center,
            child: Text(
              'No phones paired over LAN yet.',
              style: TextStyle(color: Colors.grey[600]),
            ),
          )
        else
          ..._lanPeers.map(
            (peer) => RadioListTile<String>(
              value: peer.deviceName,
              groupValue: _selectedLanDeviceName,
              onChanged: (value) =>
                  setState(() => _selectedLanDeviceName = value),
              title: Text(
                peer.deviceName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(peer.displayId),
              secondary: const Icon(CupertinoIcons.wifi),
            ),
          ),
        const SizedBox(height: kPagePadding),
        ElevatedButton(
          onPressed: _isRequesting ? null : _downloadOverLan,
          style: ElevatedButton.styleFrom(
            backgroundColor: kPrimaryColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
          ),
          child: const Text('Download offers'),
        ),
        const SizedBox(height: kPagePadding * 2),
      ];

  Future<void> _loadPairedDevices() async {
    if (!mounted) return;

    setState(() {
      _isLoadingDevices = true;
    });

    try {
      final response = await _backendService.get('/api/device/whitelisted');

      if (response['success'] == true) {
        final data = response['data'];

        final refreshed =
            await SQLiteService().refreshWhitelistedDevices(data);
        if (refreshed == null) {
          throw StateError('Whitelisted device cache refresh was rejected');
        }

        if (!mounted) return;
        setState(() {
          _pairedDevices = refreshed;
          if (_selectedDeviceName != null &&
              !_pairedDevices.any(
                (d) => d['device_name']?.toString() == _selectedDeviceName,
              )) {
            _selectedDeviceName = null;
          }
        });
      } else {
        final cached = await SQLiteService().queryAll('whitelistedDevices');
        if (!mounted) return;
        setState(() {
          _pairedDevices = cached;
        });
      }
    } catch (_) {
      final cached = await SQLiteService().queryAll('whitelistedDevices');
      if (!mounted) return;
      setState(() {
        _pairedDevices = cached;
      });
    }

    if (!mounted) return;
    setState(() {
      _isLoadingDevices = false;
    });
  }

  Future<void> _openPairingFlow() async {
    await Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (context) => const PairDevicePage(),
      ),
    );

    await _loadPairedDevices();
  }

  Future<void> _requestOffers() async {
    if (_selectedDeviceName == null || _selectedDeviceName!.isEmpty) {
      showErrorDialog(context, 'Error', 'Please select a paired device first.');
      return;
    }

    if (_isRequesting) return;

    setState(() {
      _isRequesting = true;
    });

    showLoadingDialog(context, text: 'Requesting offers...');

    try {
      final response = await _offersTransferService.requestOffersFromDevice(
        _selectedDeviceName!,
      );

      if (!mounted) return;
      Navigator.of(context).pop();

      if (response['success'] == true) {
        await showSuccessDialog(
          context,
          text:
              'Request sent. Offers will download automatically when the paired phone responds.',
        );
      } else {
        showErrorDialog(
          context,
          'Error',
          response['message']?.toString() ??
              'Failed to send request to paired device.',
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        showErrorDialog(context, 'Error', 'Failed to request offers: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isRequesting = false;
        });
      }
    }
  }

  Widget _buildPairedDeviceTile(Map<String, dynamic> device) {
    final deviceName = device['device_name']?.toString() ?? 'Unknown Device';
    final ownerEmail = device['owner_email']?.toString() ?? '';
    final subtitle =
        ownerEmail.isNotEmpty ? ownerEmail : 'Accepted / whitelisted';

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBorderRadius),
        side: BorderSide(
          color: _selectedDeviceName == deviceName
              ? kPrimaryColor
              : Colors.grey.withValues(alpha: 0.2),
          width: _selectedDeviceName == deviceName ? 1.5 : 1,
        ),
      ),
      child: RadioListTile<String>(
        value: deviceName,
        groupValue: _selectedDeviceName,
        onChanged: (value) {
          setState(() {
            _selectedDeviceName = value;
          });
        },
        title: Text(
          deviceName,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(subtitle),
        secondary: Icon(
          _selectedDeviceName == deviceName
              ? CupertinoIcons.check_mark_circled_solid
              : CupertinoIcons.device_phone_portrait,
          color: _selectedDeviceName == deviceName ? kPrimaryColor : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            header(context, 'Download Offers'),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPairedDevices,
                child: ListView(
                  padding: const EdgeInsets.all(kPagePadding),
                  children: [
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(value: false, label: Text('Online')),
                        ButtonSegment(value: true, label: Text('LAN')),
                      ],
                      selected: {_overLan},
                      onSelectionChanged: (selection) =>
                          setState(() => _overLan = selection.first),
                    ),
                    const SizedBox(height: kPagePadding),
                    if (_overLan) ..._buildLanSection() else ...[
                    Text(
                      'Request offer rules from another paired BSAT phone. Incoming offers replace local offers.',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: kPagePadding),
                    Container(
                      padding: const EdgeInsets.all(kPagePadding),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Step 1',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'If the source phone is not paired yet, pair it first.',
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _openPairingFlow,
                            icon: const Icon(CupertinoIcons.link),
                            label: const Text('Pair a new device'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimaryColor,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: kPagePadding * 1.5),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Accepted devices',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _loadPairedDevices,
                          icon: const Icon(CupertinoIcons.refresh),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_isLoadingDevices)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CupertinoActivityIndicator()),
                      )
                    else if (_pairedDevices.isEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        alignment: Alignment.center,
                        child: Column(
                          children: [
                            Icon(
                              CupertinoIcons.slash_circle,
                              color: Colors.grey[500],
                              size: 42,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No accepted paired devices found.',
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Pair first, then request offers from that device.',
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._pairedDevices.map(_buildPairedDeviceTile),
                    const SizedBox(height: kPagePadding),
                    ElevatedButton(
                      onPressed: _isRequesting ? null : _requestOffers,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                      ),
                      child: _isRequesting
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : const Text('Request offers'),
                    ),
                    const SizedBox(height: kPagePadding * 2),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
