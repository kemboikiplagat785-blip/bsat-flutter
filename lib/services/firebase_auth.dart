import 'package:firebase_auth/firebase_auth.dart';

class MyFirebaseAuth {
  bool isSignedIn() {
    bool isSignedIn = false;
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (user == null) {
        isSignedIn = false;
      } else {
        isSignedIn = true;
      }
    });
    return isSignedIn;
  }
}
