import 'package:bsat/components/dialogs/show_error_dialog.dart';
import 'package:bsat/screens/onboarding/login.dart';
import 'package:bsat/screens/onboarding/signup.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../services/firebase_auth.dart';
import '../utils/internet.dart';

class OnlineManagementScreen extends StatefulWidget {
  const OnlineManagementScreen({super.key});

  @override
  State<OnlineManagementScreen> createState() => _OnlineManagementScreenState();
}

class _OnlineManagementScreenState extends State<OnlineManagementScreen> {
  var myFirebaseAuth = MyFirebaseAuth();

  bool isSignedIn = true;

  bool isOnline = true;

  @override
  void initState() {
    super.initState();

    checkIfConnected();

    setState(() => isSignedIn = myFirebaseAuth.isSignedIn());
  }

  void checkIfConnected() async {
    isOnline = await InternetUtils.isConnected();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!isOnline) {
      showErrorDialog(
        context,
        'No Internet',
        'Connect to the internet to continue.',
      ).then((_) async {
        Navigator.pop(context);
      });

      // return;
    }
    if (!isSignedIn) {
      Navigator.of(context).push(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => SignupPage(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return CupertinoPageTransition(
              primaryRouteAnimation: animation,
              secondaryRouteAnimation: secondaryAnimation,
              linearTransition: true,
              child: child,
            );
          },
        ),
      );
    }
    return const Scaffold();
  }
}
