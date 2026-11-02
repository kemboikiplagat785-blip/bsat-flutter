import 'dart:convert';

import 'package:bsat/services/sqlite_service.dart';

import 'lan_peer_store.dart';

/// `device_id` prefix of a forwarding rule created from LAN management. Such
/// a destination has no Online device record; its ID only marks the rule as
/// LAN-only.
const String lanOnlyDeviceIdPrefix = 'lan:';

/// True for a `forwardingDevices` row created from LAN management.
bool isLanOnlyForwardingRow(Map<String, dynamic> row) =>
    row['device_id']?.toString().startsWith(lanOnlyDeviceIdPrefix) == true;

/// A forwarding rule whose new jobs go over LAN: a `forwardingDevices` row
/// with `forwarding_transport = 'lan'`. The forwarding engine reads it like
/// every other rule; the per-job transport keeps retries on LAN.
class LanForwardingRule {
  final int id;
  final String deviceName;
  final String deviceId;
  final List<int> amounts;
  final bool enabled;

  const LanForwardingRule({
    required this.id,
    required this.deviceName,
    required this.deviceId,
    required this.amounts,
    required this.enabled,
  });

  /// Created from LAN management (no Online device record).
  bool get lanOnly => deviceId.startsWith(lanOnlyDeviceIdPrefix);

  static LanForwardingRule fromRow(Map<String, dynamic> row) =>
      LanForwardingRule(
        id: row['id'] as int,
        deviceName: row['device_name']?.toString() ?? '',
        deviceId: row['device_id']?.toString() ?? '',
        amounts: parseForwardingAmounts(row['amounts_to_forward']),
        enabled: (row['paused'] ?? 0) != 1,
      );
}

/// Reads the stored amounts as the forwarding engine does (brackets and
/// quotes ignored, comma separated); entries that are not numbers are
/// dropped.
List<int> parseForwardingAmounts(Object? stored) {
  final text = (stored?.toString() ?? '').replaceAll(RegExp(r'[\[\]"]'), '');
  return [
    for (final part in text.split(','))
      if (int.tryParse(part.trim()) case final amount?) amount,
  ];
}

/// A LAN rule change that was refused; [message] is user-readable.
class LanRuleException implements Exception {
  final String message;

  const LanRuleException(this.message);

  @override
  String toString() => message;
}

/// Creates, edits, enables/disables and removes LAN forwarding rules. Local
/// only: no backend call and no Online account is involved.
class LanForwardingRuleStore {
  final SQLiteService _sqlite;
  final LanPeerStore _peers;

  LanForwardingRuleStore({SQLiteService? sqliteService, LanPeerStore? peers})
      : _sqlite = sqliteService ?? SQLiteService(),
        _peers = peers ?? LanPeerStore(sqliteService);

  static const String _table = 'forwardingDevices';
  static const String _lan = 'lan';

  /// Every rule whose transport is LAN, by device name.
  Future<List<LanForwardingRule>> all() async {
    final rows = await _sqlite.queryCustom(
      _table,
      'forwarding_transport = ?',
      [_lan],
      orderBy: 'device_name ASC',
    );
    return rows.map(LanForwardingRule.fromRow).toList();
  }

  /// Adds a LAN rule for the trusted LAN device [deviceName].
  Future<LanForwardingRule> create({
    required String deviceName,
    required List<int> amounts,
  }) async {
    final name = deviceName.trim();
    final validAmounts = _validAmounts(amounts);
    final peer = await _trustedPeer(name);
    final existing = await _rowsNamed(name);
    if (existing.isNotEmpty) {
      throw LanRuleException(
        existing.single['forwarding_transport'] == _lan
            ? 'A LAN forwarding rule for $name already exists. Edit it '
                'instead.'
            : 'An Online forwarding rule for $name already exists. Remove '
                'it, or switch its transport to LAN in Online management.',
      );
    }
    final id = await _sqlite.insertStuff({
      'device_name': name,
      'device_id': '$lanOnlyDeviceIdPrefix${peer.fingerprint}',
      'owner_email': '',
      'user_id': null,
      'amounts_to_forward': jsonEncode(validAmounts),
      'paused': 0,
      'forwarding_transport': _lan,
    }, _table);
    return (await _byId(id))!;
  }

  /// Changes the amounts of rule [id] and, for a LAN-only rule, its device.
  /// A rule that came from Online management keeps its device.
  Future<LanForwardingRule> update(
    int id, {
    required String deviceName,
    required List<int> amounts,
  }) async {
    final rule = await _byId(id);
    if (rule == null) throw const LanRuleException('The rule no longer exists.');
    final name = deviceName.trim();
    final validAmounts = _validAmounts(amounts);
    final changes = <String, dynamic>{
      'amounts_to_forward': jsonEncode(validAmounts),
    };
    if (name != rule.deviceName) {
      if (!rule.lanOnly) {
        throw const LanRuleException(
            'This rule belongs to an Online device; its device can only be '
            'changed in Online management.');
      }
      final peer = await _trustedPeer(name);
      if ((await _rowsNamed(name)).isNotEmpty) {
        throw LanRuleException('A forwarding rule for $name already exists.');
      }
      changes['device_name'] = name;
      changes['device_id'] = '$lanOnlyDeviceIdPrefix${peer.fingerprint}';
    }
    await _sqlite.updateStuff(
      changes,
      'id = ? AND forwarding_transport = ?',
      [id, _lan],
      _table,
    );
    return (await _byId(id))!;
  }

  /// Enables (resumes) or disables (pauses) rule [id]. A disabled rule gets
  /// no new jobs; jobs already created keep their own retry schedule.
  Future<void> setEnabled(int id, bool enabled) async {
    final updated = await _sqlite.updateStuff(
      {'paused': enabled ? 0 : 1},
      'id = ? AND forwarding_transport = ?',
      [id, _lan],
      _table,
    );
    if (updated != 1) throw const LanRuleException('The rule no longer exists.');
  }

  /// Deletes rule [id]. Existing jobs keep their persisted transport.
  Future<void> remove(int id) async {
    await _sqlite.deleteWhere(
      _table,
      'id = ? AND forwarding_transport = ?',
      [id, _lan],
    );
  }

  Future<LanForwardingRule?> _byId(int id) async {
    final rows = await _sqlite.queryCustom(
      _table,
      'id = ? AND forwarding_transport = ?',
      [id, _lan],
      limit: 1,
    );
    return rows.isEmpty ? null : LanForwardingRule.fromRow(rows.single);
  }

  Future<List<Map<String, dynamic>>> _rowsNamed(String name) =>
      _sqlite.queryCustom(_table, 'device_name = ?', [name], limit: 1);

  Future<LanPeer> _trustedPeer(String name) async {
    final lookup = await _peers.lookupDevice(name);
    if (lookup.state != LanPeerLookupState.trusted || lookup.peer == null) {
      throw LanRuleException(
          '$name is not a trusted LAN device. Pair it over LAN first.');
    }
    return lookup.peer!;
  }

  static List<int> _validAmounts(List<int> amounts) {
    final unique = amounts.toSet().toList()..sort();
    if (unique.isEmpty) {
      throw const LanRuleException('Add at least one amount to forward.');
    }
    if (unique.any((amount) => amount <= 0)) {
      throw const LanRuleException('Amounts must be greater than zero.');
    }
    return unique;
  }
}
