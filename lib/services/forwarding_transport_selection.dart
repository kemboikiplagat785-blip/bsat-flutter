/// Per-destination choice of forwarding transport.
///
/// The destination's preference decides the transport of *new* jobs only.
/// Each job persists its own transport (`transactions.forwardingTransport`);
/// retries and recovery use that, never the current preference. A LAN
/// destination is never silently sent over the Internet instead.
library;

import 'package:bsat/services/sqlite_service.dart';

/// Transport a destination device is configured to receive forwarding over.
enum ForwardingTransportKind { online, lan }

/// Interprets a stored preference. Only the exact value `'lan'` selects LAN;
/// anything else (missing, null, `'online'`, unknown or malformed) is the
/// existing default, online.
ForwardingTransportKind parseForwardingTransportPreference(Object? stored) =>
    stored == 'lan' ? ForwardingTransportKind.lan : ForwardingTransportKind.online;

/// A forwarding destination as persisted in `forwardingDevices`.
/// [deviceId] is the backend device ID; [deviceName] is the unique name the
/// forwarding code addresses (and stores on jobs).
class ForwardingDestination {
  final String deviceId;
  final String deviceName;

  /// True only for an alternative target that was looked up in
  /// `whitelistedDevices` because it has no `forwardingDevices` row. Such a
  /// destination has no stored preference and resolves to online, as before
  /// preferences were persisted.
  final bool whitelistOnly;

  const ForwardingDestination({
    required this.deviceId,
    required this.deviceName,
    this.whitelistOnly = false,
  });

  factory ForwardingDestination.fromDeviceRow(Map<String, dynamic> row) =>
      ForwardingDestination(
        deviceId: row['device_id']?.toString() ?? '',
        deviceName: row['device_name']?.toString() ?? '',
      );

  factory ForwardingDestination.fromWhitelistedDeviceRow(
    Map<String, dynamic> row,
  ) =>
      ForwardingDestination(
        deviceId: row['device_id']?.toString() ?? '',
        deviceName: row['device_name']?.toString() ?? '',
        whitelistOnly: true,
      );
}

/// Source of stored per-destination transport preferences.
abstract class ForwardingTransportPreferences {
  /// The raw stored preference for [destination], or null when none is
  /// stored. May throw if the store cannot be read.
  Future<Object?> storedPreferenceFor(ForwardingDestination destination);
}

/// Default source: the `forwarding_transport` column of the destination's
/// `forwardingDevices` row. Legacy rows (NULL) resolve to online, exactly as
/// before transport selection; deleting the row deletes its preference.
class SQLiteForwardingTransportPreferences
    implements ForwardingTransportPreferences {
  final SQLiteService _sqliteService;

  SQLiteForwardingTransportPreferences([SQLiteService? sqliteService])
      : _sqliteService = sqliteService ?? SQLiteService();

  /// Throws when the destination's row does not exist or cannot be read. A
  /// whitelist-only destination has no stored preference (null), but only
  /// after the database confirms it is one; otherwise this throws.
  @override
  Future<Object?> storedPreferenceFor(
    ForwardingDestination destination,
  ) async {
    if (destination.whitelistOnly) {
      await _sqliteService.verifyWhitelistOnlyDestination(
        deviceId: destination.deviceId,
        deviceName: destination.deviceName,
      );
      return null;
    }
    return _sqliteService.getForwardingTransportPreference(
      deviceId: destination.deviceId,
      deviceName: destination.deviceName,
    );
  }

  /// Stores [kind] for [destination] only. Throws when its row does not exist.
  Future<void> save(
    ForwardingDestination destination,
    ForwardingTransportKind kind,
  ) async {
    final updated = await _sqliteService.setForwardingTransportPreference(
      deviceId: destination.deviceId,
      deviceName: destination.deviceName,
      transport: kind.name,
    );
    if (updated == 0) {
      throw StateError('Forwarding device not found');
    }
  }
}

/// Routing decision for *new* forwarding to one destination.
class ForwardingRouteDecision {
  /// The configured transport, or null when the preference could not be read.
  final ForwardingTransportKind? selected;

  const ForwardingRouteDecision._(this.selected);

  /// Whether a new job may be submitted to this destination over the
  /// Internet transport. LAN and unreadable preferences are not; a LAN
  /// destination is reachable only through the LAN transport.
  bool get deliverable => selected == ForwardingTransportKind.online;

  /// Short label for logs.
  String get label => selected?.name ?? 'unresolved';
}

/// Transport for a manual forward to a device picked from the paired-device
/// list. That list is the backend's whitelist, so a pick may have no
/// forwarding device record: such a device keeps the legacy Online path, as
/// manual forwarding always had. A pick that matches a forwarding device
/// record (by name or ID) uses that record's preference; a match that is
/// ambiguous, or a store that cannot be read, has no transport (null).
Future<ForwardingTransportKind?> resolveManualForwardingTransport({
  required SQLiteService sqliteService,
  required String deviceId,
  required String deviceName,
}) async {
  if (deviceName.trim().isEmpty) return null;
  try {
    final rows = await sqliteService.queryCustom(
      'forwardingDevices',
      deviceId.trim().isEmpty
          ? 'device_name = ?'
          : 'device_name = ? OR device_id = ?',
      deviceId.trim().isEmpty ? [deviceName] : [deviceName, deviceId],
      limit: 2,
    );
    if (rows.isEmpty) return ForwardingTransportKind.online;
    if (rows.length != 1 ||
        rows.single['device_name']?.toString() != deviceName) {
      return null;
    }
    return parseForwardingTransportPreference(
      rows.single['forwarding_transport'],
    );
  } catch (_) {
    return null;
  }
}

/// Resolves the transport for a destination. Reads only the preference
/// source: no network, no transaction state, no USSD.
class ForwardingTransportResolver {
  final ForwardingTransportPreferences preferences;

  const ForwardingTransportResolver(this.preferences);

  Future<ForwardingRouteDecision> resolve(
    ForwardingDestination destination,
  ) async {
    final Object? stored;
    try {
      stored = await preferences.storedPreferenceFor(destination);
    } catch (_) {
      // An unreadable preference might be LAN; never assume online.
      return const ForwardingRouteDecision._(null);
    }
    return ForwardingRouteDecision._(
        parseForwardingTransportPreference(stored));
  }
}
