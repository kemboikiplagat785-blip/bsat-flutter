import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/dart.dart';

import 'lan_crypto_util.dart';
import 'lan_device_identity.dart';
import 'lan_net_util.dart';
import 'lan_secure_session.dart';
import 'lan_atomic_file.dart';

/// Ported from the BSAT Local Lab prototype (lib/src/pairing/pairing.dart).
/// Changes: QR prefix and checksum label are BSAT-specific, and the
/// confirmation step also exchanges and checks the BSAT device identity.
///
/// Pairing invitation (25 bytes, shown as 40 base32 characters):
///   ipv4[4] | port[2, BE] | token[10] | fingerprintPrefix[8] | check[1]
/// check = first byte of SHA-256("BSAT-LAN-PAIR-V1" || preceding 24 bytes).
///
/// The token is a one-time, 5-minute pairing credential (80 bits). The
/// fingerprint prefix (64 bits) lets the joiner verify it reached the device
/// that displayed the invitation. Neither is a long-lived secret; no private
/// key material is included.
const String invitationQrPrefix = 'BSATLAN:PAIR:1:';
const String _labQrScheme = 'BSATLAN:';
const String _pairQrPrefix = 'BSATLAN:PAIR:';
const Duration invitationLifetime = Duration(minutes: 5);
const Duration confirmationTimeout = Duration(minutes: 2);
const int maxInvitationFailures = 5;

/// Upper bound on accepted invitation text, checked before any decoding.
/// The canonical QR text is 55 characters; the grouped code 49.
const int maxInvitationTextLength = 128;
const int _codeSymbols = 40;

enum InvitationProblem {
  tooLong,
  notAnInvitation,
  unsupportedVersion,
  invalidCharacters,
  wrongLength,
  checksum,
  notPrivateAddress,
  invalidPort,
}

/// A rejected invitation text. [message] is user-readable and never echoes
/// the input.
class InvitationFormatException extends FormatException {
  final InvitationProblem problem;

  const InvitationFormatException(this.problem, String message)
    : super(message);
}

class PairingInvitation {
  final InternetAddress host;
  final int port;
  final Uint8List token;
  final Uint8List fingerprintPrefix;

  PairingInvitation({
    required this.host,
    required this.port,
    required this.token,
    required this.fingerprintPrefix,
  });

  Uint8List toBytes() {
    final bytes = Uint8List(25);
    bytes.setRange(0, 4, host.rawAddress);
    ByteData.sublistView(bytes).setUint16(4, port, Endian.big);
    bytes.setRange(6, 16, token);
    bytes.setRange(16, 24, fingerprintPrefix);
    bytes[24] = _check(bytes.sublist(0, 24));
    return bytes;
  }

  /// Manual-entry form: 10 groups of 4 characters.
  String get code {
    final raw = base32Encode(toBytes());
    return [for (var i = 0; i < raw.length; i += 4) raw.substring(i, i + 4)]
        .join('-');
  }

  String get qrText => '$invitationQrPrefix${base32Encode(toBytes())}';

  /// Parses either the QR text or the typed code. Separators (hyphens,
  /// spaces) and letter case are presentation only and are ignored, as are
  /// the look-alike digits 0/1/8 (read as O/I/B). Everything else must be
  /// exact: 40 base32 symbols, a matching checksum, a private address.
  /// Throws [InvitationFormatException].
  static PairingInvitation parse(String text) {
    if (text.length > maxInvitationTextLength) {
      throw const InvitationFormatException(
        InvitationProblem.tooLong,
        'The pairing code is too long.',
      );
    }
    var cleaned = text.trim();
    final upper = cleaned.toUpperCase();
    if (upper.startsWith(_labQrScheme)) {
      if (!upper.startsWith(invitationQrPrefix)) {
        throw upper.startsWith(_pairQrPrefix)
            ? const InvitationFormatException(
                InvitationProblem.unsupportedVersion,
                'This invitation uses an unsupported invitation version. '
                'Update BSAT on both phones.',
              )
            : const InvitationFormatException(
                InvitationProblem.notAnInvitation,
                'This is not a pairing invitation.',
              );
      }
      cleaned = cleaned.substring(invitationQrPrefix.length);
    }
    final symbols = cleaned.toUpperCase().replaceAll(RegExp(r'[\s\-]'), '');
    if (!RegExp(r'^[A-Z2-7018]*$').hasMatch(symbols)) {
      throw const InvitationFormatException(
        InvitationProblem.invalidCharacters,
        'The pairing code contains invalid characters.',
      );
    }
    if (symbols.length != _codeSymbols) {
      throw InvitationFormatException(
        InvitationProblem.wrongLength,
        'The pairing code has ${symbols.length} characters; it must have '
        '$_codeSymbols (${symbols.length < _codeSymbols ? 'incomplete' : 'extra characters'}).',
      );
    }
    final bytes = base32Decode(symbols);
    if (bytes[24] != _check(bytes.sublist(0, 24))) {
      throw const InvitationFormatException(
        InvitationProblem.checksum,
        'The pairing code checksum is wrong (typo?).',
      );
    }
    final host = InternetAddress.fromRawAddress(bytes.sublist(0, 4));
    if (!isAllowedLanAddress(host)) {
      throw const InvitationFormatException(
        InvitationProblem.notPrivateAddress,
        'The pairing code does not contain a private local address.',
      );
    }
    final port = ByteData.sublistView(bytes).getUint16(4, Endian.big);
    if (port == 0) {
      throw const InvitationFormatException(
        InvitationProblem.invalidPort,
        'Invalid port.',
      );
    }
    return PairingInvitation(
      host: host,
      port: port,
      token: Uint8List.fromList(bytes.sublist(6, 16)),
      fingerprintPrefix: Uint8List.fromList(bytes.sublist(16, 24)),
    );
  }

  /// Strict form for camera scans: the payload must be exactly the canonical
  /// QR text this app displays ([qrText]); no separators, case changes or
  /// surrounding text. A QR code that is not a BSAT LAN pairing invitation is
  /// rejected without being interpreted.
  static PairingInvitation parseScanned(String text) {
    if (text.length > maxInvitationTextLength) {
      throw const InvitationFormatException(
        InvitationProblem.tooLong,
        'The QR code holds too much data.',
      );
    }
    if (!text.startsWith(_labQrScheme)) {
      throw const InvitationFormatException(
        InvitationProblem.notAnInvitation,
        'This QR code is not a BSAT LAN pairing invitation.',
      );
    }
    if (text.startsWith(invitationQrPrefix) &&
        !RegExp(r'^[A-Z2-7]{40}$')
            .hasMatch(text.substring(invitationQrPrefix.length))) {
      throw const InvitationFormatException(
        InvitationProblem.wrongLength,
        'The QR code is damaged or incomplete. Scan it again.',
      );
    }
    return parse(text);
  }

  bool matchesServer(List<int> serverIdentity) => constantTimeEquals(
    fingerprintBytes(serverIdentity).sublist(0, 8),
    fingerprintPrefix,
  );

  static int _check(List<int> data) => const DartSha256().hashSync([
    ...utf8.encode('BSAT-LAN-PAIR-V1'),
    ...data,
  ]).bytes[0];
}

enum InvitationState { active, consumed, cancelled, expired, locked }

/// Why a pairing attempt's invitation was refused. [wire] travels to the
/// joiner as the handshake refusal reason; it carries no secret.
enum InvitationRejection {
  /// No invitation is active (never created, or the app restarted).
  noInvitation('no_invitation'),
  expired('expired'),

  /// Single use: this invitation was already redeemed.
  used('used'),

  /// Cancelled on the inviting phone (e.g. its invite screen was closed).
  cancelled('cancelled'),

  /// A newer invitation was created after this one.
  replaced('replaced'),

  /// Disabled after [maxInvitationFailures] wrong codes.
  locked('locked'),

  /// Not the token of the current or any recent invitation.
  wrongCode('wrong_code');

  final String wire;
  const InvitationRejection(this.wire);

  static InvitationRejection? fromWire(String? wire) {
    for (final value in values) {
      if (value.wire == wire) return value;
    }
    return null;
  }
}

class _RetiredInvitation {
  final Uint8List tokenHash;
  final InvitationRejection reason;

  _RetiredInvitation(this.tokenHash, this.reason);
}

/// The inviter's single active invitation. Tokens are compared by hash in
/// constant time and are single-use.
///
/// The hashes of the last few retired invitations are kept in memory only
/// to explain a refusal precisely (e.g. "already used" rather than "wrong
/// code"). A retired token is never accepted, and presenting one does not
/// count towards the wrong-code lock, since it is not a guess at the
/// current token.
class InvitationHost {
  static const int retiredKept = 8;

  final DateTime Function() clock;
  PairingInvitation? _invitation;
  Uint8List? _tokenHash;
  DateTime? _expiresAt;
  InvitationState _state = InvitationState.cancelled;
  int _failures = 0;
  final List<_RetiredInvitation> _retired = [];

  /// The reason for the most recent refusal, for diagnostics.
  InvitationRejection? lastRejection;

  InvitationHost({DateTime Function()? clock}) : clock = clock ?? DateTime.now;

  PairingInvitation? get invitation =>
      state == InvitationState.active ? _invitation : null;
  DateTime? get expiresAt => _expiresAt;

  InvitationState get state {
    if (_state == InvitationState.active &&
        _expiresAt != null &&
        !clock().isBefore(_expiresAt!)) {
      _state = InvitationState.expired;
    }
    return _state;
  }

  PairingInvitation create({
    required InternetAddress host,
    required int port,
    required String ownFingerprint,
  }) {
    final previous = state;
    _retire(
      previous == InvitationState.active
          ? InvitationRejection.replaced
          : _rejectionFor(previous),
    );
    final token = secureRandomBytes(10);
    final invitation = PairingInvitation(
      host: host,
      port: port,
      token: token,
      fingerprintPrefix: hexDecode(ownFingerprint).sublist(0, 8),
    );
    _invitation = invitation;
    _tokenHash = _hash(token);
    _expiresAt = clock().add(invitationLifetime);
    _state = InvitationState.active;
    _failures = 0;
    return invitation;
  }

  void cancel() {
    if (state == InvitationState.active) _state = InvitationState.cancelled;
    _retire(_rejectionFor(_state));
  }

  /// Consumes the invitation if [token] is correct and it is still active.
  /// A wrong token counts towards [maxInvitationFailures].
  HandshakeErrorCode? consume(Uint8List? token) =>
      redeem(token) == null ? null : HandshakeErrorCode.invitationInvalid;

  /// Like [consume], returning why the token was refused (null: accepted).
  InvitationRejection? redeem(Uint8List? token) =>
      lastRejection = _redeem(token);

  InvitationRejection? _redeem(Uint8List? token) {
    final current = state;
    if (token == null) {
      return current == InvitationState.active
          ? InvitationRejection.wrongCode
          : InvitationRejection.noInvitation;
    }
    final hash = _hash(token);
    final currentHash = _tokenHash;
    if (currentHash != null && constantTimeEquals(hash, currentHash)) {
      if (current != InvitationState.active) return _rejectionFor(current);
      _state = InvitationState.consumed;
      _retire(InvitationRejection.used);
      return null;
    }
    for (final retired in _retired.reversed) {
      if (constantTimeEquals(hash, retired.tokenHash)) return retired.reason;
    }
    if (current != InvitationState.active) {
      return InvitationRejection.noInvitation;
    }
    _failures++;
    if (_failures >= maxInvitationFailures) {
      _state = InvitationState.locked;
      _retire(InvitationRejection.locked);
    }
    return InvitationRejection.wrongCode;
  }

  static InvitationRejection _rejectionFor(InvitationState state) =>
      switch (state) {
        InvitationState.active => InvitationRejection.replaced,
        InvitationState.consumed => InvitationRejection.used,
        InvitationState.cancelled => InvitationRejection.cancelled,
        InvitationState.expired => InvitationRejection.expired,
        InvitationState.locked => InvitationRejection.locked,
      };

  /// Moves the current token hash to the retired list; it can never be
  /// accepted again.
  void _retire(InvitationRejection reason) {
    final hash = _tokenHash;
    if (hash == null) return;
    _tokenHash = null;
    _retired.add(_RetiredInvitation(hash, reason));
    if (_retired.length > retiredKept) _retired.removeAt(0);
  }

  static Uint8List _hash(List<int> token) => Uint8List.fromList(
    const DartSha256().hashSync([...utf8.encode('pair-token'), ...token]).bytes,
  );
}

/// What the joining user is told when the pairing handshake is refused.
String describeJoinFailure(HandshakeException error) => switch (error.code) {
  HandshakeErrorCode.invitationInvalid => switch (InvitationRejection.fromWire(
    error.reason,
  )) {
    InvitationRejection.expired =>
      'Invitation expired (invitations last '
          '${invitationLifetime.inMinutes} minutes). Create a new one '
          'on the other phone.',
    InvitationRejection.used =>
      'Invitation already used. Each invitation works once: create a '
          'new one on the other phone.',
    InvitationRejection.cancelled =>
      'Invitation cancelled on the other phone (its invite screen was '
          'closed). Create a new one.',
    InvitationRejection.replaced =>
      'This is an older invitation: the other phone has created a '
          'newer one since. Scan the code it shows now.',
    InvitationRejection.locked =>
      'The other phone disabled this invitation after too many wrong '
          'codes. Create a new one.',
    InvitationRejection.noInvitation =>
      'The other phone has no active invitation (it may have '
          'restarted or closed the invite screen). Create a new one.',
    InvitationRejection.wrongCode =>
      'The code does not match the invitation shown on the other '
          'phone (an old or mistyped code?). Scan the code it shows '
          'now.',
    null =>
      'The invitation is expired, cancelled or already used. '
          'Create a new one on the other phone.',
  },
  HandshakeErrorCode.identityMismatch =>
    'Identity mismatch: the device at that address is not the one that '
        'created the invitation.',
  HandshakeErrorCode.incompatibleProtocol =>
    'The other device runs an older, insecure version.',
  HandshakeErrorCode.timeout =>
    'The secure handshake timed out: something accepted the connection '
        'but the other phone did not answer. On the phone showing the QR, '
        'keep BSAT open with the screen on and check that the address under '
        'the QR matches its Wi-Fi IP address. Turn off VPN on both phones, '
        'make sure both are on the same Wi-Fi or hotspot, then create a new '
        'QR and try again.',
  HandshakeErrorCode.authenticationFailed =>
    'Authentication failed: ${error.detail}',
  HandshakeErrorCode.untrustedPeer || HandshakeErrorCode.protocolError =>
    'Pairing handshake failed (${error.summary}).',
};

enum PairingPhase {
  /// Waiting for both users to compare the code and confirm.
  awaitingConfirmation,

  /// This user confirmed; waiting for the peer's confirmation.
  waitingForPeer,

  /// Both confirmed and the peer is now trusted locally.
  completed,

  rejectedLocally,
  rejectedByPeer,
  cancelled,
  failed,
}

/// The BSAT device a pairing peer says it is, sent inside the authenticated,
/// encrypted pairing session. It is a claim bound to the peer's key; the user
/// chose which BSAT device to pair with, and [PairingSession.validatePeer]
/// refuses any other one before trust can be confirmed.
class LanPeerIdentity {
  final String deviceName;
  final String deviceId;

  /// The peer's LAN listening port, a routing hint only.
  final int? listenPort;

  const LanPeerIdentity({
    required this.deviceName,
    required this.deviceId,
    this.listenPort,
  });

  static const int maxNameChars = 100;

  Map<String, Object?> toJson() => {
        'type': 'pair_identity',
        'deviceName': deviceName,
        'deviceId': deviceId,
        if (listenPort != null) 'listenPort': listenPort,
      };

  /// Null when [json] is not a well-formed identity message.
  static LanPeerIdentity? fromJson(Map<String, Object?> json) {
    final name = json['deviceName'];
    final id = json['deviceId'];
    final port = json['listenPort'];
    if (name is! String ||
        name.trim().isEmpty ||
        name.length > maxNameChars ||
        name.contains(RegExp(r'[\x00-\x1f]'))) {
      return null;
    }
    if (id is! String || id.length > maxNameChars) return null;
    if (port != null && (port is! int || port < 1 || port > 65535)) {
      return null;
    }
    return LanPeerIdentity(
      deviceName: name.trim(),
      deviceId: id.trim(),
      listenPort: port as int?,
    );
  }
}

/// The confirmation step of an authenticated pairing session. Both sides
/// first exchange their BSAT identity ([LanPeerIdentity]). Trust is written
/// only after the peer's identity was accepted by [validatePeer], the local
/// user confirmed the code, AND the peer's confirmation arrived over the
/// authenticated session.
class PairingSession {
  final SecureSession session;
  final LanPeerIdentity localIdentity;

  /// Returns a user-readable refusal, or null to accept the peer.
  final FutureOr<String?> Function(LanPeerIdentity peer) validatePeer;
  final Future<void> Function(PairingSession) saveTrust;
  final void Function() onChanged;
  PairingPhase phase = PairingPhase.awaitingConfirmation;
  String? failure;
  LanPeerIdentity? peerIdentity;
  bool _localConfirmed = false;
  bool _remoteConfirmed = false;
  Timer? _timeout;

  PairingSession({
    required this.session,
    required this.localIdentity,
    required this.validatePeer,
    required this.saveTrust,
    required this.onChanged,
  }) {
    _timeout = Timer(confirmationTimeout, () {
      if (!_finished) _finish(PairingPhase.failed, 'Confirmation timed out.');
    });
    unawaited(_sendIdentity());
    _listen();
  }

  String get sas => session.sas;
  String get peerFingerprint => session.peerFingerprint;
  String get peerNickname => session.peerNickname;

  /// True once the peer's BSAT identity was received and accepted; only then
  /// may the user confirm.
  bool get peerAccepted => peerIdentity != null;
  bool get _finished =>
      phase != PairingPhase.awaitingConfirmation &&
      phase != PairingPhase.waitingForPeer;
  bool get isFinished => _finished;

  Future<void> _sendIdentity() async {
    try {
      await session.send(localIdentity.toJson());
    } catch (_) {
      if (!_finished) {
        _finish(PairingPhase.failed, "Could not send this device's identity.");
      }
    }
  }

  Future<void> _listen() async {
    try {
      while (!_finished) {
        final message = await session.receive();
        switch (message['type']) {
          case 'pair_identity':
            if (peerIdentity != null) {
              _finish(PairingPhase.failed, 'Unexpected pairing message.');
              break;
            }
            final identity = LanPeerIdentity.fromJson(message);
            if (identity == null) {
              await _refuse('The other phone sent an invalid BSAT identity.');
              break;
            }
            final refusal = await validatePeer(identity);
            if (refusal != null) {
              await _refuse(refusal);
              break;
            }
            peerIdentity = identity;
            onChanged();
            await _maybeComplete();
          case 'pair_confirm':
            if (peerIdentity == null) {
              _finish(PairingPhase.failed, 'Unexpected pairing message.');
              break;
            }
            _remoteConfirmed = true;
            await _maybeComplete();
          case 'pair_reject':
            _finish(
              PairingPhase.rejectedByPeer,
              'The other device rejected pairing.',
            );
          default:
            _finish(PairingPhase.failed, 'Unexpected pairing message.');
        }
      }
    } catch (error) {
      // When both sides already confirmed, _maybeComplete owns the outcome.
      if (!_finished && !(_localConfirmed && _remoteConfirmed)) {
        _finish(
          PairingPhase.failed,
          'Pairing connection ended before both devices confirmed.',
        );
      }
    }
  }

  Future<void> _refuse(String reason) async {
    try {
      await session.send({'type': 'pair_reject'});
      await session.connection.flush();
    } catch (_) {}
    _finish(PairingPhase.failed, reason);
  }

  Future<void> confirm() async {
    if (_finished || _localConfirmed || !peerAccepted) return;
    _localConfirmed = true;
    phase = PairingPhase.waitingForPeer;
    onChanged();
    try {
      await session.send({'type': 'pair_confirm'});
    } catch (_) {
      _finish(PairingPhase.failed, 'Could not send confirmation.');
      return;
    }
    await _maybeComplete();
  }

  Future<void> reject() async {
    if (_finished) return;
    try {
      await session.send({'type': 'pair_reject'});
      await session.connection.flush();
    } catch (_) {}
    _finish(PairingPhase.rejectedLocally, 'Pairing rejected on this device.');
  }

  void cancel() {
    // Once both users confirmed, _maybeComplete owns the outcome: trust may
    // already be written, so it must not be reported as cancelled.
    if (_finished || (_localConfirmed && _remoteConfirmed)) return;
    _finish(PairingPhase.cancelled, 'Pairing cancelled.');
  }

  Future<void> _maybeComplete() async {
    if (!_localConfirmed ||
        !_remoteConfirmed ||
        peerIdentity == null ||
        _finished) {
      return;
    }
    try {
      await saveTrust(this);
      // Give the peer a moment to receive our confirmation before closing.
      await session.connection.flush();
      _finish(PairingPhase.completed, null);
    } on StorageException catch (error) {
      _finish(
        PairingPhase.failed,
        'Local storage failure: the trusted device could not be saved '
        '(${error.detail}).',
      );
    } catch (error) {
      _finish(
        PairingPhase.failed,
        'Could not save trust: ${error.runtimeType}',
      );
    }
  }

  void _finish(PairingPhase result, String? reason) {
    phase = result;
    failure = reason;
    _timeout?.cancel();
    if (result == PairingPhase.completed) {
      Timer(const Duration(milliseconds: 500), session.close);
    } else {
      session.close();
    }
    onChanged();
  }
}
