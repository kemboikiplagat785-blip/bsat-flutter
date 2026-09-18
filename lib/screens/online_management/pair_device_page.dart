import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/search_device.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PairDevicePage extends StatefulWidget {
  const PairDevicePage({super.key});

  @override
  State<PairDevicePage> createState() => _PairDevicePageState();
}

class _PairDevicePageState extends State<PairDevicePage> {
  final TextEditingController _targetDeviceController = TextEditingController();
  // String _myDeviceId = "Loading...";
  String myDeviceName = "Loading...";

  // bool _isLoading = false;
  List<dynamic> _pairedDevices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData();
    });
  }

  Future<void> _initData() async {
    myDeviceName =
        await SharedPreferencesService().getDeviceName() ?? "Unknown";
    setState(() {});
    // await _loadPendingPairings();
  }

  Future<void> _handleSearch(String query) async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => SearchDevicePage(query: query)),
    );

    if (result != null && result is Map) {
      // Assuming the device object has a 'device_name' or 'name' field
      String? targetName = result['device_name'];
      if (targetName != null) {
        setState(() {
          _targetDeviceController.text = targetName;
        });
      } else {
        if (mounted) {
          showErrorDialog(
              context, "Error", "Selected device does not have a valid name.");
        }
      }
    }
  }

  Future<void> _pairDevices() async {
    if (_targetDeviceController.text.isEmpty) {
      showErrorDialog(
          context, "Error", "Please enter or select a target device name.");
      return;
    }

    if (myDeviceName == "Loading..." || myDeviceName == "Unknown") {
      showErrorDialog(
          context, "Error", "Could not determine your device name.");
      return;
    }

    showLoadingDialog(context, text: "Pairing...");

    try {
      final backendService = BackendService();
      // Using a likely endpoint. Update if the server expects a different one.
      final response =
          await backendService.post('/api/devices/request-pairing', body: {
        'myDeviceName': myDeviceName,
        'targetDeviceName': _targetDeviceController.text,
      });

      // Hide loading dialog
      if (mounted) Navigator.pop(context);

      if (response['success']) {
        if (mounted) {
          await showSuccessDialog(context, text: "Pairing request sent!");
          Navigator.of(context).pop();
        }
      } else {
        if (mounted) {
          String errorMessage =
              response['message'] ?? "Failed to pair devices.";

          if (response['error'] != null && response['error'] is Map) {
            errorMessage = response['error']['error'] ??
                response['error']['message'] ??
                errorMessage;
          }

          showErrorDialog(context, "Error", errorMessage);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Hide loading
        showErrorDialog(context, "Error", "An error occurred: $e");
      }
    }
  }

  Future<void> getPairedDevices() async {
    try {
      final backendService = BackendService();
      final response = await backendService
          .get('/api/devices/paired-devices?myDeviceName=$myDeviceName');
      if (response['success'] && mounted) {
        _pairedDevices = response['data']['pairedDevices'] ?? [];
        // You can set this to state and display in the UI if needed
        setState(() {});
      }
    } catch (e) {
      debugPrint("Error loading paired devices: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: CustomScrollView(
        slivers: [
          // Elegant Header
          SliverAppBar(
            pinned: true,
            leading: IconButton(
              icon: const Icon(CupertinoIcons.back),
              onPressed: () => Navigator.pop(context),
            ),
            backgroundColor: theme.colorScheme.surface,
            elevation: 0,
            title: const Text(
              "Pair New Device",
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
          ),

          SliverPadding(
            padding: const EdgeInsets.all(kPagePadding),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _buildInfoCard(theme),
                const SizedBox(height: kPagePadding * 2),

                // Input Section
                _buildSectionLabel("TARGET DEVICE"),
                const SizedBox(height: kPagePadding),
                _buildModernInputField(theme),

                const SizedBox(height: kPagePadding * 2),

                // Action Button
                _buildPairButton(theme),

                const SizedBox(height: kPagePadding * 2),
                _buildSecurityNote(theme),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(kPagePadding),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kPrimaryColor, kPrimaryColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(kBorderRadius),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Your Identity",
            style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            myDeviceName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w900,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(kBorderRadius),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_outlined,
                    color: Colors.white, size: 14),
                SizedBox(width: 6),
                Text("Broadcast Active",
                    style: TextStyle(color: Colors.white, fontSize: 11)),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.5,
        color: Colors.grey,
      ),
    );
  }

  Widget _buildModernInputField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _targetDeviceController,
        style: const TextStyle(fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: "Enter device name...",
          hintStyle: TextStyle(color: theme.hintColor.withValues(alpha: 0.4)),
          prefixIcon:
              const Icon(CupertinoIcons.device_phone_portrait, size: 20),
          suffixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: kPrimaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              icon: const Icon(Icons.search_rounded,
                  color: kPrimaryColor, size: 20),
              onPressed: () => _handleSearch(_targetDeviceController.text),
            ),
          ),
          border: InputBorder.none,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        ),
      ),
    );
  }

  Widget _buildPairButton(ThemeData theme) {
    return Container(
      width: double.infinity,
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: kPrimaryColor.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: _pairDevices,
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          elevation: 0,
        ),
        child: const Text(
          "Send Pairing Request",
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
      ),
    );
  }

  Widget _buildSecurityNote(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              "Make sure the target device is online and discoverable to receive the request.",
              style: TextStyle(color: theme.hintColor, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
