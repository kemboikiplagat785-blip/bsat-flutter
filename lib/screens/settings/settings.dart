import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'dart:io';
import 'package:bsat/utils/logger.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/screens/online_management/login.dart';

// Assuming these imports remain the same
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/theme.dart';
import '../../providers/theme_provider.dart';
import '../../services/kill_switch_service.dart';
import '../../utils/constants.dart';
import 'kill_switch.dart';
import 'updater.dart';

class SettingsPage extends StatefulWidget {
  final bool isDashboard;
  const SettingsPage({super.key, this.isDashboard = false});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final sharedPreferencesService = SharedPreferencesService();
  final TextEditingController _postfixController = TextEditingController();
  final TextEditingController _retryController = TextEditingController();
  final TextEditingController _deleteDurationController =
      TextEditingController();

  final TextEditingController _forwardUnavailableLimitController =
      TextEditingController();

  int unavailableLimit = 0;

  bool autoSaveContacts = false;

  bool useSignature = false;
  bool autoSwitch = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    autoSaveContacts =
        await sharedPreferencesService.getAutoSaveContacts() ?? false;
    _postfixController.text =
        await sharedPreferencesService.getPostfixContactName() ?? '';
    _retryController.text =
        (await sharedPreferencesService.getRetryMinutes() ?? '').toString();
    _deleteDurationController.text =
        (await sharedPreferencesService.getAutoDeleteAfterNumberOfDays() ?? '')
            .toString();
    useSignature = await sharedPreferencesService.getUseSignature() ?? false;
    autoSwitch = await sharedPreferencesService.getCanAutoSwitch() ?? false;

    unavailableLimit =
        await sharedPreferencesService.getForwardUnavailableLimit() ?? 0;

    _forwardUnavailableLimitController.text = unavailableLimit.toString();

    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('Settings',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: !widget.isDashboard,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _buildSectionTitle('General'),
          _buildGroup([
            _buildToggleTile(
              label: 'Auto Save Contacts',
              value: autoSaveContacts,
              onChanged: (val) async {
                setState(() => autoSaveContacts = val);
                await sharedPreferencesService.setAutoSaveContacts(val);
              },
            ),
            _buildInputTile(
              label: 'Name Prefix',
              controller: _postfixController,
              hint: 'e.g. Customer',
              onSave: () => _saveField('Prefix', _postfixController.text,
                  sharedPreferencesService.setPostfixCOntactName),
            ),
            Divider(height: 1, color: theme.dividerColor.withOpacity(0.1)),
            _buildToggleTile(
                label: 'Forward unavailable amounts',
                value: unavailableLimit > 0,
                onChanged: (val) async {
                  if (!val) {
                    // If turning off, set limit to 0
                    await sharedPreferencesService
                        .setForwardUnavailableLimit(0);
                    setState(() => unavailableLimit = 0);
                  } else {
                    // If turning on, set to a default value if it was previously 0
                    if (unavailableLimit == 0) {
                      unavailableLimit = 400; // Default value when enabling
                      await sharedPreferencesService
                          .setForwardUnavailableLimit(unavailableLimit);
                      _forwardUnavailableLimitController.text =
                          unavailableLimit.toString();
                    }
                    setState(() => unavailableLimit = unavailableLimit);
                  }
                }),
            if (unavailableLimit > 0)
              _buildInputTile(
                label: 'Forward Unavailable Limit',
                controller: _forwardUnavailableLimitController,
                hint: 'Highest "unavailable" amount that can be forwarded',
                keyboardType: TextInputType.number,
                onSave: () => _saveField(
                    'Forward Limit',
                    _forwardUnavailableLimitController.text,
                    (val) => sharedPreferencesService
                        .setForwardUnavailableLimit(int.parse(val))),
              ),
          ]),
          _buildSectionTitle('Risk detection'),
          _buildGroup([
            _buildToggleTile(
                label: 'Detect code changes',
                hint: 'Use signatures to detect if USSD code has changed.',
                value: useSignature,
                onChanged: (val) async {
                  setState(() => useSignature = val);
                  await sharedPreferencesService.setUseSignature(val);
                }),
            if (useSignature)
              _buildToggleTile(
                  label: 'Auto-switch when change is detected',
                  hint:
                      'Automatically switch to the new code when changes are detected. experimental',
                  value: autoSwitch,
                  onChanged: (val) async {
                    setState(() => autoSwitch = val);
                    await sharedPreferencesService.setCanAutoSwitch(val);
                  }),
          ]),
          _buildSectionTitle('Automation'),
          _buildGroup([
            _buildInputTile(
              label: 'Retry Attempts',
              controller: _retryController,
              hint: '0',
              keyboardType: TextInputType.number,
              onSave: () => _saveField(
                  'Retry',
                  _retryController.text,
                  (val) =>
                      sharedPreferencesService.setRetryMinutes(int.parse(val))),
            ),
          ]),
          _buildSectionTitle('Appearance'),
          _buildThemeSelector(),
          _buildSectionTitle('Data Management'),
          _buildGroup([
            _buildInputTile(
              label: 'Auto-delete after (days)',
              controller: _deleteDurationController,
              hint: '0 to disable',
              keyboardType: TextInputType.number,
              onSave: () => _saveField(
                  'Duration',
                  _deleteDurationController.text,
                  (val) => sharedPreferencesService
                      .setAutoDeleteAfterNumberOfDays(int.parse(val))),
            ),
            ListTile(
              title: const Text('Send Logs to Developer',
                  style: TextStyle(
                      color: Colors.blueAccent, fontWeight: FontWeight.w600)),
              trailing: const Icon(CupertinoIcons.paperplane,
                  color: Colors.blueAccent, size: 20),
              onTap: _handleSendLogs,
            ),
            ListTile(
              title: const Text('Clear Transaction History',
                  style: TextStyle(
                      color: Colors.redAccent, fontWeight: FontWeight.w600)),
              trailing: const Icon(CupertinoIcons.delete,
                  color: Colors.redAccent, size: 20),
              onTap: _handleDeleteHistory,
            ),
          ]),
          _buildSectionTitle('About'),
          _buildGroup([
            ListTile(
              title: const Text('App Version'),
              subtitle: FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Text('Loading...');
                  } else if (snapshot.hasError) {
                    return const Text('Error loading version');
                  } else {
                    return Text(snapshot.data?.version ?? 'Unknown');
                  }
                },
              ),
            ),
            // check for updates. killswitch page
            ListTile(
              title: const Text('Check for updates'),
              trailing: const Icon(CupertinoIcons.refresh,
                  color: kPrimaryColor, size: 20),
              onTap: () {
                String arch = 'unknown';
                DeviceInfoPlugin().androidInfo.then((info) {
                  switch (info.supportedAbis.first) {
                    case 'arm64-v8a':
                      arch = 'arm64';
                      break;
                    case 'armeabi-v7a':
                      arch = 'armeabi';
                      break;
                    case 'x86_64':
                      arch = 'x86_64';
                      break;
                    case 'x86':
                      arch = 'x86';
                      break;
                    default:
                      return 'unknown';
                  }
                });

                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => 
                    // KillswitchScreen(
                    //   config: KillswitchConfig(
                    //     updateUrl: 'https://api.bsat.co.ke/api/general/download-app?arch_type=$arch',
                    //     message: '',
                    //     daysRemaining: 1000,
                    //     enforcement: KillswitchEnforcement.safe,
                    //   ),
                    ApkDownloaderPage(),
                  ),
                );
              },
            ),
          ]),
          const SizedBox(height: 50),
        ],
      ),
    );
  }

  // --- UI Components ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.2,
          color: Theme.of(context).primaryColor.withOpacity(0.7),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border:
            Border.all(color: Theme.of(context).dividerColor.withOpacity(0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildToggleTile({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    String? hint,
  }) {
    return ListTile(
      title: Text(label,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
      trailing: CupertinoSwitch(
          value: value, onChanged: onChanged, activeColor: kPrimaryColor),
      subtitle: hint != null
          ? Text(hint,
              style:
                  TextStyle(fontSize: 12, color: Theme.of(context).hintColor))
          : null,
    );
  }

  Widget _buildInputTile({
    required String label,
    required TextEditingController controller,
    required VoidCallback onSave,
    String? hint,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(label,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.end,
              style:
                  TextStyle(color: kPrimaryColor, fontWeight: FontWeight.bold),
              decoration: InputDecoration(
                hintText: hint,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          IconButton(
            icon: Icon(CupertinoIcons.check_mark_circled, size: 20),
            onPressed: onSave,
            color: kPrimaryColor,
          )
        ],
      ),
    );
  }

  Widget _buildThemeSelector() {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final List<Map<String, dynamic>> themes = [
      {
        'color': kBgColor,
        'action': themeProvider.setlightTheme,
        'name': 'Light'
      },
      {
        'color': kSecondaryColor,
        'action': themeProvider.setDarkTheme,
        'name': 'Dark'
      },
      {
        'color': kBrownBackground,
        'action': themeProvider.setBrownTheme,
        'name': 'Brown'
      },
      {
        'color': const Color.fromARGB(255, 82, 23, 52),
        'action': themeProvider.setPinkTheme,
        'name': 'Pink'
      },
      {
        'color': kIndigoColor.withAlpha(150),
        'action': themeProvider.setIndigoColor,
        'name': 'Indigo'
      },
      {
        'color': const Color(0xFF190b28),
        'action': themeProvider.setDarkPurpleTheme,
        'name': 'Purple'
      },
      {
        'color': Colors.black,
        'action': themeProvider.setBlackAndWhiteTheme,
        'name': 'OLED'
      },
    ];

    return _buildGroup([
      Padding(
        padding: const EdgeInsets.all(16.0),
        child: SizedBox(
          height: 60,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: themes.length,
            separatorBuilder: (_, __) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              return GestureDetector(
                onTap: themes[index]['action'],
                child: Column(
                  children: [
                    Container(
                      width: 35,
                      height: 35,
                      decoration: BoxDecoration(
                        color: themes[index]['color'],
                        shape: BoxShape.circle,
                        border: Border.all(
                            color: Colors.grey.withOpacity(0.3), width: 1),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(themes[index]['name'],
                        style: const TextStyle(fontSize: 10)),
                  ],
                ),
              );
            },
          ),
        ),
      )
    ]);
  }

  // --- Helpers ---

  Future<void> _saveField(
      String name, String value, Function(String) saveAction) async {
    // Show a small snackbar or haptic feedback instead of a heavy dialog for modernist feel
    await saveAction(value);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text('$name updated'),
          behavior: SnackBarBehavior.floating,
          width: 200),
    );
  }

  Future<void> _handleSendLogs() async {
    try {
      final isLoggedIn = await AuthService().isLoggedIn();
      if (!isLoggedIn) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Login Required'),
            content: const Text(
                'You need to be logged in to send logs to the developer.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                },
                child: const Text('Login'),
              ),
            ],
          ),
        );
        return;
      }

      if (BsatLogger.logFile != null && await BsatLogger.logFile!.exists()) {
        final content = await BsatLogger.logFile!.readAsString();
        if (content.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Log file is empty.')),
          );
          return;
        }

        final deviceName = await sharedPreferencesService.getDeviceName();
        final response = await BackendService().post(
          '/api/devices/logs',
          body: {
            'deviceName': deviceName ?? 'Unknown Device',
            'logs': content,
          },
        );

        if (response['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Logs sent successfully!')),
          );
          // clear logs after sending
          await BsatLogger.logFile!.writeAsString('');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('Failed: ${response['message'] ?? 'Unknown error'}')),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No logs available to send.')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _handleDeleteHistory() async {
    // Keep your logic but use a more modern confirmation style if possible
  }
}
