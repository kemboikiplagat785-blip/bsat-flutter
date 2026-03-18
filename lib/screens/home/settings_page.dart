import 'package:bsat/screens/black_screen.dart';
import 'package:bsat/screens/settings/about.dart';
import 'package:bsat/screens/settings/settings.dart';
import 'package:bsat/screens/settings/subscription.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/button_descriptive.dart';
import '../../components/header.dart';
import '../../utils/constants.dart';

class HomeSettingsPage extends StatefulWidget {
  const HomeSettingsPage({super.key});

  @override
  State<HomeSettingsPage> createState() => _HomeSettingsPageState();
}

class _HomeSettingsPageState extends State<HomeSettingsPage> {
    String appVersion = '';

  @override
  void initState() {
    super.initState();
    getAppVersion().then((value) {
      setState(() {
        appVersion = value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              header(context, "Settings", hideBack: true),

              // renew subscription
              buttonDescriptive(
                context,
                title: 'Renew or manage your subscription',
                subtitle: 'Subscription',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SubscriptionPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.money_dollar,
                  color: kIndigoColor,
                ),
              ),

              
              // account settings
              buttonDescriptive(
                context,
                title: 'Manage your account details, preferences, and security settings',
                subtitle: 'Settings',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SettingsPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.settings,
                  color: kPrimaryColor,
                ),
              ),
              
              // account settings
              buttonDescriptive(
                context,
                title: 'Reduce power consumption when running advanced requests',
                subtitle: 'Black Screen',
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const BlackoutScreen(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.lightbulb,
                  color: kWarningColor,
                ),
              ),
                    const SizedBox(height: kPagePadding * 7),
            ],
          ),
        ),
      ),
    );
  }
}