import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/pair_device_page.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class ShareContactsPage extends StatefulWidget {
  const ShareContactsPage({super.key});

  @override
  State<ShareContactsPage> createState() => _ShareContactsPageState();
}

class _ShareContactsPageState extends State<ShareContactsPage> {
  final BackendService _backendService = BackendService();

  List<Map<String, dynamic>> _pairedDevices = [];
  String? _selectedDeviceName;
  bool _isLoadingDevices = true;
  bool _isSending = false;

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
        final devices = data?['devices'] ?? [];
        final list = List<Map<String, dynamic>>.from(devices);

        // Keep local cache in sync, like the other device pages do
        await SQLiteService().clearTable('whitelistedDevices');
        for (final device in list) {
          await SQLiteService().insertStuff(device, 'whitelistedDevices');
        }

        if (!mounted) return;
        setState(() {
          _pairedDevices = list;
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
    } catch (e) {
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

  Future<void> _sendContacts() async {
    if (_selectedDeviceName == null || _selectedDeviceName!.isEmpty) {
      showErrorDialog(context, "Error", "Please select a paired device first.");
      return;
    }

    if (_isSending) return;

    setState(() {
      _isSending = true;
    });

    showLoadingDialog(context, text: "Preparing and sending contacts...");

    try {
      final transferId =
          await ContactsService().startContactsTransfer(_selectedDeviceName!);

      if (!mounted) return;
      Navigator.of(context).pop(); // close loading dialog

      if (transferId != null) {
        await showSuccessDialog(
          context,
          text:
              "Contacts transfer started successfully.\nTransfer ID: $transferId",
        );
      } else {
        showErrorDialog(
          context,
          "Error",
          "Failed to start the contact transfer.",
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop(); // close loading dialog
        showErrorDialog(context, "Error", "Failed to send contacts: $e");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
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
            header(context, "Share Contacts"),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadPairedDevices,
                child: ListView(
                  padding: const EdgeInsets.all(kPagePadding),
                  children: [
                    Text(
                      "Send your phone contacts to another BSAT phone that is already paired with this device.",
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
                            "Step 1",
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            "If the target phone is not paired yet, request pairing first.",
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _openPairingFlow,
                            icon: const Icon(CupertinoIcons.link),
                            label: const Text("Pair a new device"),
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
                          "Accepted devices",
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          onPressed: _loadPairedDevices,
                          icon: const Icon(CupertinoIcons.refresh),
                          label: const Text("Refresh"),
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
                              "No accepted paired devices found.",
                              style: TextStyle(color: Colors.grey[600]),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Pair first, then come back here to share contacts.",
                              style: TextStyle(color: Colors.grey[500]),
                            ),
                          ],
                        ),
                      )
                    else
                      ..._pairedDevices.map(_buildPairedDeviceTile),
                    const SizedBox(height: kPagePadding),
                    ElevatedButton(
                      onPressed: _isSending ? null : _sendContacts,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                      ),
                      child: _isSending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text("Send contacts"),
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
