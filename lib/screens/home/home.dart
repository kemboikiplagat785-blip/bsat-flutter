import 'package:bsat/screens/home/dashboard/dashboard.dart';
import 'package:bsat/screens/home/settings_page.dart';
import 'package:bsat/screens/home/tools_page.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../../utils/constants.dart';
import '../transactions/transaction_history.dart';
import '../settings/settings.dart';
import '../stats/statistics.dart';
import '../messaging/send_message_page.dart';
import 'data_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    // const _DashboardHome(),
    const DashBoardPage(isDashboard: true),
    const DataPage(),
    const ToolsPage(),
    const HomeSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // backgroundColor: kBgColor,
      extendBody: true,
      body: SafeArea(
        child: IndexedStack(
          index: _selectedIndex,
          children: _pages,
        ),
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(
            kPagePadding, 0, kPagePadding, kPagePadding),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
          border: Border (
            bottom: BorderSide(
              color: kIndigoColor,
              width: 3,
            ),
            right: BorderSide(
              color: kIndigoColor,
              width: 3,
            ),

          )
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(0),
          child: NavigationBarTheme(
            data: NavigationBarThemeData(
              backgroundColor: Theme.of(context).cardColor,
              indicatorColor: kIndigoColor.withOpacity(0.15),
              labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
              labelTextStyle: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    // color: kDarkerGreen,
                  );
                }
                return TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade500,
                );
              }),
              iconTheme: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return const IconThemeData(color: kIndigoColor, size: 26);
                }
                return IconThemeData(color: Colors.grey.shade500, size: 24);
              }),
            ),
            child: NavigationBar(
              height: 70,
              elevation: 0,
              backgroundColor: Theme.of(context).cardColor,
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              destinations: const [
                NavigationDestination(
                  icon: Icon(CupertinoIcons.home),
                  selectedIcon: Icon(CupertinoIcons.house_fill),
                  label: 'Home',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.doc_chart),
                  selectedIcon: Icon(CupertinoIcons.doc_chart_fill),
                  label: 'Data',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.wrench),
                  selectedIcon: Icon(CupertinoIcons.wrench_fill),
                  label: 'Tools',
                ),
                NavigationDestination(
                  icon: Icon(CupertinoIcons.settings),
                  selectedIcon: Icon(CupertinoIcons.settings_solid),
                  label: 'Settings',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.03),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 12),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
