import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:bsat/components/header.dart'; // Assuming header is here based on standard
import 'package:bsat/utils/constants.dart'; // Assuming constants are here

class ApkDownloaderPage extends StatefulWidget {
  const ApkDownloaderPage({Key? key}) : super(key: key);

  @override
  State<ApkDownloaderPage> createState() => _ApkDownloaderPageState();
}

class _ApkDownloaderPageState extends State<ApkDownloaderPage> {
  int _received = 0;
  int _total = -1;
  bool _isDownloading = false;
  bool _isDownloaded = false;
  String _savePath = "";

  bool _isLoadingConfig = true;
  String? _latestVersion;
  String? _killMessage;
  String? _iosStoreUrl;

  @override
  void initState() {
    super.initState();
    _fetchAppConfig();
  }

  Future<void> _fetchAppConfig() async {
    try {
      Dio dio = Dio();
      final response =
          await dio.get('https://api.bsat.co.ke/api/devices/app-config');
      final data = response.data;
      if (mounted) {
        setState(() {
          _latestVersion = data['latest_version'];
          _killMessage = data['kill_message'];
          _iosStoreUrl = data['ios_store_url'];
          _isLoadingConfig = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingConfig = false;
          _killMessage =
              "Could not load update information. Please try again later.";
        });
      }
    }
  }

  Future<void> _downloadAndInstall() async {
    // This feature is only for Android. Prevent iOS from crashing.
    if (!Platform.isAndroid) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('In-app updates are only supported on Android.')),
      );
      return;
    }

    setState(() {
      _isDownloading = true;
      _received = 0;
      _total = -1;
      _isDownloaded = false;
    });

    try {
      // 1. Get the architecture
      String archType = "arm64-v8a";
      try {
        DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        AndroidDeviceInfo androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.supportedAbis.isNotEmpty) {
          archType = androidInfo.supportedAbis[0];
        }
      } catch (e) {
        debugPrint("Error getting device info: $e");
      }

      // Map Android specific ABIs to standard server values if necessary
      if (archType.contains("arm64")) archType = "arm64";
      if (archType.contains("armeabi")) archType = "armeabi-v7a";

      final String apkUrl =
          "https://api.bsat.co.ke/api/general/download-app?arch_type=$archType";

      // 2. Get the temporary directory of the device
      Directory tempDir = await getTemporaryDirectory();
      _savePath = '${tempDir.path}/update.apk';

      // print("Downloading APK to: $_savePath from $apkUrl");

      // 3. Download the APK using Dio
      Dio dio = Dio();
      await dio.download(
        apkUrl,
        _savePath,
        onReceiveProgress: (received, total) {
          setState(() {
            _received = received;
            _total = total;
          });
        },
      );

      // 4. Update UI state once downloaded
      setState(() {
        _isDownloading = false;
        _isDownloaded = true;
      });

      // 5. Automatically trigger the installation
      _installApk();
    } catch (e) {
      setState(() {
        _isDownloading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error downloading APK: $e')),
      );
    }
  }

  Future<void> _installApk() async {
    if (_savePath.isEmpty) return;

    // OpenFilex automatically uses the correct Android Intent based on the .apk extension
    final result = await OpenFilex.open(_savePath);

    if (result.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Could not open the installer: ${result.message}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    double receivedMB = _received / (1024 * 1024);
    double totalMB = _total != -1 ? _total / (1024 * 1024) : 0;

    // Attempting to calculate percentage if total is known
    double progressValue =
        _total != -1 && _total > 0 ? _received / _total : 0.0;

    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, 'App Update'),
            Padding(
              padding: const EdgeInsets.all(kPagePadding),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                ),
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.system_update,
                        size: 80, color: Theme.of(context).primaryColor),
                    const SizedBox(height: 24),

                    if (_isLoadingConfig)
                      const CircularProgressIndicator()
                    else ...[
                      Text(
                        _latestVersion != null
                            ? "Version $_latestVersion is available!"
                            : "A new version of the app is available",
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.bold),
                        textAlign: TextAlign.center,
                      ),
                      if (_killMessage != null) ...[
                        const SizedBox(height: 16),
                        Text(
                          _killMessage!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ],
                    const SizedBox(height: 32),

                    // Progress Bar
                    if (_isDownloading) ...[
                      if (_total != -1)
                        LinearProgressIndicator(value: progressValue)
                      else
                        const LinearProgressIndicator(),
                      const SizedBox(height: 12),
                      if (_total != -1)
                        Text(
                            "${receivedMB.toStringAsFixed(2)} MB / ${totalMB.toStringAsFixed(2)} MB (${(progressValue * 100).toStringAsFixed(1)}%)")
                      else
                        Text("${receivedMB.toStringAsFixed(2)} MB Downloaded"),
                    ],

                    const SizedBox(height: 32),

                    // Action Buttons
                    if (!_isDownloading)
                      ElevatedButton.icon(
                        onPressed:
                            _isDownloaded ? _installApk : _downloadAndInstall,
                        icon: Icon(_isDownloaded
                            ? Icons.install_mobile
                            : Icons.download),
                        label: Text(
                            _isDownloaded ? "Install Now" : "Download Update"),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(kBorderRadius),
                          ),
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
