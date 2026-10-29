import 'package:bsat/services/sqlite_service.dart';

/// A BSAT device this phone may pair with over LAN.
class LanPairingCandidate {
  final String deviceName;
  final String deviceId;

  const LanPairingCandidate({required this.deviceName, required this.deviceId});
}

/// Devices this phone already knows: its Online paired (whitelisted) devices
/// and its forwarding rule targets, read from this phone's database only (no
/// network). LAN pairing adds a local connection to a known device; it never
/// makes an unknown device a candidate. Sorted by name; one entry per name,
/// the whitelist entry first.
Future<List<LanPairingCandidate>> loadLanPairingCandidates([
  SQLiteService? sqliteService,
]) async {
  final sqlite = sqliteService ?? SQLiteService();
  final byName = <String, LanPairingCandidate>{};
  for (final table in const ['whitelistedDevices', 'forwardingDevices']) {
    try {
      for (final row in await sqlite.queryAll(table)) {
        final name = row['device_name']?.toString().trim() ?? '';
        if (name.isEmpty) continue;
        byName.putIfAbsent(
          name,
          () => LanPairingCandidate(
            deviceName: name,
            deviceId: row['device_id']?.toString() ?? '',
          ),
        );
      }
    } catch (_) {
      // A missing table simply contributes no devices.
    }
  }
  return byName.values.toList()
    ..sort((a, b) => a.deviceName.compareTo(b.deviceName));
}

/// Shown when [loadLanPairingCandidates] finds no device.
const String lanNoPairingCandidatesHelp =
    'This phone knows no Online devices; that is fine for LAN. Type the '
    "other phone's LAN name below:\n"
    "1. On both phones, open Forward SMS → LAN and set each phone's name.\n"
    '2. On each phone, tap "Pair LAN device" and type the other phone\'s '
    'name.\n'
    '3. Make sure both phones are on the same Wi-Fi or hotspot.\n'
    'Phones with Online accounts may instead pair online first ("Pair New '
    'Device" in Online management) and then choose each other here.';
