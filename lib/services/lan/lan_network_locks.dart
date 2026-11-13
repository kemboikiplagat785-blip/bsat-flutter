import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('com.bsat.app/lan_network');

/// Holds or releases the Android Wi-Fi lock (keeps Wi-Fi out of power-save so
/// incoming LAN connections are not delayed or dropped with the screen off)
/// and the multicast lock (lets discovery announcements through the Wi-Fi
/// packet filter). Held only while the LAN listener runs with a pairing.
/// Does nothing where the channel is not registered.
Future<void> setLanNetworkLocks(bool held) async {
  try {
    await _channel.invokeMethod<void>(held ? 'acquire' : 'release');
  } on MissingPluginException {
    // Not Android, or not the main engine.
  }
}
