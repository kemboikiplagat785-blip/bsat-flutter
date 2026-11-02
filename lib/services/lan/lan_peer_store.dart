import 'dart:convert';
import 'dart:typed_data';

import 'package:bsat/services/sqlite_service.dart';

import 'lan_crypto_util.dart';
import 'lan_device_identity.dart';

enum LanPeerStatus { trusted, revoked }

/// A device paired for LAN forwarding. Identity is the pinned Ed25519 public
/// key; [deviceName]/[deviceId] bind it to one BSAT device. The address and
/// port are routing hints only and are never used for authorization.
class LanPeer {
  final String fingerprint;
  final Uint8List publicKey;
  final String deviceName;
  final String deviceId;
  final LanPeerStatus status;
  final DateTime pairedAt;
  final DateTime? revokedAt;
  final String? lastAddress;
  final int? lastPort;
  final DateTime? lastConnectedAt;

  const LanPeer({
    required this.fingerprint,
    required this.publicKey,
    required this.deviceName,
    required this.deviceId,
    required this.status,
    required this.pairedAt,
    this.revokedAt,
    this.lastAddress,
    this.lastPort,
    this.lastConnectedAt,
  });

  bool get isTrusted => status == LanPeerStatus.trusted;
  String get displayId => displayFingerprint(fingerprint);

  Map<String, Object?> toRow() => {
        'fingerprint': fingerprint,
        'public_key': base64Encode(publicKey),
        'device_name': deviceName,
        'device_id': deviceId,
        'status': status.name,
        'paired_at': pairedAt.millisecondsSinceEpoch,
        'revoked_at': revokedAt?.millisecondsSinceEpoch,
        'last_address': lastAddress,
        'last_port': lastPort,
        'last_connected_at': lastConnectedAt?.millisecondsSinceEpoch,
      };

  /// Throws [FormatException] for a corrupted row: a record whose key does
  /// not match its fingerprint is never used.
  static LanPeer fromRow(Map<String, Object?> row) {
    final publicKey = base64Decode(row['public_key']?.toString() ?? '');
    final fingerprint = row['fingerprint']?.toString() ?? '';
    if (publicKey.length != 32 || fingerprintOf(publicKey) != fingerprint) {
      throw const FormatException('Fingerprint does not match public key.');
    }
    final status = switch (row['status']) {
      'trusted' => LanPeerStatus.trusted,
      'revoked' => LanPeerStatus.revoked,
      _ => throw const FormatException('Unknown LAN peer status.'),
    };
    DateTime? date(Object? value) {
      final ms = int.tryParse(value?.toString() ?? '');
      return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    }

    return LanPeer(
      fingerprint: fingerprint,
      publicKey: Uint8List.fromList(publicKey),
      deviceName: row['device_name']?.toString() ?? '',
      deviceId: row['device_id']?.toString() ?? '',
      status: status,
      pairedAt: date(row['paired_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      revokedAt: date(row['revoked_at']),
      lastAddress: row['last_address']?.toString(),
      lastPort: int.tryParse(row['last_port']?.toString() ?? ''),
      lastConnectedAt: date(row['last_connected_at']),
    );
  }
}

/// How a BSAT device name resolves to a LAN peer.
enum LanPeerLookupState {
  /// Exactly one trusted record.
  trusted,

  /// No record: never paired, or removed.
  unpaired,

  /// Only revoked records.
  revoked,

  /// The store could not be read or holds inconsistent records.
  unavailable,
}

class LanPeerLookup {
  final LanPeerLookupState state;
  final LanPeer? peer;

  const LanPeerLookup(this.state, [this.peer]);
}

/// Persisted LAN pairings (SQLite `lanPeers`).
class LanPeerStore {
  final SQLiteService _sqliteService;

  LanPeerStore([SQLiteService? sqliteService])
      : _sqliteService = sqliteService ?? SQLiteService();

  Future<List<LanPeer>> all() async {
    final rows = await _sqliteService.getLanPeers();
    final peers = <LanPeer>[];
    for (final row in rows) {
      try {
        peers.add(LanPeer.fromRow(row));
      } on FormatException {
        // A corrupted record is never trusted.
      }
    }
    return peers;
  }

  Future<bool> get isEmpty async => (await _sqliteService.getLanPeers()).isEmpty;

  Future<LanPeer?> byFingerprint(String fingerprint) async {
    final row = await _sqliteService.getLanPeer(fingerprint);
    if (row == null) return null;
    try {
      return LanPeer.fromRow(row);
    } on FormatException {
      return null;
    }
  }

  /// True only for a trusted record whose pinned key equals [publicKey].
  Future<bool> isTrustedKey(List<int> publicKey) async {
    final peer = await byFingerprint(fingerprintOf(publicKey));
    return peer != null &&
        peer.isTrusted &&
        constantTimeEquals(peer.publicKey, publicKey);
  }

  /// Resolves the LAN peer bound to [deviceName]. Never throws.
  Future<LanPeerLookup> lookupDevice(String deviceName) async {
    final name = deviceName.trim();
    if (name.isEmpty) return const LanPeerLookup(LanPeerLookupState.unpaired);
    try {
      final rows = await _sqliteService.getLanPeersForDevice(name);
      final peers = rows.map(LanPeer.fromRow).toList();
      final trusted = peers.where((peer) => peer.isTrusted).toList();
      if (trusted.length == 1) {
        return LanPeerLookup(LanPeerLookupState.trusted, trusted.single);
      }
      if (trusted.length > 1) {
        return const LanPeerLookup(LanPeerLookupState.unavailable);
      }
      return LanPeerLookup(
        peers.isEmpty ? LanPeerLookupState.unpaired : LanPeerLookupState.revoked,
        peers.isEmpty ? null : peers.first,
      );
    } catch (_) {
      return const LanPeerLookup(LanPeerLookupState.unavailable);
    }
  }

  Future<LanPeer> trust({
    required List<int> publicKey,
    required String deviceName,
    required String deviceId,
    String? address,
    int? port,
  }) async {
    final peer = LanPeer(
      fingerprint: fingerprintOf(publicKey),
      publicKey: Uint8List.fromList(publicKey),
      deviceName: deviceName,
      deviceId: deviceId,
      status: LanPeerStatus.trusted,
      pairedAt: DateTime.now(),
      lastAddress: address,
      lastPort: port,
    );
    await _sqliteService.saveLanPeer(peer.toRow());
    return peer;
  }

  Future<void> revoke(String fingerprint) async {
    final updated = await _sqliteService.revokeLanPeer(
      fingerprint,
      revokedAt: DateTime.now().millisecondsSinceEpoch,
    );
    if (updated != 1) throw StateError('Unknown LAN peer.');
  }

  Future<void> remove(String fingerprint) =>
      _sqliteService.removeLanPeer(fingerprint);

  Future<void> clear() => _sqliteService.clearLanPeers();

  Future<void> recordConnection(
    String fingerprint,
    String address, {
    int? port,
  }) =>
      _sqliteService.recordLanPeerConnection(
        fingerprint,
        address: address,
        port: port,
        connectedAt: DateTime.now().millisecondsSinceEpoch,
      );
}
