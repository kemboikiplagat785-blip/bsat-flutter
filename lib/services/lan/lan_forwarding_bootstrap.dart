import 'dart:async';

import 'package:bsat/services/firebase_messaging_service.dart';
import 'package:bsat/services/lan_forwarding_transport.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';

import 'lan_forwarding_service.dart';
import 'lan_local_identity.dart';
import 'lan_messages.dart';
import 'lan_peer_store.dart';

/// Runs a validated LAN request through the same handler FCM messages use,
/// with replies bound to the LAN session and the sender authenticated by the
/// peer's pinned key.
Future<void> handleLanForwardingRequest(
  LanForwardingData message,
  LanPeer peer,
  LanReplySink reply,
) =>
    handleRemoteMessage(
      RemoteMessage(data: message.data),
      replySink: reply,
      authenticatedSenderDeviceName: peer.deviceName,
    );

/// Runs a validated LAN reply (a receipt ACK or a confirmation receipt)
/// through the existing acknowledgement handlers. Such replies need no reply
/// of their own; nothing is sent anywhere else.
Future<void> handleLanForwardingReply(LanForwardingData reply, LanPeer peer) =>
    handleRemoteMessage(
      RemoteMessage(data: reply.data),
      replySink: (_) async {},
      authenticatedSenderDeviceName: peer.deviceName,
    );

/// Starts LAN forwarding in the main (UI) isolate, which owns the
/// Keystore-protected identity and the listener. Other isolates reach it
/// through [LanServiceRegistry]. Off Android, or when the Keystore is not
/// available, LAN stays unavailable and nothing else changes.
///
/// The listener runs only while this isolate runs and only after a pairing
/// exists. It is refreshed when the app resumes and every 30 seconds, so a
/// network change rebinds it. Android may still suspend or kill the process
/// in the background; LAN jobs then fail their delivery attempt and stay on
/// the existing retry schedules.
Future<void> startLanForwardingInMainIsolate() async {
  if (LanForwardingService.instance != null) return;
  final LanForwardingService service;
  try {
    service = LanForwardingService(
      peers: LanPeerStore(),
      identityStore: await androidLanIdentityStore(),
      // The Online device name, or this phone's local LAN name when it has
      // no Online registration: LAN needs no Online account.
      ownDeviceName: () async => (await forwardingDeviceName() ?? '').trim(),
      ownDeviceId: () async =>
          (await SharedPreferencesService().getDeviceId() ?? '').trim(),
      inboundHandler: handleLanForwardingRequest,
      replyProcessor: handleLanForwardingReply,
    );
  } catch (error) {
    debugPrint('LAN FORWARDING: unavailable on this device ($error)');
    return;
  }
  LanForwardingService.instance = service;
  LanServiceRegistry.register(service);
  await refreshLanForwarding();
  WidgetsBinding.instance.addObserver(_LanLifecycleObserver());
  Timer.periodic(const Duration(seconds: 30), (_) => refreshLanForwarding());
}

/// Loads the identity and (re)binds the listener when a pairing exists.
Future<void> refreshLanForwarding() async {
  final service = LanForwardingService.instance;
  if (service == null) return;
  try {
    if (await service.peers.isEmpty) return;
    await service.loadIdentity();
    await service.startListening();
  } catch (error) {
    debugPrint('LAN FORWARDING: refresh failed (${error.runtimeType})');
  }
}

class _LanLifecycleObserver extends WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refreshLanForwarding());
  }
}
