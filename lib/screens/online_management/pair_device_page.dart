import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/online_management/search_device.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
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
  String _myDeviceId = "Loading...";
  bool _isLoading = false;
  List<dynamic> _pendingPairings = [];
  List<dynamic> _pairedDevices = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initData();
    });
  }

  Future<void> _initData() async {
    await _loadMyDeviceId();
    await _loadPendingPairings();
  }

  Future<void> _loadPendingPairings() async {
    if (_myDeviceId == "Loading..." || _myDeviceId == "Unknown") return;

    showLoadingDialog(  context, text: "Loading pending pairings...");

    try {
      final backendService = BackendService();
      final response = await backendService
          .get('/api/device/pending-pairings?myDeviceId=$_myDeviceId');
      if (response['success'] && mounted) {
        setState(() {
          _pendingPairings = response['data']['requests'] ?? [];
        });
        print("Pending Pairings: ${response['data']['requests']}");
      }
    } catch (e) {
      debugPrint("Error loading pending pairings: $e");
    }

      Navigator.of(context).pop(); // Hide loading
  }

  Future<void> _loadMyDeviceId() async {
    String? id = await AuthService().getDeviceId();
    if (mounted) {
      setState(() {
        _myDeviceId = id ?? "Unknown";
      });
    }
  }

  Future<void> _handleSearch(String query) async {
    final result = await Navigator.push(
      context,
      CupertinoPageRoute(builder: (context) => SearchDevicePage(query: query)),
    );

    if (result != null && result is Map) {
      // Assuming the device object has a 'device_id' or 'id' field
      String? targetId = result['device_id'] ?? result['id'];
      if (targetId != null) {
        setState(() {
          _targetDeviceController.text = targetId;
        });
      } else {
        if (mounted) {
          showErrorDialog(
              context, "Error", "Selected device does not have a valid ID.");
        }
      }
    }
  }

  Future<void> _pairDevices() async {
    if (_targetDeviceController.text.isEmpty) {
      showErrorDialog(
          context, "Error", "Please enter or select a target device ID.");
      return;
    }

    if (_myDeviceId == "Loading..." || _myDeviceId == "Unknown") {
      showErrorDialog(context, "Error", "Could not determine your device ID.");
      return;
    }

    showLoadingDialog(context, text: "Pairing...");

    try {
      final backendService = BackendService();
      // Using a likely endpoint. Update if the server expects a different one.
      final response =
          await backendService.post('/api/devices/request-pairing', body: {
        'myDeviceId': _myDeviceId,
        'targetDeviceId': _targetDeviceController.text,
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

          print("Pairing Error: $errorMessage");
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
          .get('/api/devices/paired-devices?myDeviceId=$_myDeviceId');
      if (response['success'] && mounted) {
        _pairedDevices = response['data']['pairedDevices'] ?? [];
        print("Paired Devices: $_pairedDevices");
        // You can set this to state and display in the UI if needed
        setState(() {});
      }
    } catch (e) {
      debugPrint("Error loading paired devices: $e");
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: kBgColor,
      body: SafeArea(
        child: Column(
          children: [
            header(context, "Pair Device"),
            Expanded(
              child: SingleChildScrollView(
                padding: kPagePaddingInsets,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // const SizedBox(height: 24),
                    const Text(
                      "Target Device ID/Email",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: kPagePadding),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _targetDeviceController,
                            onSubmitted: _handleSearch,
                            decoration: InputDecoration(
                              hintText: "Enter Target Device ID/email",
                              filled: true,
                              // fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                                borderSide: BorderSide.none,
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        ElevatedButton(
                          onPressed: () =>
                              _handleSearch(_targetDeviceController.text),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            // foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                            shadowColor: Colors.transparent,
                            elevation: 0,
                            padding: const EdgeInsets.all(14),
                          ),
                          child: const Icon(Icons.search),
                        ),
                      ],
                    ),
                    const SizedBox(height: kPagePadding * 2),
                    ElevatedButton(
                      onPressed: _pairDevices,
                      style: ElevatedButton.styleFrom(
                        // backgroundColor: kPrimaryColor,
                        // foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        elevation: 2,
                      ),
                      child: const Text(
                        "PAIR DEVICES",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    const SizedBox(height: kPagePadding * 3),
                    const Text(
                      "Connection Requests",
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: kPagePadding / 2),
                    if (_pendingPairings.isEmpty)
                      const Padding(
                        padding: EdgeInsets.all(8.0),
                        child: Text("No pending pairings found.",
                            style: TextStyle(color: Colors.grey)),
                      )
                    else
                      ..._pendingPairings.map((pairing) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(kBorderRadius),
                            border:
                                Border.all(color: Colors.grey.withOpacity(0.2)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.phonelink_setup, color: Colors.orange),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                        "Req from: ${pairing['requester_name'] ?? 'Unknown'}",
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold)),
                                    Text(
                                        "ID: ${pairing['requester_device_id'] ?? ''}",
                                        style: TextStyle(
                                            fontSize: 12, color: Colors.grey)),
                                    Text(
                                        "Status: ${pairing['status'] ?? 'Pending'}",
                                        style: TextStyle(fontSize: 12)),
                                  ],
                                ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.check,
                                        color: Colors.green),
                                    onPressed: () => _respondToPairing(
                                        pairing['id'].toString(), true),
                                    tooltip: "Accept",
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    onPressed: () => _respondToPairing(
                                        pairing['id'].toString(), false),
                                    tooltip: "Reject",
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    //   Container(
                    //   padding: const EdgeInsets.all(16),
                    //   decoration: BoxDecoration(
                    //     // color: Colors.white,
                    //     color: Theme.of(context).cardColor,
                    //     borderRadius: BorderRadius.circular(kBorderRadius),
                    //     border: Border(
                    //       bottom: BorderSide(
                    //         // color: Theme.of(context).hintColor,
                    //         color: Colors.black.withOpacity(0.9),
                    //         width: 4,
                    //       ),
                    //       right: BorderSide(
                    //         // color: Theme.of(context).hintColor,
                    //         color: Colors.black.withOpacity(0.9),
                    //         width: 4,
                    //       ),
                    //     ),
                    //   ),
                    //   child: Column(
                    //     crossAxisAlignment: CrossAxisAlignment.start,
                    //     children: [
                    //       const Text(
                    //         "My Device ID",
                    //         style: TextStyle(
                    //           fontSize: 14,
                    //           // color: Colors.grey,
                    //         ),
                    //       ),
                    //       const SizedBox(height: 8),
                    //       Row(
                    //         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    //         children: [
                    //           Row(
                    //             children: [
                    //               Icon(Icons.perm_device_information,
                    //                   color: kPrimaryColor),
                    //               const SizedBox(width: 10),
                    //               Text(
                    //                 _myDeviceId,
                    //                 style: const TextStyle(
                    //                   fontSize: 16,
                    //                   fontWeight: FontWeight.bold,
                    //                 ),
                    //               ),
                    //             ],
                    //           ),
                    //           IconButton(
                    //             onPressed: () {
                    //               // copy to clipboard
                    //               Clipboard.setData(
                    //                   ClipboardData(text: _myDeviceId));
                    //               ScaffoldMessenger.of(context).showSnackBar(
                    //                 const SnackBar(
                    //                   content:
                    //                       Text("Device ID copied to clipboard"),
                    //                 ),
                    //               );
                    //             },
                    //             icon: Icon(CupertinoIcons.doc_on_doc),
                    //           )
                    //         ],
                    //       ),
                    //     ],
                    //   ),
                    // ),
                    const SizedBox(height: kPagePadding * 2),
                    const Text(
                      "Paired devices",
                      style: TextStyle(
                        // fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
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
