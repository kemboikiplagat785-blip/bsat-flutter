import 'package:bsat/services/shared_preferences_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The name this phone uses for LAN forwarding when it has no Online BSAT
/// device registration. Stored on this phone only; never sent to the backend.
const String lanLocalDeviceNameKey = 'lan_local_device_name';

/// Longest accepted name; the LAN pairing identity accepts no longer one.
const int lanDeviceNameMaxChars = 100;

/// A user-readable reason [name] cannot be this phone's LAN name, or null.
/// Mirrors what the other phone accepts in the pairing identity.
String? lanDeviceNameProblem(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return 'Enter a name for this phone.';
  if (trimmed.length > lanDeviceNameMaxChars) {
    return 'The name is too long (at most $lanDeviceNameMaxChars characters).';
  }
  if (trimmed.contains(RegExp(r'[\x00-\x1f]'))) {
    return 'The name contains invalid characters.';
  }
  return null;
}

/// The locally chosen LAN name, or null when none is set.
Future<String?> getLanLocalDeviceName() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.reload();
  final name = prefs.getString(lanLocalDeviceNameKey)?.trim() ?? '';
  return name.isEmpty ? null : name;
}

/// Stores [name] as this phone's LAN name. Throws [ArgumentError] when
/// [lanDeviceNameProblem] refuses it.
Future<void> setLanLocalDeviceName(String name) async {
  final problem = lanDeviceNameProblem(name);
  if (problem != null) throw ArgumentError(problem);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(lanLocalDeviceNameKey, name.trim());
}

/// The name this phone puts on forwarding messages and LAN pairings.
///
/// A phone registered Online keeps its Online device name, exactly as
/// before. Only a phone without one uses its local LAN name; with neither,
/// the Online value (null or empty) is returned unchanged, so every caller's
/// existing fallback still applies.
Future<String?> forwardingDeviceName() async {
  final online = await SharedPreferencesService().getDeviceName();
  if (online != null && online.trim().isNotEmpty) return online;
  return await getLanLocalDeviceName() ?? online;
}

/// True when this phone's forwarding name comes from its Online
/// registration (it then cannot be changed from the LAN screen).
Future<bool> hasOnlineDeviceName() async {
  final online = await SharedPreferencesService().getDeviceName();
  return online != null && online.trim().isNotEmpty;
}
