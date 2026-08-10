import 'package:bsat/screens/home/dashboard/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:ota_update/ota_update.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/admin_management_service.dart';
import 'updater.dart';

class KillswitchScreen extends StatefulWidget {
  final KillswitchConfig config;
  final bool isDismissible;
  final VoidCallback? onRetry;
  final VoidCallback? onSkip;

  const KillswitchScreen({
    super.key,
    required this.config,
    required this.isDismissible,
    this.onRetry,
    this.onSkip,
  });

  @override
  State<KillswitchScreen> createState() => _KillswitchScreenState();
}

class _KillswitchScreenState extends State<KillswitchScreen> {
  OtaEvent? currentEvent;
  bool isDownloading = false;

  Future<void> _startInAppUpdate() async {
    if (widget.config.updateUrl.isEmpty) return;

    setState(() {
      isDownloading = true;
    });

    try {
      OtaUpdate()
          .execute(
        widget.config.updateUrl,
        destinationFilename: 'bsat-update.apk',
      )
          .listen(
        (OtaEvent event) {
          setState(() {
            currentEvent = event;
            if (event.status == OtaStatus.ALREADY_RUNNING_ERROR ||
                event.status == OtaStatus.PERMISSION_NOT_GRANTED_ERROR ||
                event.status == OtaStatus.INTERNAL_ERROR) {
              isDownloading = false;
            }
          });
        },
      );
    } catch (e) {
      // print('Failed to make OTA update. Details: $e');
      setState(() {
        isDownloading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isOfflineLockout =
        widget.config.enforcement == KillswitchEnforcement.offlineLockout;
    // bool canPop = widget.isDismissible || isOfflineLockout;

    return PopScope(
      canPop: widget.isDismissible,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  isOfflineLockout
                      ? Icons.wifi_off_rounded
                      : (widget.isDismissible
                          ? Icons.update_rounded
                          : Icons.warning_rounded),
                  size: 80,
                  color: isOfflineLockout
                      ? Colors.grey
                      : (widget.isDismissible
                          ? Colors.orange
                          : Colors.redAccent),
                ),
                const SizedBox(height: 24),
                Text(
                  isOfflineLockout
                      ? "Network Required"
                      : (widget.isDismissible
                          ? "Update Recommended"
                          : "Update Required"),
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                if (widget.isDismissible && !isOfflineLockout)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.withOpacity(0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.timer_outlined, color: Colors.orange),
                        const SizedBox(width: 8),
                        Text(
                          widget.config.daysRemaining > 0
                              ? "${widget.config.daysRemaining} days remaining"
                              : "Less than 24 hours left!",
                          style: const TextStyle(
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text(
                  widget.config.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 40),
                if (isDownloading) ...[
                  LinearProgressIndicator(
                    value: currentEvent?.value != null &&
                            double.tryParse(currentEvent!.value!) != null
                        ? double.parse(currentEvent!.value!) / 100
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    currentEvent?.status == OtaStatus.DOWNLOADING
                        ? 'Downloading: ${currentEvent?.value}%'
                        : currentEvent?.status == OtaStatus.INSTALLING
                            ? 'Installing...'
                            : (currentEvent?.value ?? 'Preparing...'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ] else
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton(
                      onPressed: isOfflineLockout
                          ? widget.onRetry
                          : () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => ApkDownloaderPage(),
                                ),
                              );
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isOfflineLockout
                            ? Colors.grey.shade800
                            : Colors.blue,
                        foregroundColor: Colors.white,
                      ),
                      child: Text(
                          isOfflineLockout ? "Retry Connection" : "Update Now",
                          style: const TextStyle(fontSize: 18)),
                    ),
                  ),
                if (widget.isDismissible &&
                    !isOfflineLockout &&
                    widget.onSkip != null) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text(
                      "Remind me later",
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
