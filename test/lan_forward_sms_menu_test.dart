// Home → Automation Tools → Forward SMS (online/offline): the "Use Another
// Phone" menu offers Online, Offline (SMS) and LAN, and each opens its own
// page. Widget tests only; no network, SMS or USSD.
import 'package:bsat/components/dialogs/use_another_phone_dialog.dart';
import 'package:bsat/screens/home/dashboard/dashboard_tools.dart';
import 'package:bsat/screens/online_management/lan/lan_management.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Page extends StatelessWidget {
  final String label;
  const _Page(this.label);

  @override
  Widget build(BuildContext context) =>
      Scaffold(body: Center(child: Text('page:$label')));
}

/// A screen with one button that opens the menu, with every option's page
/// replaced by a marker page (the real pages need Online, SMS or LAN
/// services).
Widget _menuHost({bool realLanPage = false}) => MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showUseAnotherPhoneDialog(
              context,
              onlinePageBuilder: (_) => const _Page('online'),
              offlinePageBuilder: (_) => const _Page('offline'),
              lanPageBuilder: realLanPage ? null : (_) => const _Page('lan'),
            ),
            child: const Text('open menu'),
          ),
        ),
      ),
    );

Future<void> _openMenu(WidgetTester tester, {bool realLanPage = false}) async {
  await tester.pumpWidget(_menuHost(realLanPage: realLanPage));
  await tester.tap(find.text('open menu'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the Home tools open the menu with Online, Offline (SMS) and LAN',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DashboardToolsSection(onReload: () {}),
        ),
      ),
    ));
    await tester.tap(find.text('Forward SMS (online/offline)'));
    await tester.pumpAndSettle();

    expect(find.text('Use Another Phone'), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);
    expect(find.text('Offline (sms)'), findsOneWidget);
    expect(find.text('LAN'), findsOneWidget);
    // Order: Online, Offline (SMS), LAN.
    final online = tester.getTopLeft(find.text('Online')).dy;
    final offline = tester.getTopLeft(find.text('Offline (sms)')).dy;
    final lan = tester.getTopLeft(find.text('LAN')).dy;
    expect(online < offline && offline < lan, isTrue);
  });

  testWidgets('Online still opens Online management', (tester) async {
    await _openMenu(tester);
    await tester.tap(find.text('Online'));
    await tester.pumpAndSettle();
    expect(find.text('page:online'), findsOneWidget);
    expect(find.text('Use Another Phone'), findsNothing);
  });

  testWidgets('Offline (SMS) still opens the SMS forwarding page',
      (tester) async {
    await _openMenu(tester);
    await tester.tap(find.text('Offline (sms)'));
    await tester.pumpAndSettle();
    expect(find.text('page:offline'), findsOneWidget);
  });

  testWidgets('LAN opens LAN management directly', (tester) async {
    await _openMenu(tester);
    await tester.tap(find.text('LAN'));
    await tester.pumpAndSettle();
    expect(find.text('page:lan'), findsOneWidget);
    expect(find.text('page:online'), findsNothing);
  });

  testWidgets('by default LAN pushes the LAN management screen',
      (tester) async {
    await _openMenu(tester, realLanPage: true);
    await tester.tap(find.text('LAN'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(LanManagementScreen), findsOneWidget);
  });

  testWidgets('Cancel closes the menu without navigating', (tester) async {
    await _openMenu(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Use Another Phone'), findsNothing);
    expect(find.textContaining('page:'), findsNothing);
  });
}
