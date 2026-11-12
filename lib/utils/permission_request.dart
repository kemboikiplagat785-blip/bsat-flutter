import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

extension SafePermissionRequest on Permission {
  /// Like [request], but returns the current status instead of throwing when
  /// another permission request is still on screen: permission_handler allows
  /// only one at a time and fails the second with a PlatformException.
  Future<PermissionStatus> requestSafely() async {
    try {
      return await request();
    } on PlatformException {
      return status;
    }
  }
}
