import 'package:bsat/components/hero.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // For Clipboard
import 'package:url_launcher/url_launcher.dart'; // Add url_launcher to pubspec.yaml
import '../../utils/constants.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String appVersion = '1.0.0'; // Default if loading fails

  @override
  void initState() {
    super.initState();
    // Assuming getAppVersion is a helper you've defined elsewhere
    getAppVersion().then((value) => setState(() => appVersion = value));
  }

  // Helpers for Actions
  void _launchURL(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _copyToClipboard(String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Copied to clipboard'),
        behavior: SnackBarBehavior.floating,
        width: 200,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text('About',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 24)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const MyHeroWidget(),
          _buildSectionTitle('The Project'),
          _buildGroup([
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'BSAT (Bingwa Sokoni Automation Toolkit) helps you automate and monitor USSD tasks. This is a personal project and is not affiliated with Safaricom or M-Pesa.',
                style: TextStyle(height: 1.5, fontSize: 14),
              ),
            ),
          ]),
          _buildSectionTitle('Support'),
          _buildGroup([
            _buildActionTile(
              label: 'Call Support',
              value: '0742342297',
              icon: CupertinoIcons.phone,
              onTap: () => _launchURL('tel:0742342297'),
              onLongPress: () => _copyToClipboard('0742342297'),
            ),
            _buildActionTile(
              label: 'WhatsApp',
              value: '0795559924',
              icon: CupertinoIcons.chat_bubble_2,
              onTap: () => _launchURL('https://wa.me/254795559924'),
              onLongPress: () => _copyToClipboard('0795559924'),
            ),
          ]),
          _buildSectionTitle('Legal'),
          _buildGroup([
            _buildActionTile(
              label: 'Affiliation',
              value: 'Independent Project',
              icon: CupertinoIcons.shield,
            ),
          ]),
          const SizedBox(height: 40),
          const Center(
            child: Text('Made with ❤️ in Kenya',
                style: TextStyle(fontSize: 12, color: Colors.grey)),
          ),
        ],
      ),
    );
  }

  // --- UI Reusable Components (Matches Settings UI) ---

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 24),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.1,
          color: kIndigoColor.withValues(alpha: 0.7),
        ),
      ),
    );
  }

  Widget _buildGroup(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: Theme.of(context).dividerColor.withValues(alpha: 0.05)),
      ),
      child: Column(children: children),
    );
  }

  Widget _buildActionTile({
    required String label,
    required String value,
    required IconData icon,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      leading: Icon(icon, size: 22, color: kIndigoColor),
      title: Text(label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
      subtitle: Text(value,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
      trailing: onTap != null
          ? const Icon(CupertinoIcons.chevron_right, size: 14)
          : null,
    );
  }
}
