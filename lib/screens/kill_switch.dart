import 'package:bsat/screens/home/dashboard/dashboard.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/kill_switch_service.dart';


class KillswitchScreen extends StatelessWidget {
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

  Future<void> _launchStore() async {
    if (config.updateUrl.isEmpty) return;
    
    final url = Uri.parse(config.updateUrl);
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    bool isOfflineLockout = config.enforcement == KillswitchEnforcement.offlineLockout;

    return PopScope(
      canPop: false,
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
                      : (isDismissible ? Icons.update_rounded : Icons.warning_rounded),
                  size: 80,
                  color: isOfflineLockout 
                      ? Colors.grey 
                      : (isDismissible ? Colors.orange : Colors.redAccent),
                ),
                const SizedBox(height: 24),
                Text(
                  isOfflineLockout 
                      ? "Network Required" 
                      : (isDismissible ? "Update Recommended" : "Update Required"),
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                if (isDismissible && !isOfflineLockout)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                          config.daysRemaining > 0 
                              ? "${config.daysRemaining} days remaining" 
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
                  config.message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 40),
                
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isOfflineLockout ? onRetry : _launchStore,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isOfflineLockout ? Colors.grey.shade800 : Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(
                      isOfflineLockout ? "Retry Connection" : "Update Now", 
                      style: const TextStyle(fontSize: 18)
                    ),
                  ),
                ),
                
                if (isDismissible && !isOfflineLockout && onSkip != null) ...[
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: onSkip,
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
