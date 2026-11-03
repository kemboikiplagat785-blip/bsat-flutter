// After a first install the onboarding page can still be alive under the app.
// Opening the keyboard rebuilds it, and that must not close the screen on top.
import 'package:bsat/screens/onboarding/main_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('opening the keyboard does not close the screen on top',
      (tester) async {
    PackageInfo.setMockInitialValues(
      appName: 'BSAT',
      packageName: 'com.bsat.app',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({'running_status': false});
    final navigator = GlobalKey<NavigatorState>();
    tester.view.physicalSize = const Size(1080, 3600);
    addTearDown(tester.view.reset);

    // The onboarding logo animates forever, so nothing ever settles.
    Future<void> settle() async {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
    }

    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigator,
      home: const OnboardingPage(),
    ));
    await settle();

    // Onboarding finishes while its first page stays underneath.
    await (await SharedPreferences.getInstance())
        .setBool('running_status', true);
    navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(body: TextField()),
    ));
    await settle();
    expect(find.byType(TextField), findsOneWidget);

    // The keyboard opening changes the screen's insets for every page.
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await settle();

    expect(find.byType(TextField), findsOneWidget);
  });
}
