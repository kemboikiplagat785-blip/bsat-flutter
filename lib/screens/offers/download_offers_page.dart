import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/offers_transfer_service.dart';
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadPairedDevices();
    });
  }

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
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
