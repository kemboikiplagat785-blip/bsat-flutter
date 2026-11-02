// BSAT LAN forwarding secure transport. Ported from the BSAT Local Lab
// prototype (lib/src/secure/secure_session.dart, its "protocol version 2"):
// the handshake, key schedule and record layer are unchanged. Only the
// domain-separation labels (BSAT-LAN-V1) and the protocol version constant
// differ, so a Lab key or transcript can never be accepted by BSAT. The
// prototype's plaintext Phase 2 compatibility reply is removed: BSAT has no
// unauthenticated LAN peers.
//
// Construction (SIGMA-I / TLS 1.3 handshake pattern, standard primitives
// only; see README "Protocol and cryptographic design"):
//
//   C -> S  secure_hello        {mode, ephemeral X25519 pub eC, random rC}
//   S -> C  secure_hello_reply  {ephemeral eS, random rS, identity IS,
//                                signature = Ed25519_IS(L_srv || th1)}
//           th1  = SHA-256(L_th1 || len(helloBytes) || helloBytes || eS || rS || IS)
//           keys = HKDF-SHA-256(ikm = X25519(eC, eS), salt = th1,
//                               info = L_keys, 128 bytes)
//                = k_c2s | k_s2c | k_cfin | k_sfin
//   C -> S  record#0 {secure_client_auth: identity IC,
//                     signature = Ed25519_IC(L_cli || th2),
//                     finished  = HMAC-SHA-256(k_cfin, th2) [, token]}
//           th2  = SHA-256(L_th2 || th1 || IC)
//   S -> C  record#0 {secure_ready: finished = HMAC-SHA-256(k_sfin, th2)}
//           or record#0 {secure_error: code}
//
// Records: ChaCha20-Poly1305 (RFC 8439). Separate key per direction, 96-bit
// nonce = 0x00000000 || seq (uint64 BE), AAD = L_rec || dir || seq || th1.
// Sequence numbers must arrive exactly in order starting at 0; anything else
// (replay, reorder, drop, tamper, other session) closes the session.

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

import 'lan_crypto_util.dart';
import 'lan_device_identity.dart';
import 'lan_framing.dart';
import 'lan_frame_connection.dart';

const _labelTh1 = 'BSAT-LAN-V1 th1';
const _labelTh2 = 'BSAT-LAN-V1 th2';
const _labelServerSig = 'BSAT-LAN-V1 server-auth';
const _labelClientSig = 'BSAT-LAN-V1 client-auth';
const _labelKeys = 'BSAT-LAN-V1 session keys';
const _labelRecord = 'BSAT-LAN-V1 record';
const _labelSas = 'BSAT-LAN-V1 sas';

class SecureTypes {
  static const hello = 'secure_hello';
  static const helloReply = 'secure_hello_reply';
  static const record = 'secure_record';
  static const clientAuth = 'secure_client_auth';
  static const ready = 'secure_ready';
  static const error = 'secure_error';
}

enum HandshakeMode { session, pairing }

/// Maximum plaintext inside one record, leaving room for base64 expansion
/// within [maxFramePayloadBytes].
const int maxRecordPlaintextBytes = 8 * 1024;
/// Upper bound for a whole handshake. The pure-Dart X25519/Ed25519 work on
/// both phones runs in sequence; on budget phones (and in debug builds) it
/// was measured to take about 10 s, so a tighter bound made pairing fail.
/// It only limits how long an unfinished handshake may hold a connection.
const Duration handshakeTimeout = Duration(seconds: 30);

/// Longest nickname (the peer's BSAT device name) accepted in a handshake.
const int maxNicknameChars = 100;

enum HandshakeErrorCode {
  /// Peer only speaks the unauthenticated Phase 2 protocol.
  incompatibleProtocol,

  /// Peer's identity is not trusted (or revoked).
  untrustedPeer,

  /// Peer's identity is valid but is not the device we expected.
  identityMismatch,

  /// Signature or finished MAC did not verify.
  authenticationFailed,

  /// Pairing invitation missing, wrong, expired or already used.
  invitationInvalid,

  /// Malformed or unexpected handshake message.
  protocolError,

  /// Handshake did not complete within [handshakeTimeout].
  timeout,
}

/// Optional refinement of a refusal code sent inside the encrypted error
/// record, e.g. why an invitation was refused. A short lowercase identifier;
/// never contains token, key or payload material.
final RegExp _reasonPattern = RegExp(r'^[a-z_]{1,32}$');

String? _reasonField(Object? value) =>
    value is String && _reasonPattern.hasMatch(value) ? value : null;

/// A server's decision to refuse a client.
class HandshakeRefusal {
  final HandshakeErrorCode code;
  final String? reason;

  const HandshakeRefusal(this.code, [this.reason]);
}

class HandshakeException implements Exception {
  final HandshakeErrorCode code;
  final String detail;

  /// See [HandshakeRefusal.reason]. Null when the peer gave none (including
  /// Phase 3 builds that predate reasons).
  final String? reason;

  /// True when the remote side explicitly rejected us.
  final bool remote;

  const HandshakeException(
    this.code,
    this.detail, {
    this.remote = false,
    this.reason,
  });

  String get wireCode => switch (code) {
    HandshakeErrorCode.incompatibleProtocol => 'incompatible_protocol',
    HandshakeErrorCode.untrustedPeer => 'untrusted_peer',
    HandshakeErrorCode.identityMismatch => 'identity_mismatch',
    HandshakeErrorCode.authenticationFailed => 'authentication_failed',
    HandshakeErrorCode.invitationInvalid => 'invitation_invalid',
    HandshakeErrorCode.protocolError => 'protocol_error',
    HandshakeErrorCode.timeout => 'timeout',
  };

  static HandshakeErrorCode fromWire(Object? code) => switch (code) {
    'untrusted_peer' => HandshakeErrorCode.untrustedPeer,
    'identity_mismatch' => HandshakeErrorCode.identityMismatch,
    'authentication_failed' => HandshakeErrorCode.authenticationFailed,
    'invitation_invalid' => HandshakeErrorCode.invitationInvalid,
    'incompatible_protocol' => HandshakeErrorCode.incompatibleProtocol,
    _ => HandshakeErrorCode.protocolError,
  };

  /// Wire code plus reason, e.g. `invitation_invalid (expired)`.
  String get summary => reason == null ? wireCode : '$wireCode ($reason)';

  @override
  String toString() => 'HandshakeException($summary): $detail';
}

/// Raised for any record-layer failure. The session is closed.
class RecordException implements Exception {
  final String detail;

  const RecordException(this.detail);

  @override
  String toString() => 'RecordException: $detail';
}

class _SessionKeys {
  final SecretKeyData c2s;
  final SecretKeyData s2c;
  final Uint8List clientFinished;
  final Uint8List serverFinished;

  _SessionKeys(this.c2s, this.s2c, this.clientFinished, this.serverFinished);

  static Future<_SessionKeys> derive(SecretKey shared, Uint8List th1) async {
    final okm = await Hkdf(
      hmac: Hmac.sha256(),
      outputLength: 128,
    ).deriveKey(secretKey: shared, nonce: th1, info: utf8.encode(_labelKeys));
    final bytes = okm.bytes;
    final keys = _SessionKeys(
      SecretKeyData(bytes.sublist(0, 32), overwriteWhenDestroyed: true),
      SecretKeyData(bytes.sublist(32, 64), overwriteWhenDestroyed: true),
      Uint8List.fromList(bytes.sublist(64, 96)),
      Uint8List.fromList(bytes.sublist(96, 128)),
    );
    okm.destroy();
    return keys;
  }

  void destroyFinishedKeys() {
    clientFinished.fillRange(0, 32, 0);
    serverFinished.fillRange(0, 32, 0);
  }
}

/// Seals and opens records for one session in one direction pair.
class RecordProtector {
  final SecretKeyData _sendKey;
  final SecretKeyData _receiveKey;
  final int _sendDirection;
  final int _receiveDirection;
  final Uint8List sessionId;
  int _sendSeq = 0;
  int _receiveSeq = 0;
  bool _destroyed = false;

  static final _aead = Chacha20.poly1305Aead();

  RecordProtector._(
    this._sendKey,
    this._receiveKey,
    this._sendDirection,
    this._receiveDirection,
    this.sessionId,
  );

  /// Test-only: build a protector from explicit keys.
  factory RecordProtector.forTesting({
    required List<int> sendKey,
    required List<int> receiveKey,
    required int sendDirection,
    required int receiveDirection,
    required List<int> sessionId,
  }) => RecordProtector._(
    SecretKeyData(sendKey),
    SecretKeyData(receiveKey),
    sendDirection,
    receiveDirection,
    Uint8List.fromList(sessionId),
  );

  int get sentRecords => _sendSeq;
  int get receivedRecords => _receiveSeq;

  List<int> _nonce(int direction, int seq) {
    final nonce = Uint8List(12);
    nonce[3] = direction;
    ByteData.sublistView(nonce).setUint64(4, seq, Endian.big);
    return nonce;
  }

  List<int> _aad(int direction, int seq) {
    final header = Uint8List(9);
    header[0] = direction;
    ByteData.sublistView(header).setUint64(1, seq, Endian.big);
    return [...utf8.encode(_labelRecord), ...header, ...sessionId];
  }

  Future<Map<String, Object?>> seal(Map<String, Object?> plaintext) async {
    if (_destroyed) throw const RecordException('Session is closed.');
    final clear = utf8.encode(jsonEncode(plaintext));
    if (clear.length > maxRecordPlaintextBytes) {
      throw const RecordException('Record plaintext too large.');
    }
    final seq = _sendSeq++;
    final box = await _aead.encrypt(
      clear,
      secretKey: _sendKey,
      nonce: _nonce(_sendDirection, seq),
      aad: _aad(_sendDirection, seq),
    );
    return {
      'version': secureProtocolVersion,
      'type': SecureTypes.record,
      'seq': seq,
      'ct': base64Encode([...box.cipherText, ...box.mac.bytes]),
    };
  }

  Future<Map<String, Object?>> open(Map<String, Object?> record) async {
    if (_destroyed) throw const RecordException('Session is closed.');
    if (record['version'] != secureProtocolVersion ||
        record['type'] != SecureTypes.record) {
      throw const RecordException('Not a secure record.');
    }
    final seq = record['seq'];
    if (seq is! int || seq != _receiveSeq) {
      throw RecordException(
        'Unexpected record sequence $seq (expected $_receiveSeq).',
      );
    }
    final ctText = record['ct'];
    if (ctText is! String) throw const RecordException('Missing ciphertext.');
    final Uint8List ct;
    try {
      ct = base64Decode(ctText);
    } on FormatException {
      throw const RecordException('Ciphertext is not base64.');
    }
    if (ct.length < 16) throw const RecordException('Ciphertext truncated.');
    final List<int> clear;
    try {
      clear = await _aead.decrypt(
        SecretBox(
          ct.sublist(0, ct.length - 16),
          nonce: _nonce(_receiveDirection, seq),
          mac: Mac(ct.sublist(ct.length - 16)),
        ),
        secretKey: _receiveKey,
        aad: _aad(_receiveDirection, seq),
      );
    } on SecretBoxAuthenticationError {
      throw const RecordException('Record failed authentication.');
    }
    _receiveSeq++;
    try {
      final decoded = jsonDecode(utf8.decode(clear));
      if (decoded is! Map<String, dynamic>) {
        throw const RecordException('Record plaintext is not an object.');
      }
      return decoded;
    } on FormatException {
      throw const RecordException('Record plaintext is not JSON.');
    }
  }

  void destroy() {
    if (_destroyed) return;
    _destroyed = true;
    _sendKey.destroy();
    _receiveKey.destroy();
  }
}

/// An authenticated, encrypted connection to one peer.
class SecureSession {
  final FrameConnection connection;
  final RecordProtector _records;
  final HandshakeMode mode;
  final Uint8List peerPublicKey;
  final String peerFingerprint;
  final String peerNickname;

  /// Six-digit short authentication string derived from th2. Both sides
  /// compute the same value only if they saw the same handshake.
  final String sas;
  final DateTime establishedAt = DateTime.now();
  Future<void> _sendChain = Future.value();

  SecureSession._({
    required this.connection,
    required RecordProtector records,
    required this.mode,
    required this.peerPublicKey,
    required this.peerNickname,
    required this.sas,
  }) : // Named parameters cannot be private, so the field is set here.
       // ignore: prefer_initializing_formals
       _records = records,
       peerFingerprint = fingerprintOf(peerPublicKey);

  Uint8List get sessionId => _records.sessionId;
  bool get isClosed => connection.isClosed;

  /// Encrypts and sends one message. Sends are serialized so sequence
  /// numbers reach the socket in order.
  Future<void> send(Map<String, Object?> message) {
    final result = _sendChain.then((_) async {
      final record = await _records.seal(message);
      connection.sendJson(record);
    });
    _sendChain = result.catchError((_) {});
    return result;
  }

  /// Receives and decrypts the next message. Throws [RecordException] on any
  /// authentication or ordering failure; the caller must then [close].
  Future<Map<String, Object?>> receive({Duration? timeout}) async {
    final frame = await connection.next(timeout: timeout);
    final Map<String, Object?> json;
    try {
      json = decodeJsonObject(frame);
    } on ProtocolException catch (error) {
      throw RecordException('Malformed record frame: ${error.wireCode}');
    }
    return _records.open(json);
  }

  void close() {
    _records.destroy();
    connection.close();
  }
}

Uint8List _sha256(List<int> data) =>
    Uint8List.fromList(const DartSha256().hashSync(data).bytes);

Uint8List _lengthPrefixed(List<int> bytes) {
  final out = Uint8List(4 + bytes.length);
  ByteData.sublistView(out).setUint32(0, bytes.length, Endian.big);
  out.setRange(4, out.length, bytes);
  return out;
}

Uint8List _th1(
  List<int> helloBytes,
  List<int> serverEphemeral,
  List<int> serverRandom,
  List<int> serverIdentity,
) => _sha256([
  ...utf8.encode(_labelTh1),
  ..._lengthPrefixed(helloBytes),
  ...serverEphemeral,
  ...serverRandom,
  ...serverIdentity,
]);

Uint8List _th2(List<int> th1, List<int> clientIdentity) =>
    _sha256([...utf8.encode(_labelTh2), ...th1, ...clientIdentity]);

String deriveSas(List<int> th2) {
  final digest = _sha256([...utf8.encode(_labelSas), ...th2]);
  final value = ByteData.sublistView(digest).getUint32(0, Endian.big) % 1000000;
  return value.toString().padLeft(6, '0');
}

Future<Uint8List> _hmac(List<int> key, List<int> data) async =>
    Uint8List.fromList(
      (await Hmac.sha256().calculateMac(
        data,
        secretKey: SecretKeyData(key),
      )).bytes,
    );

Uint8List _b64Field(Map<String, Object?> json, String key, int length) {
  final value = json[key];
  if (value is! String) {
    throw HandshakeException(
      HandshakeErrorCode.protocolError,
      'Missing field $key.',
    );
  }
  try {
    final bytes = base64Decode(value);
    if (bytes.length != length) throw const FormatException();
    return bytes;
  } on FormatException {
    throw HandshakeException(
      HandshakeErrorCode.protocolError,
      'Field $key has the wrong format.',
    );
  }
}

String _nicknameField(Map<String, Object?> json) {
  final value = json['nickname'];
  if (value is! String || value.isEmpty || value.length > maxNicknameChars) {
    return 'Unnamed device';
  }
  return value.replaceAll(RegExp(r'[\x00-\x1f]'), '');
}

Future<T> _withTimeout<T>(Future<T> Function() body) async {
  try {
    return await body().timeout(handshakeTimeout);
  } on TimeoutException {
    throw const HandshakeException(
      HandshakeErrorCode.timeout,
      'Handshake timed out.',
    );
  }
}

/// Client side of the handshake.
///
/// [acceptServer] decides, before the client reveals its own identity,
/// whether the server's authenticated identity key is the one expected.
/// [pairingToken] is required in [HandshakeMode.pairing].
Future<SecureSession> clientHandshake({
  required FrameConnection connection,
  required DeviceIdentity identity,
  required String nickname,
  required HandshakeMode mode,
  required FutureOr<HandshakeErrorCode?> Function(Uint8List serverIdentity)
  acceptServer,
  Uint8List? pairingToken,
  // Test hook: claim this public key while signing with [identity], to
  // verify that servers reject identity forgery.
  Uint8List? debugClaimedIdentity,
}) => _withTimeout(() async {
  final ephemeral = await X25519().newKeyPair();
  final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
  final clientRandom = secureRandomBytes(32);
  final helloBytes = connection.sendJson({
    'version': secureProtocolVersion,
    'type': SecureTypes.hello,
    'mode': mode.name,
    'ephemeral': base64Encode(ephemeralPublic),
    'random': base64Encode(clientRandom),
  });

  final Map<String, Object?> reply;
  try {
    reply = decodeJsonObject(await connection.next());
  } on ProtocolException catch (error) {
    throw HandshakeException(
      HandshakeErrorCode.protocolError,
      'Malformed handshake reply: ${error.wireCode}',
    );
  }
  if (reply['version'] == secureProtocolVersion &&
      reply['type'] == SecureTypes.error) {
    throw HandshakeException(
      HandshakeException.fromWire(reply['code']),
      'Peer rejected the handshake (${reply['code']}).',
      remote: true,
    );
  }
  if (reply['version'] != secureProtocolVersion ||
      reply['type'] != SecureTypes.helloReply) {
    throw const HandshakeException(
      HandshakeErrorCode.protocolError,
      'Unexpected handshake reply.',
    );
  }
  final serverEphemeral = _b64Field(reply, 'ephemeral', 32);
  final serverRandom = _b64Field(reply, 'random', 32);
  final serverIdentity = _b64Field(reply, 'identity', 32);
  final serverSignature = _b64Field(reply, 'signature', 64);
  final th1 = _th1(helloBytes, serverEphemeral, serverRandom, serverIdentity);
  if (!await verifyEd25519(
    message: [...utf8.encode(_labelServerSig), ...th1],
    signature: serverSignature,
    publicKey: serverIdentity,
  )) {
    throw const HandshakeException(
      HandshakeErrorCode.authenticationFailed,
      'Server signature is invalid.',
    );
  }
  final refusal = await acceptServer(serverIdentity);
  if (refusal != null) {
    throw HandshakeException(
      refusal,
      'Server identity ${displayFingerprint(fingerprintOf(serverIdentity))} '
      'is not acceptable.',
    );
  }

  final shared = await X25519().sharedSecretKey(
    keyPair: ephemeral,
    remotePublicKey: SimplePublicKey(serverEphemeral, type: KeyPairType.x25519),
  );
  final keys = await _SessionKeys.derive(shared, th1);
  final records = RecordProtector._(keys.c2s, keys.s2c, 1, 2, th1);
  final claimed = debugClaimedIdentity ?? identity.publicKey;
  final th2 = _th2(th1, claimed);
  try {
    final auth = await records.seal({
      'type': SecureTypes.clientAuth,
      'identity': base64Encode(claimed),
      'nickname': nickname,
      'signature': base64Encode(
        await identity.sign([...utf8.encode(_labelClientSig), ...th2]),
      ),
      'finished': base64Encode(await _hmac(keys.clientFinished, th2)),
      if (pairingToken != null) 'token': base64Encode(pairingToken),
    });
    connection.sendJson(auth);

    final response = await records.open(
      decodeJsonObject(await connection.next()),
    );
    if (response['type'] == SecureTypes.error) {
      throw HandshakeException(
        HandshakeException.fromWire(response['code']),
        'Peer rejected this device (${response['code']}).',
        remote: true,
        reason: _reasonField(response['reason']),
      );
    }
    if (response['type'] != SecureTypes.ready) {
      throw const HandshakeException(
        HandshakeErrorCode.protocolError,
        'Expected secure_ready.',
      );
    }
    final finished = _b64Field(response, 'finished', 32);
    if (!constantTimeEquals(finished, await _hmac(keys.serverFinished, th2))) {
      throw const HandshakeException(
        HandshakeErrorCode.authenticationFailed,
        'Server finished MAC is invalid.',
      );
    }
    keys.destroyFinishedKeys();
    return SecureSession._(
      connection: connection,
      records: records,
      mode: mode,
      peerPublicKey: serverIdentity,
      peerNickname: _nicknameField(response),
      sas: deriveSas(th2),
    );
  } on RecordException catch (error) {
    records.destroy();
    throw HandshakeException(
      HandshakeErrorCode.authenticationFailed,
      error.detail,
    );
  } on ProtocolException catch (error) {
    records.destroy();
    throw HandshakeException(HandshakeErrorCode.protocolError, error.detail);
  } catch (_) {
    records.destroy();
    rethrow;
  }
});

/// Server-side authorization decision for a client identity: null accepts.
typedef ClientAuthorizer = FutureOr<HandshakeRefusal?> Function(
  HandshakeMode mode,
  Uint8List clientIdentity,
  Uint8List? pairingToken,
);

/// Server side of the handshake. [firstFrame] is the already-read hello.
Future<SecureSession> serverHandshake({
  required FrameConnection connection,
  required Uint8List firstFrame,
  required DeviceIdentity identity,
  required String nickname,
  required ClientAuthorizer authorize,
}) => _withTimeout(() async {
  final Map<String, Object?> hello;
  try {
    hello = decodeJsonObject(firstFrame);
  } on ProtocolException catch (error) {
    throw HandshakeException(HandshakeErrorCode.protocolError, error.detail);
  }
  if (hello['version'] != secureProtocolVersion ||
      hello['type'] != SecureTypes.hello) {
    throw const HandshakeException(
      HandshakeErrorCode.protocolError,
      'Expected secure_hello.',
    );
  }
  final mode = switch (hello['mode']) {
    'session' => HandshakeMode.session,
    'pairing' => HandshakeMode.pairing,
    _ => throw const HandshakeException(
      HandshakeErrorCode.protocolError,
      'Unknown handshake mode.',
    ),
  };
  final clientEphemeral = _b64Field(hello, 'ephemeral', 32);
  _b64Field(hello, 'random', 32);

  final ephemeral = await X25519().newKeyPair();
  final ephemeralPublic = (await ephemeral.extractPublicKey()).bytes;
  final serverRandom = secureRandomBytes(32);
  final th1 = _th1(
    firstFrame,
    ephemeralPublic,
    serverRandom,
    identity.publicKey,
  );
  connection.sendJson({
    'version': secureProtocolVersion,
    'type': SecureTypes.helloReply,
    'ephemeral': base64Encode(ephemeralPublic),
    'random': base64Encode(serverRandom),
    'identity': base64Encode(identity.publicKey),
    'signature': base64Encode(
      await identity.sign([...utf8.encode(_labelServerSig), ...th1]),
    ),
  });

  final shared = await X25519().sharedSecretKey(
    keyPair: ephemeral,
    remotePublicKey: SimplePublicKey(clientEphemeral, type: KeyPairType.x25519),
  );
  final keys = await _SessionKeys.derive(shared, th1);
  final records = RecordProtector._(keys.s2c, keys.c2s, 2, 1, th1);

  Future<Never> refuse(
    HandshakeErrorCode code,
    String detail, {
    String? reason,
  }) async {
    try {
      connection.sendJson(
        await records.seal({
          'type': SecureTypes.error,
          'code': HandshakeException(code, '').wireCode,
          if (_reasonField(reason) != null) 'reason': reason,
        }),
      );
      await connection.flush();
    } catch (_) {}
    records.destroy();
    throw HandshakeException(code, detail, reason: _reasonField(reason));
  }

  final Map<String, Object?> auth;
  try {
    auth = await records.open(decodeJsonObject(await connection.next()));
  } on RecordException catch (error) {
    records.destroy();
    throw HandshakeException(
      HandshakeErrorCode.authenticationFailed,
      error.detail,
    );
  } on ProtocolException catch (error) {
    records.destroy();
    throw HandshakeException(HandshakeErrorCode.protocolError, error.detail);
  }
  if (auth['type'] != SecureTypes.clientAuth) {
    return refuse(HandshakeErrorCode.protocolError, 'Expected client auth.');
  }
  final Uint8List clientIdentity;
  final Uint8List signature;
  final Uint8List finished;
  try {
    clientIdentity = _b64Field(auth, 'identity', 32);
    signature = _b64Field(auth, 'signature', 64);
    finished = _b64Field(auth, 'finished', 32);
  } on HandshakeException catch (error) {
    return refuse(error.code, error.detail);
  }
  final th2 = _th2(th1, clientIdentity);
  if (!await verifyEd25519(
        message: [...utf8.encode(_labelClientSig), ...th2],
        signature: signature,
        publicKey: clientIdentity,
      ) ||
      !constantTimeEquals(finished, await _hmac(keys.clientFinished, th2))) {
    return refuse(
      HandshakeErrorCode.authenticationFailed,
      'Client signature or finished MAC is invalid.',
    );
  }
  Uint8List? token;
  if (mode == HandshakeMode.pairing) {
    final value = auth['token'];
    if (value is String) {
      try {
        token = base64Decode(value);
      } on FormatException {
        token = null;
      }
    }
  }
  final refusal = await authorize(mode, clientIdentity, token);
  if (refusal != null) {
    return refuse(
      refusal.code,
      'Client ${displayFingerprint(fingerprintOf(clientIdentity))} '
      'refused.',
      reason: refusal.reason,
    );
  }
  connection.sendJson(
    await records.seal({
      'type': SecureTypes.ready,
      'nickname': nickname,
      'finished': base64Encode(await _hmac(keys.serverFinished, th2)),
    }),
  );
  keys.destroyFinishedKeys();
  return SecureSession._(
    connection: connection,
    records: records,
    mode: mode,
    peerPublicKey: clientIdentity,
    peerNickname: _nicknameField(auth),
    sas: deriveSas(th2),
  );
});

/// Plaintext reply for a first frame that is not a secure hello. It names no
/// identity and carries no secret; nothing ever falls back to plaintext.
Map<String, Object?> plaintextRefusal() => {
      'version': secureProtocolVersion,
      'type': SecureTypes.error,
      'code': 'protocol_error',
    };
