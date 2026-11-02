/// Authenticated LAN transport for BSAT forwarding.
///
/// Built from the BSAT Local Lab prototype's secure session (pinned Ed25519
/// identities, X25519 + HKDF session keys, ChaCha20-Poly1305 records), its
/// framing and its QR pairing. The prototype's long-lived reconnecting sender,
/// heartbeat, JSON outbox and received-message ledger are deliberately NOT
/// used: BSAT's SQLite job rows, submission claims, receiver claims and retry
/// schedules stay the only durable state and the only retry loops.
///
/// Every LAN exchange is one bounded session: connect, authenticate, send one
/// forwarding message, read the replies the receiver's existing handler
/// produces (receipt ACK, confirmation receipt), close. A socket write or a
/// frame never means anything by itself; only the existing handlers decide.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'lan_device_identity.dart';
import 'lan_frame_connection.dart';
import 'lan_framing.dart';
import 'lan_key_wrapper.dart';
import 'lan_messages.dart';
import 'lan_net_util.dart';
import 'lan_pairing.dart';
import 'lan_peer_store.dart';
import 'lan_secure_session.dart';

/// Sends one reply (an Internet-style request body whose `data` map is what
/// the peer's handler will see) over the session that carried a request.
typedef LanReplySink = Future<void> Function(Map<String, dynamic> postBody);

/// Handles one authenticated, validated request. Runs the existing BSAT
/// handlers; replies go to [reply], never to the Internet.
typedef LanInboundHandler = Future<void> Function(
  LanForwardingData message,
  LanPeer peer,
  LanReplySink reply,
);

/// Processes one validated reply received by the client side of an exchange.
typedef LanReplyProcessor = Future<void> Function(
  LanForwardingData reply,
  LanPeer peer,
);

enum LanExchangeOutcome {
  /// The expected reply arrived (or, when none is expected, the receiver
  /// reported that it handled the request).
  completed,

  /// The receiver finished without sending the expected reply (for example
  /// its handler refused the job before claiming it).
  noReply,

  /// The receiver refused the request before running any handler.
  refused,

  /// No LAN identity on this device yet.
  notConfigured,

  /// The destination is not paired.
  unpaired,

  /// The destination's pairing was revoked.
  revoked,

  /// Could not connect (no address, refused, unreachable, timed out).
  unreachable,

  /// The peer failed authentication or does not trust this device.
  authenticationFailed,

  /// The request was written but no final answer arrived in time, or the
  /// session ended. The receiver may have accepted it.
  deliveryUnknown,

  /// The peer sent something that violates the protocol.
  protocolError,
}

class LanExchangeResult {
  final LanExchangeOutcome outcome;
  final bool requestWritten;
  final List<LanForwardingData> replies;
  final String? reason;

  const LanExchangeResult(
    this.outcome, {
    this.requestWritten = false,
    this.replies = const [],
    this.reason,
  });
}

/// What the device-management screen shows for a LAN destination.
enum LanReachability {
  notConfigured,
  unpaired,
  revoked,
  unreachable,
  authenticationFailed,
  reachable,
}

/// Outbound side used by [LanForwardingTransport]: the in-process service, or
/// a proxy to it from another isolate.
abstract class LanForwardingClient {
  Future<LanExchangeResult> exchange({
    required String recipientDeviceName,
    required Map<String, dynamic> data,
    required bool Function(LanForwardingData reply) isFinalReply,
    LanReplyProcessor? onReply,
  });

  Future<LanReachability> probe(String deviceName);
}

class LanForwardingService extends ChangeNotifier
    implements LanForwardingClient {
  static const int maxConnections = 8;
  static const Duration requestReadTimeout = Duration(seconds: 15);

  final LanPeerStore peers;
  final IdentityStore? identityStore;
  final Future<String> Function() ownDeviceName;
  final Future<String> Function() ownDeviceId;

  /// Private IPv4 addresses to listen on. Tests pass loopback.
  final Future<List<InternetAddress>> Function() listenAddresses;
  final int preferredPort;
  final Duration connectTimeout;
  final Duration replyTimeout;
  final Duration probeTimeout;
  final DateTime Function() clock;

  /// Runs every validated inbound request. Set at startup.
  LanInboundHandler? inboundHandler;

  /// Default processor for replies received by [exchange].
  LanReplyProcessor? replyProcessor;

  DeviceIdentity? _identity;
  IdentityStatus identityStatus = IdentityStatus.absent;
  String? identityProblem;

  final Map<String, ServerSocket> _servers = {};
  final Set<FrameConnection> _connections = {};
  int? _listenPort;
  String? listenerFailure;

  final InvitationHost invitations;
  PairingSession? pairing;
  String? pairingError;
  _PairingTarget? _inviteTarget;

  /// In-memory diagnostics only; never contains message bodies or secrets.
  final List<String> events = [];

  LanForwardingService({
    required this.peers,
    required this.ownDeviceName,
    required this.ownDeviceId,
    this.identityStore,
    Future<List<InternetAddress>> Function()? listenAddresses,
    this.preferredPort = defaultLanForwardingPort,
    this.connectTimeout = const Duration(seconds: 4),
    this.replyTimeout = const Duration(seconds: 20),
    this.probeTimeout = const Duration(seconds: 6),
    DateTime Function()? clock,
    DeviceIdentity? identity,
    this.inboundHandler,
    this.replyProcessor,
  })  : listenAddresses = listenAddresses ?? _privateAddresses,
        clock = clock ?? DateTime.now,
        invitations = InvitationHost(clock: clock) {
    if (identity != null) {
      _identity = identity;
      identityStatus = IdentityStatus.ready;
    }
  }

  /// The service of the main (UI) isolate, which owns the listener and the
  /// Keystore-protected identity. Null in every other isolate.
  static LanForwardingService? instance;

  static Future<List<InternetAddress>> _privateAddresses() async =>
      [for (final candidate in await listLanAddresses()) candidate.address];

  DeviceIdentity? get identity => _identity;
  bool get isListening => _servers.isNotEmpty;
  int? get listenPort => _listenPort;
  List<InternetAddress> get boundAddresses =>
      [for (final server in _servers.values) server.address];

  void _log(String text) {
    events.add('${clock().toIso8601String()} $text');
    if (events.length > 200) events.removeAt(0);
    debugPrint('LAN FORWARDING: $text');
  }

  // ---------------------------------------------------------------- identity

  /// Loads the identity. Creates one only on a genuinely fresh install, and
  /// only when [createIfAbsent] (the user started a pairing).
  Future<IdentityStatus> loadIdentity({bool createIfAbsent = false}) async {
    if (_identity != null) return identityStatus = IdentityStatus.ready;
    final store = identityStore;
    if (store == null) return identityStatus;
    final hasTrust = !(await peers.isEmpty);
    final result = await store.load(hasTrustRelationships: hasTrust);
    identityStatus = result.status;
    identityProblem = result.problem;
    if (result.status == IdentityStatus.ready) {
      _identity = result.identity;
    } else if (result.status == IdentityStatus.absent && createIfAbsent) {
      _identity = await store.create();
      identityStatus = IdentityStatus.ready;
      identityProblem = null;
      _log('LAN identity created (${_identity!.displayId})');
    }
    notifyListeners();
    return identityStatus;
  }

  /// Explicit, user-confirmed reset: deletes the identity and every pairing.
  Future<void> resetIdentity() async {
    pairing?.cancel();
    invitations.cancel();
    await stopListening();
    await peers.clear();
    await identityStore?.destroy();
    _identity = null;
    identityStatus = IdentityStatus.absent;
    identityProblem = null;
    _log('LAN identity and all pairings removed');
    notifyListeners();
  }

  // ---------------------------------------------------------------- listener

  /// Binds one listener per private IPv4 address (never all interfaces). The
  /// same port is used on every address; when it is taken, the next ports are
  /// tried. Does nothing without an identity.
  Future<void> startListening() async {
    if (_identity == null) return;
    final addresses = await listenAddresses();
    final wanted = {
      for (final address in addresses)
        if (isAllowedLanAddress(address)) address.address: address,
    };
    if (wanted.isEmpty) {
      listenerFailure = 'No private network address (join Wi-Fi or a hotspot).';
      if (_servers.isNotEmpty) await stopListening(reason: 'network lost');
      notifyListeners();
      return;
    }
    if (_servers.isNotEmpty &&
        setEquals(_servers.keys.toSet(), wanted.keys.toSet())) {
      return;
    }
    if (_servers.isNotEmpty) await stopListening(reason: 'network changed');
    final ports = [
      if (_listenPort != null) _listenPort!,
      for (var i = 0; i < lanForwardingPortAttempts; i++) preferredPort + i,
    ];
    Object? lastError;
    for (final port in ports.toSet()) {
      final bound = <String, ServerSocket>{};
      try {
        for (final entry in wanted.entries) {
          // Port 0 lets the OS choose; every other address then uses it.
          final target = bound.isEmpty ? port : bound.values.first.port;
          bound[entry.key] = await ServerSocket.bind(entry.value, target);
        }
      } catch (error) {
        lastError = error;
        for (final server in bound.values) {
          await server.close();
        }
        continue;
      }
      _listenPort = bound.values.first.port;
      _servers.addAll(bound);
      for (final server in bound.values) {
        server.listen(
          _accept,
          onError: (Object _) => _listenerLost(server),
          onDone: () => _listenerLost(server),
          cancelOnError: true,
        );
      }
      listenerFailure = null;
      _log('Listening on ${wanted.keys.join(', ')} port $_listenPort');
      notifyListeners();
      return;
    }
    listenerFailure = 'Could not open a LAN port '
        '(${categorizeSocketError(lastError ?? 'unknown').name}).';
    _log(listenerFailure!);
    notifyListeners();
  }

  void _listenerLost(ServerSocket server) {
    final key = server.address.address;
    if (!identical(_servers[key], server)) return; // stopped deliberately
    _servers.remove(key);
    listenerFailure = 'LAN listener on $key stopped (network change?).';
    _log(listenerFailure!);
    if (_servers.isEmpty) invitations.cancel();
    notifyListeners();
  }

  Future<void> stopListening({String reason = 'stopped'}) async {
    final servers = _servers.values.toList();
    _servers.clear();
    if (servers.isNotEmpty) invitations.cancel();
    for (final connection in _connections.toList()) {
      connection.close();
    }
    _connections.clear();
    for (final server in servers) {
      await server.close();
    }
    if (servers.isNotEmpty) _log('Listener stopped ($reason)');
    notifyListeners();
  }

  void _accept(Socket socket) {
    if (!isAllowedLanAddress(socket.remoteAddress) ||
        _connections.length >= maxConnections) {
      socket.destroy();
      return;
    }
    final connection = FrameConnection(socket);
    _connections.add(connection);
    connection.done.then((_) => _connections.remove(connection));
    unawaited(_serve(connection));
  }

  Future<HandshakeRefusal?> _authorize(
    HandshakeMode mode,
    Uint8List clientIdentity,
    Uint8List? token,
  ) async {
    final own = _identity;
    if (own == null || fingerprintOf(clientIdentity) == own.fingerprint) {
      return const HandshakeRefusal(HandshakeErrorCode.protocolError);
    }
    if (mode == HandshakeMode.pairing) {
      // The token is checked first so a refusal names the precise reason
      // (expired, used...). Without a chosen BSAT device no pairing is
      // accepted at all.
      final rejection = invitations.redeem(token);
      if (rejection != null) {
        return HandshakeRefusal(
            HandshakeErrorCode.invitationInvalid, rejection.wire);
      }
      if (_inviteTarget == null) {
        return const HandshakeRefusal(
          HandshakeErrorCode.invitationInvalid,
          'no_invitation',
        );
      }
      return null;
    }
    if (await peers.isTrustedKey(clientIdentity)) return null;
    final known = await peers.byFingerprint(fingerprintOf(clientIdentity));
    return HandshakeRefusal(
      HandshakeErrorCode.untrustedPeer,
      known == null ? 'not_paired' : 'revoked',
    );
  }

  Future<void> _serve(FrameConnection connection) async {
    final own = _identity;
    if (own == null) {
      connection.close();
      return;
    }
    final SecureSession session;
    final started = Stopwatch()..start();
    try {
      final first = await connection.next(timeout: handshakeTimeout);
      Map<String, Object?>? hello;
      try {
        hello = decodeJsonObject(first);
      } on ProtocolException {
        hello = null;
      }
      if (hello == null ||
          hello['version'] != secureProtocolVersion ||
          hello['type'] != SecureTypes.hello) {
        connection.sendJson(plaintextRefusal());
        await connection.flush();
        connection.close();
        return;
      }
      session = await serverHandshake(
        connection: connection,
        firstFrame: first,
        identity: own,
        nickname: await ownDeviceName(),
        authorize: _authorize,
      );
    } catch (error) {
      _log('Refused ${connection.remoteAddress}: '
          '${error is HandshakeException ? error.summary : error.runtimeType} '
          'after ${started.elapsedMilliseconds} ms');
      connection.close();
      return;
    }
    _log('Handshake (${session.mode.name}) with ${connection.remoteAddress} '
        'completed in ${started.elapsedMilliseconds} ms');

    if (session.mode == HandshakeMode.pairing) {
      _onIncomingPairing(session);
      return;
    }

    try {
      final record = await session.receive(timeout: requestReadTimeout);
      // Trust may have been revoked between the handshake and this record.
      final peer = await peers.byFingerprint(session.peerFingerprint);
      if (peer == null ||
          !peer.isTrusted ||
          !(await peers.isTrustedKey(session.peerPublicKey))) {
        return;
      }
      switch (record['type']) {
        case LanEnvelopeTypes.probe:
          await peers.recordConnection(
            peer.fingerprint,
            connection.remoteAddress,
            port: _validPort(record['listenPort']),
          );
          await session.send({
            'type': LanEnvelopeTypes.probeOk,
            'listenPort': _listenPort,
          });
          await connection.flush();
        case LanEnvelopeTypes.request:
          await _handleRequest(session, peer, record);
        default:
          _log('Unexpected record from ${peer.deviceName}; session closed');
      }
    } catch (error) {
      if (error is! TimeoutException) {
        _log('Session ended: ${error.runtimeType}');
      }
    } finally {
      session.close();
    }
  }

  Future<void> _handleRequest(
    SecureSession session,
    LanPeer peer,
    Map<String, Object?> record,
  ) async {
    final requestId = record['requestId'];
    if (!isValidLanRequestId(requestId)) {
      _log('Malformed request from ${peer.deviceName}; session closed');
      return;
    }
    Future<void> done(String outcome, [String? reason]) async {
      try {
        await session.send({
          'type': LanEnvelopeTypes.done,
          'requestId': requestId,
          'outcome': outcome,
          if (reason != null) 'reason': reason,
        });
        await session.connection.flush();
      } catch (_) {}
    }

    final LanForwardingData message;
    try {
      message = validateLanForwardingData(
        record['data'],
        allowed: lanRequestKinds,
        authenticatedPeerDeviceName: peer.deviceName,
        ownDeviceName: await ownDeviceName(),
      );
    } on LanMessageException catch (error) {
      _log('Refused request from ${peer.deviceName}: ${error.reason}');
      await done('rejected', error.reason);
      return;
    }
    await peers.recordConnection(
      peer.fingerprint,
      session.connection.remoteAddress,
      port: _validPort(record['listenPort']),
    );
    final handler = inboundHandler;
    if (handler == null) {
      await done('rejected', LanRejectReasons.handlerUnavailable);
      return;
    }
    _log('${message.kind.name} job=${message.forwardingJobId} '
        'from ${peer.deviceName}');
    Future<void> reply(Map<String, dynamic> postBody) async {
      final data = postBody['data'];
      if (data is! Map || session.isClosed) return;
      try {
        await session.send({
          'type': LanEnvelopeTypes.reply,
          'requestId': requestId,
          'data': Map<String, Object?>.from(data),
        });
        await session.connection.flush();
      } catch (_) {
        // The client may already have its answer and have closed.
      }
    }

    try {
      await handler(message, peer, reply);
      await done('handled');
    } catch (error) {
      _log('Handler failed for job=${message.forwardingJobId}: '
          '${error.runtimeType}');
      await done('rejected', LanRejectReasons.handlerFailed);
    }
  }

  static int? _validPort(Object? value) =>
      value is int && value > 0 && value <= 65535 ? value : null;

  // ---------------------------------------------------------------- outbound

  Future<({SecureSession? session, LanPeer? peer, LanExchangeResult? failure})>
      _open(String deviceName) async {
    final own = _identity;
    if (own == null) {
      return (
        session: null,
        peer: null,
        failure: const LanExchangeResult(LanExchangeOutcome.notConfigured),
      );
    }
    final lookup = await peers.lookupDevice(deviceName);
    final peer = lookup.peer;
    switch (lookup.state) {
      case LanPeerLookupState.trusted:
        break;
      case LanPeerLookupState.unpaired:
        return (
          session: null,
          peer: null,
          failure: const LanExchangeResult(LanExchangeOutcome.unpaired),
        );
      case LanPeerLookupState.revoked:
        return (
          session: null,
          peer: null,
          failure: const LanExchangeResult(LanExchangeOutcome.revoked),
        );
      case LanPeerLookupState.unavailable:
        return (
          session: null,
          peer: null,
          failure: const LanExchangeResult(
            LanExchangeOutcome.unpaired,
            reason: 'pairing record unavailable',
          ),
        );
    }
    final address = InternetAddress.tryParse(peer?.lastAddress ?? '');
    final port = peer?.lastPort;
    if (peer == null ||
        address == null ||
        !isAllowedLanAddress(address) ||
        port == null) {
      return (
        session: null,
        peer: peer,
        failure: const LanExchangeResult(
          LanExchangeOutcome.unreachable,
          reason: 'no known address',
        ),
      );
    }
    final Socket socket;
    try {
      socket = await Socket.connect(address, port, timeout: connectTimeout);
    } catch (error) {
      return (
        session: null,
        peer: peer,
        failure: LanExchangeResult(
          LanExchangeOutcome.unreachable,
          reason: categorizeSocketError(error).name,
        ),
      );
    }
    final connection = FrameConnection(socket);
    try {
      final session = await clientHandshake(
        connection: connection,
        identity: own,
        nickname: await ownDeviceName(),
        mode: HandshakeMode.session,
        acceptServer: (serverIdentity) async {
          if (fingerprintOf(serverIdentity) != peer.fingerprint) {
            return HandshakeErrorCode.identityMismatch;
          }
          if (!await peers.isTrustedKey(serverIdentity)) {
            return HandshakeErrorCode.untrustedPeer;
          }
          return null;
        },
      );
      return (session: session, peer: peer, failure: null);
    } on HandshakeException catch (error) {
      connection.close();
      return (
        session: null,
        peer: peer,
        failure: LanExchangeResult(
          error.code == HandshakeErrorCode.timeout
              ? LanExchangeOutcome.unreachable
              : LanExchangeOutcome.authenticationFailed,
          reason: error.summary,
        ),
      );
    } catch (error) {
      connection.close();
      return (
        session: null,
        peer: peer,
        failure: LanExchangeResult(
          LanExchangeOutcome.unreachable,
          reason: error.runtimeType.toString(),
        ),
      );
    }
  }

  @override
  Future<LanExchangeResult> exchange({
    required String recipientDeviceName,
    required Map<String, dynamic> data,
    required bool Function(LanForwardingData reply) isFinalReply,
    LanReplyProcessor? onReply,
  }) async {
    final requestKind = lanMessageKindOf(data);
    if (requestKind == null || !lanRequestKinds.contains(requestKind)) {
      return const LanExchangeResult(
        LanExchangeOutcome.refused,
        reason: LanRejectReasons.unsupportedType,
      );
    }
    final opened = await _open(recipientDeviceName);
    final failure = opened.failure;
    if (failure != null) {
      _log('No session with $recipientDeviceName: ${failure.outcome.name}'
          '${failure.reason == null ? '' : ' (${failure.reason})'}');
      return failure;
    }
    final session = opened.session!;
    final peer = opened.peer!;
    final requestId = newLanRequestId();
    final replies = <LanForwardingData>[];
    final processor = onReply ?? replyProcessor;
    final expectsReply = lanReplyKindsFor(requestKind).isNotEmpty;
    var written = false;
    try {
      await session.send({
        'type': LanEnvelopeTypes.request,
        'requestId': requestId,
        'listenPort': _listenPort,
        'data': data,
      });
      written = true;
      await peers.recordConnection(
        peer.fingerprint,
        session.connection.remoteAddress,
        port: session.connection.remotePort,
      );
      final deadline = clock().add(replyTimeout);
      final own = await ownDeviceName();
      while (true) {
        final remaining = deadline.difference(clock());
        if (remaining <= Duration.zero) throw TimeoutException('reply');
        final record = await session.receive(timeout: remaining);
        if (record['requestId'] != requestId) {
          return LanExchangeResult(LanExchangeOutcome.protocolError,
              requestWritten: true, replies: replies, reason: 'request ID');
        }
        switch (record['type']) {
          case LanEnvelopeTypes.reply:
            final LanForwardingData reply;
            try {
              reply = validateLanForwardingData(
                record['data'],
                allowed: lanReplyKindsFor(requestKind),
                authenticatedPeerDeviceName: peer.deviceName,
                ownDeviceName: own,
              );
            } on LanMessageException catch (error) {
              _log('Invalid reply from ${peer.deviceName}: ${error.reason}');
              return LanExchangeResult(LanExchangeOutcome.protocolError,
                  requestWritten: true, replies: replies, reason: error.reason);
            }
            replies.add(reply);
            if (processor != null) await processor(reply, peer);
            if (isFinalReply(reply)) {
              return LanExchangeResult(LanExchangeOutcome.completed,
                  requestWritten: true, replies: replies);
            }
          case LanEnvelopeTypes.done:
            final outcome = record['outcome'];
            final reason = record['reason'];
            if (outcome == 'handled') {
              return LanExchangeResult(
                expectsReply
                    ? LanExchangeOutcome.noReply
                    : LanExchangeOutcome.completed,
                requestWritten: true,
                replies: replies,
              );
            }
            return LanExchangeResult(LanExchangeOutcome.refused,
                requestWritten: true,
                replies: replies,
                reason: reason is String && reason.length <= 64 ? reason : null);
          default:
            return LanExchangeResult(LanExchangeOutcome.protocolError,
                requestWritten: true, replies: replies, reason: 'record type');
        }
      }
    } on TimeoutException {
      return LanExchangeResult(LanExchangeOutcome.deliveryUnknown,
          requestWritten: written, replies: replies, reason: 'timeout');
    } on RecordException catch (error) {
      return LanExchangeResult(LanExchangeOutcome.protocolError,
          requestWritten: written, replies: replies, reason: error.detail);
    } catch (error) {
      return LanExchangeResult(
        written
            ? LanExchangeOutcome.deliveryUnknown
            : LanExchangeOutcome.unreachable,
        requestWritten: written,
        replies: replies,
        reason: error.runtimeType.toString(),
      );
    } finally {
      session.close();
    }
  }

  @override
  Future<LanReachability> probe(String deviceName) async {
    final result = await _probe(deviceName).timeout(
      probeTimeout + handshakeTimeout,
      onTimeout: () => LanReachability.unreachable,
    );
    notifyListeners();
    return result;
  }

  Future<LanReachability> _probe(String deviceName) async {
    final opened = await _open(deviceName);
    final failure = opened.failure;
    if (failure != null) {
      return switch (failure.outcome) {
        LanExchangeOutcome.notConfigured => LanReachability.notConfigured,
        LanExchangeOutcome.unpaired => LanReachability.unpaired,
        LanExchangeOutcome.revoked => LanReachability.revoked,
        LanExchangeOutcome.authenticationFailed =>
          LanReachability.authenticationFailed,
        _ => LanReachability.unreachable,
      };
    }
    final session = opened.session!;
    try {
      await session.send({
        'type': LanEnvelopeTypes.probe,
        'listenPort': _listenPort,
      });
      final reply = await session.receive(timeout: probeTimeout);
      if (reply['type'] != LanEnvelopeTypes.probeOk) {
        return LanReachability.unreachable;
      }
      await peers.recordConnection(
        opened.peer!.fingerprint,
        session.connection.remoteAddress,
        port: session.connection.remotePort,
      );
      return LanReachability.reachable;
    } catch (_) {
      return LanReachability.unreachable;
    } finally {
      session.close();
    }
  }

  // ---------------------------------------------------------------- pairing

  Future<LanPeerIdentity> _localIdentity() async => LanPeerIdentity(
        deviceName: await ownDeviceName(),
        deviceId: await ownDeviceId(),
        listenPort: _listenPort,
      );

  /// Inviter side: shows a one-time invitation for [expectedDeviceName].
  /// Creates the identity if needed and starts the listener.
  Future<PairingInvitation> createInvitation({
    required String expectedDeviceName,
    required String expectedDeviceId,
  }) async {
    await loadIdentity(createIfAbsent: true);
    final own = _identity;
    if (own == null) {
      throw StateError(identityProblem ?? 'LAN identity unavailable.');
    }
    await startListening();
    final port = _listenPort;
    if (_servers.isEmpty || port == null) {
      throw StateError(listenerFailure ?? 'LAN listener is not running.');
    }
    pairing?.cancel();
    pairing = null;
    pairingError = null;
    _inviteTarget = _PairingTarget(expectedDeviceName, expectedDeviceId);
    final invitation = invitations.create(
      host: _servers.values.first.address,
      port: port,
      ownFingerprint: own.fingerprint,
    );
    _log('Pairing invitation created for $expectedDeviceName '
        '(valid ${invitationLifetime.inMinutes} min)');
    notifyListeners();
    return invitation;
  }

  void cancelInvitation() {
    invitations.cancel();
    _inviteTarget = null;
    pairing?.cancel();
    notifyListeners();
  }

  void _onIncomingPairing(SecureSession session) {
    final target = _inviteTarget;
    if (target == null) {
      session.close();
      return;
    }
    pairing?.cancel();
    _localIdentity().then((local) {
      pairing = _newPairing(
        session,
        local: local,
        target: target,
        address: session.connection.remoteAddress,
        port: null,
      );
      notifyListeners();
    });
  }

  /// Joiner side: connects with an invitation for [expectedDeviceName].
  /// [scanned] selects the strict parser for camera input. Trust is saved
  /// only after both users confirm and the peer proved it is that device.
  Future<void> joinWithInvitation(
    String code, {
    required String expectedDeviceName,
    required String expectedDeviceId,
    bool scanned = false,
  }) async {
    pairing?.cancel();
    pairing = null;
    pairingError = null;
    notifyListeners();
    final PairingInvitation invitation;
    try {
      invitation = scanned
          ? PairingInvitation.parseScanned(code)
          : PairingInvitation.parse(code);
    } on FormatException catch (error) {
      // The input itself is never logged: it contains the one-time token.
      pairingError = error.message;
      notifyListeners();
      return;
    }
    await loadIdentity(createIfAbsent: true);
    final own = _identity;
    if (own == null) {
      pairingError = identityProblem ?? 'LAN identity unavailable.';
      notifyListeners();
      return;
    }
    // The peer replies to this device over LAN, so listen before pairing.
    await startListening();
    FrameConnection? connection;
    final started = Stopwatch()..start();
    try {
      final socket = await Socket.connect(
        invitation.host,
        invitation.port,
        timeout: connectTimeout,
      );
      _log('Connected to ${invitation.host.address}:${invitation.port} in '
          '${started.elapsedMilliseconds} ms');
      connection = FrameConnection(socket);
      final session = await clientHandshake(
        connection: connection,
        identity: own,
        nickname: await ownDeviceName(),
        mode: HandshakeMode.pairing,
        pairingToken: invitation.token,
        acceptServer: (serverIdentity) => invitation.matchesServer(serverIdentity)
            ? null
            : HandshakeErrorCode.identityMismatch,
      );
      _log('Pairing handshake completed in ${started.elapsedMilliseconds} ms');
      pairing = _newPairing(
        session,
        local: await _localIdentity(),
        target: _PairingTarget(expectedDeviceName, expectedDeviceId),
        address: invitation.host.address,
        port: invitation.port,
      );
    } on HandshakeException catch (error) {
      connection?.close();
      _log('Pairing handshake failed (${error.summary}) after '
          '${started.elapsedMilliseconds} ms');
      pairingError = describeJoinFailure(error);
    } catch (error) {
      connection?.close();
      _log('Pairing connection failed (${error.runtimeType}) after '
          '${started.elapsedMilliseconds} ms');
      pairingError = describeConnectError(error);
    }
    notifyListeners();
  }

  PairingSession _newPairing(
    SecureSession session, {
    required LanPeerIdentity local,
    required _PairingTarget target,
    required String address,
    required int? port,
  }) {
    return PairingSession(
      session: session,
      localIdentity: local,
      validatePeer: (peer) => target.refusalFor(peer),
      saveTrust: (pairing) async {
        final peer = pairing.peerIdentity!;
        await peers.trust(
          publicKey: session.peerPublicKey,
          deviceName: target.deviceName,
          deviceId: target.deviceId.isNotEmpty ? target.deviceId : peer.deviceId,
          address: address,
          port: peer.listenPort ?? port,
        );
        if (identical(_inviteTarget, target)) _inviteTarget = null;
        _log('Paired with ${target.deviceName} '
            '(${displayFingerprint(session.peerFingerprint)})');
      },
      onChanged: notifyListeners,
    );
  }

  void resetFinishedPairing() {
    final current = pairing;
    if (current != null && !current.isFinished) return;
    pairing = null;
    pairingError = null;
    notifyListeners();
  }

  /// Ends the invitation and any pairing that is not finished, and clears
  /// the result: opening or leaving the pairing screen never carries a
  /// pairing over to another device's screen. A pairing whose trust is being
  /// saved (both users confirmed) still completes.
  void abandonPairing() {
    invitations.cancel();
    _inviteTarget = null;
    pairing?.cancel();
    pairing = null;
    pairingError = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------- trust

  /// Revokes the pairing for [fingerprint]: every later session with that key
  /// is refused, whatever address or name it uses. Re-trusting needs a new
  /// pairing.
  Future<void> revoke(String fingerprint) async {
    await peers.revoke(fingerprint);
    if (pairing?.peerFingerprint == fingerprint) pairing?.cancel();
    _log('Revoked ${displayFingerprint(fingerprint)}');
    notifyListeners();
  }

  /// Deletes the pairing record for [fingerprint].
  Future<void> remove(String fingerprint) async {
    await peers.remove(fingerprint);
    if (pairing?.peerFingerprint == fingerprint) pairing?.cancel();
    _log('Removed ${displayFingerprint(fingerprint)}');
    notifyListeners();
  }

  @override
  void dispose() {
    pairing?.cancel();
    unawaited(stopListening());
    super.dispose();
  }
}

class _PairingTarget {
  final String deviceName;
  final String deviceId;

  _PairingTarget(this.deviceName, this.deviceId);

  /// The peer must be the BSAT device the user chose to pair with.
  String? refusalFor(LanPeerIdentity peer) {
    if (peer.deviceName != deviceName) {
      return 'The other phone is "${peer.deviceName}", not "$deviceName". '
          'Nothing was saved.';
    }
    if (deviceId.isNotEmpty &&
        peer.deviceId.isNotEmpty &&
        peer.deviceId != deviceId) {
      return 'The other phone\'s BSAT device ID does not match "$deviceName". '
          'Nothing was saved.';
    }
    return null;
  }
}

/// The Android Keystore-backed identity store in the app's no-backup
/// directory. Throws [KeyWrapperException] off Android.
Future<IdentityStore> androidLanIdentityStore() async {
  final base = await AndroidKeystoreKeyWrapper.noBackupDirectory();
  final directory = Directory('${base.path}/bsat_lan');
  await directory.create(recursive: true);
  return IdentityStore(
    directory: directory,
    wrapper: AndroidKeystoreKeyWrapper(),
  );
}
