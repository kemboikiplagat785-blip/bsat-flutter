import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

/// Where the key that protects the identity seed lives.
enum KeyProtection {
  /// Android Keystore key inside a StrongBox secure element.
  strongBox,

  /// Android Keystore key inside the TEE (hardware-backed).
  trustedEnvironment,

  /// Android Keystore key, but software-backed on this device.
  keystoreSoftware,

  /// Keystore did not report a level.
  keystoreUnknown,

  /// Test-only in-memory key. Never used by the app on a device.
  testOnly,
}

enum KeyWrapperErrorCode {
  /// The wrapping key does not exist (for example, app data was cleared or
  /// the Keystore entry was deleted).
  keyMissing,

  /// Android invalidated the wrapping key (for example, after a lock-screen
  /// change for a key that requires it).
  keyInvalidated,

  /// The wrapped blob failed authentication: corrupted or from another key.
  unwrapFailed,

  /// The Keystore could not be used on this device.
  keystoreUnavailable,
}

class KeyWrapperException implements Exception {
  final KeyWrapperErrorCode code;
  final String detail;

  const KeyWrapperException(this.code, this.detail);

  @override
  String toString() => 'KeyWrapperException(${code.name}): $detail';
}

/// Encrypts small secrets (the identity seed) under a key that never leaves
/// protected storage.
abstract class KeyWrapper {
  String get scheme;

  /// Encrypts [secret]. Creates the wrapping key if it does not exist.
  Future<Uint8List> wrap(Uint8List secret);

  /// Decrypts a blob from [wrap]. Never creates a key.
  Future<Uint8List> unwrap(Uint8List wrapped);

  Future<KeyProtection> protection();

  /// Deletes the wrapping key. Used only by an explicit identity reset.
  Future<void> deleteKey();
}

/// Android Keystore AES-256-GCM key, accessed through the platform channel
/// implemented in MainActivity.kt.
class AndroidKeystoreKeyWrapper implements KeyWrapper {
  static const MethodChannel _channel =
      MethodChannel('com.bsat.app/lan_keystore');

  @override
  String get scheme => 'android-keystore-aes256gcm-v1';

  Future<T> _call<T>(String method, [Object? args]) async {
    try {
      final result = await _channel.invokeMethod<T>(method, args);
      if (result == null) {
        throw const KeyWrapperException(
          KeyWrapperErrorCode.keystoreUnavailable,
          'Keystore returned no result.',
        );
      }
      return result;
    } on PlatformException catch (error) {
      throw KeyWrapperException(
        switch (error.code) {
          'KEY_MISSING' => KeyWrapperErrorCode.keyMissing,
          'KEY_INVALIDATED' => KeyWrapperErrorCode.keyInvalidated,
          'UNWRAP_FAILED' => KeyWrapperErrorCode.unwrapFailed,
          _ => KeyWrapperErrorCode.keystoreUnavailable,
        },
        error.message ?? error.code,
      );
    } on MissingPluginException {
      throw const KeyWrapperException(
        KeyWrapperErrorCode.keystoreUnavailable,
        'Android Keystore channel is not available on this platform.',
      );
    }
  }

  // Byte arrays decoded from a platform message are read-only views of the
  // message buffer; copy them so callers can zero the secret after use.
  @override
  Future<Uint8List> wrap(Uint8List secret) async =>
      Uint8List.fromList(await _call<Uint8List>('wrap', secret));

  @override
  Future<Uint8List> unwrap(Uint8List wrapped) async =>
      Uint8List.fromList(await _call<Uint8List>('unwrap', wrapped));

  @override
  Future<KeyProtection> protection() async {
    final level = await _call<String>('protection');
    return switch (level) {
      'strongbox' => KeyProtection.strongBox,
      'tee' => KeyProtection.trustedEnvironment,
      'software' => KeyProtection.keystoreSoftware,
      _ => KeyProtection.keystoreUnknown,
    };
  }

  @override
  Future<void> deleteKey() => _call<bool>('deleteKey');

  /// App-private directory excluded from Android auto-backup.
  static Future<Directory> noBackupDirectory() async =>
      Directory(await _channel.invokeMethod<String>('noBackupDir') ??
          (throw const KeyWrapperException(
            KeyWrapperErrorCode.keystoreUnavailable,
            'No app data directory.',
          )));
}

/// In-memory AES-GCM wrapper for host tests. Provides no protection at rest.
class TestKeyWrapper implements KeyWrapper {
  SecretKey? _key;
  bool failUnwrap = false;

  @override
  String get scheme => 'test-only-memory-aes256gcm';

  @override
  Future<Uint8List> wrap(Uint8List secret) async {
    final key = _key ??= await AesGcm.with256bits().newSecretKey();
    final box = await AesGcm.with256bits().encrypt(secret, secretKey: key);
    return Uint8List.fromList(box.concatenation());
  }

  @override
  Future<Uint8List> unwrap(Uint8List wrapped) async {
    final key = _key;
    if (key == null) {
      throw const KeyWrapperException(
          KeyWrapperErrorCode.keyMissing, 'Test key missing.');
    }
    if (failUnwrap) {
      throw const KeyWrapperException(
          KeyWrapperErrorCode.keyInvalidated, 'Test key invalidated.');
    }
    try {
      final box = SecretBox.fromConcatenation(wrapped,
          nonceLength: 12, macLength: 16);
      return Uint8List.fromList(
          await AesGcm.with256bits().decrypt(box, secretKey: key));
    } on SecretBoxAuthenticationError {
      throw const KeyWrapperException(
          KeyWrapperErrorCode.unwrapFailed, 'Test unwrap failed.');
    }
  }

  @override
  Future<KeyProtection> protection() async => KeyProtection.testOnly;

  @override
  Future<void> deleteKey() async => _key = null;
}
