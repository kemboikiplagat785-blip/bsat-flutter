import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'lan_crypto_util.dart';
import 'lan_atomic_file.dart';
import 'lan_key_wrapper.dart';

/// Fingerprint scheme (documented in README):
///   fingerprint = SHA-256( "BSAT-LAN-ID-V1" || ed25519_public_key[32] )
/// The 64-hex-digit lowercase form is the stable device ID. The display form
/// is the first 16 bytes as uppercase hex in 8 groups of 4.
const String _fingerprintLabel = 'BSAT-LAN-ID-V1';

Uint8List fingerprintBytes(List<int> publicKey) {
  if (publicKey.length != 32) {
    throw ArgumentError('Ed25519 public keys are 32 bytes.');
  }
  return Uint8List.fromList(const DartSha256()
      .hashSync([...utf8.encode(_fingerprintLabel), ...publicKey]).bytes);
}

String fingerprintOf(List<int> publicKey) => hexEncode(fingerprintBytes(publicKey));

String displayFingerprint(String fingerprintHex) {
  final upper = fingerprintHex.substring(0, 32).toUpperCase();
  return [
    for (var i = 0; i < upper.length; i += 4) upper.substring(i, i + 4),
  ].join('-');
}

String hexEncode(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

Uint8List hexDecode(String hex) {
  if (hex.length.isOdd || !RegExp(r'^[0-9a-fA-F]*$').hasMatch(hex)) {
    throw const FormatException('Invalid hex');
  }
  return Uint8List.fromList([
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ]);
}

/// This installation's signing identity. The private key exists only in
/// memory while the app runs; at rest the seed is wrapped by [KeyWrapper].
class DeviceIdentity {
  final SimpleKeyPair keyPair;
  final Uint8List publicKey;
  final String fingerprint;
  final KeyProtection protection;
  final DateTime createdAt;

  DeviceIdentity._(
    this.keyPair,
    this.publicKey,
    this.fingerprint,
    this.protection,
    this.createdAt,
  );

  String get displayId => displayFingerprint(fingerprint);

  Future<Uint8List> sign(List<int> message) async {
    final signature = await Ed25519().sign(message, keyPair: keyPair);
    return Uint8List.fromList(signature.bytes);
  }
}

Future<bool> verifyEd25519({
  required List<int> message,
  required List<int> signature,
  required List<int> publicKey,
}) async {
  if (signature.length != 64 || publicKey.length != 32) return false;
  try {
    return await Ed25519().verify(
      message,
      signature: Signature(
        signature,
        publicKey: SimplePublicKey(publicKey, type: KeyPairType.ed25519),
      ),
    );
  } catch (_) {
    return false;
  }
}

enum IdentityStatus {
  /// Loaded and usable.
  ready,

  /// No identity yet and nothing depends on one; [IdentityStore.create] may
  /// be called.
  absent,

  /// The identity file exists but its key cannot be recovered. Trust must
  /// not be reused with a new key; the user must explicitly reset.
  unavailable,

  /// No identity file, but trusted devices exist (for example, partial data
  /// loss). Refuses to create a replacement automatically.
  missingWithTrust,
}

class IdentityLoadResult {
  final IdentityStatus status;
  final DeviceIdentity? identity;
  final String? problem;

  const IdentityLoadResult(this.status, {this.identity, this.problem});
}

class IdentityStore {
  static const int _formatVersion = 1;

  final Directory directory;
  final KeyWrapper wrapper;

  IdentityStore({required this.directory, required this.wrapper});

  File get _file => File('${directory.path}/identity.json');

  /// [hasTrustRelationships] lets the store refuse to silently start over
  /// when trust already exists.
  Future<IdentityLoadResult> load({required bool hasTrustRelationships}) async {
    final Object? json;
    try {
      json = await readJsonFile(_file);
    } on StorageException catch (error) {
      return IdentityLoadResult(IdentityStatus.unavailable,
          problem: 'Identity file is unreadable: ${error.detail}');
    }
    if (json == null) {
      return IdentityLoadResult(
        hasTrustRelationships
            ? IdentityStatus.missingWithTrust
            : IdentityStatus.absent,
        problem: hasTrustRelationships
            ? 'The device identity is missing but trusted devices exist. '
                'A new identity will not be created automatically.'
            : null,
      );
    }
    try {
      if (json is! Map<String, dynamic> ||
          json['version'] != _formatVersion ||
          json['scheme'] != wrapper.scheme) {
        return const IdentityLoadResult(IdentityStatus.unavailable,
            problem: 'Identity file has an unsupported format or key scheme.');
      }
      final publicKey = base64Decode(json['publicKey'] as String);
      final wrapped = base64Decode(json['wrappedSeed'] as String);
      final seed = await wrapper.unwrap(Uint8List.fromList(wrapped));
      final keyPair = await Ed25519().newKeyPairFromSeed(seed);
      seed.fillRange(0, seed.length, 0);
      final derived = (await keyPair.extractPublicKey()).bytes;
      if (!_equal(derived, publicKey) ||
          fingerprintOf(publicKey) != json['fingerprint']) {
        return const IdentityLoadResult(IdentityStatus.unavailable,
            problem: 'Identity key does not match its stored public key.');
      }
      return IdentityLoadResult(
        IdentityStatus.ready,
        identity: DeviceIdentity._(
          keyPair,
          Uint8List.fromList(publicKey),
          json['fingerprint'] as String,
          await wrapper.protection(),
          DateTime.parse(json['createdAt'] as String),
        ),
      );
    } on KeyWrapperException catch (error) {
      return IdentityLoadResult(IdentityStatus.unavailable,
          problem: 'Identity key cannot be used (${error.code.name}): '
              '${error.detail}');
    } catch (error) {
      return IdentityLoadResult(IdentityStatus.unavailable,
          problem: 'Identity file is corrupted: $error');
    }
  }

  /// Creates a new identity. Fails if one already exists.
  Future<DeviceIdentity> create() async {
    if (await _file.exists()) {
      throw StateError('An identity already exists; reset it explicitly.');
    }
    final seed = secureRandomBytes(32);
    try {
      final keyPair = await Ed25519().newKeyPairFromSeed(seed);
      final publicKey =
          Uint8List.fromList((await keyPair.extractPublicKey()).bytes);
      final wrapped = await wrapper.wrap(seed);
      final createdAt = DateTime.now().toUtc();
      final fingerprint = fingerprintOf(publicKey);
      await writeJsonAtomically(_file, {
        'version': _formatVersion,
        'scheme': wrapper.scheme,
        'publicKey': base64Encode(publicKey),
        'fingerprint': fingerprint,
        'wrappedSeed': base64Encode(wrapped),
        'createdAt': createdAt.toIso8601String(),
      });
      return DeviceIdentity._(keyPair, publicKey, fingerprint,
          await wrapper.protection(), createdAt);
    } finally {
      seed.fillRange(0, seed.length, 0);
    }
  }

  /// Explicit, user-confirmed reset: removes the identity file and its
  /// wrapping key. The caller must also clear all trust relationships.
  Future<void> destroy() async {
    if (await _file.exists()) await _file.delete();
    await wrapper.deleteKey();
  }
}

bool _equal(List<int> a, List<int> b) => constantTimeEquals(a, b);
