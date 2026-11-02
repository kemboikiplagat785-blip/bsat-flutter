/// Application messages carried inside an authenticated LAN session.
///
/// A LAN exchange carries exactly the `data` map an Internet (FCM) delivery
/// carries, so the receiving device runs the same handlers, validation,
/// durable claims and confirmation rules for both transports. This file only
/// decides whether a map is structurally acceptable and addressed between the
/// authenticated peer and this device; it never decides purchase outcomes.
library;

import 'dart:math';

/// Envelope types inside the encrypted record layer.
class LanEnvelopeTypes {
  /// Client to server: one forwarding message.
  static const request = 'bsat_request';

  /// Server to client: a reply produced while handling the request (receipt
  /// ACK, confirmation receipt).
  static const reply = 'bsat_reply';

  /// Server to client: handling finished (or the request was refused).
  static const done = 'bsat_done';

  /// Client to server: reachability check. Carries no forwarding data.
  static const probe = 'bsat_probe';
  static const probeOk = 'bsat_probe_ok';
}

/// Why a server refused a request before any handler ran.
class LanRejectReasons {
  static const invalidMessage = 'invalid_message';
  static const unexpectedSender = 'unexpected_sender';
  static const unexpectedRecipient = 'unexpected_recipient';
  static const unsupportedType = 'unsupported_type';
  static const handlerUnavailable = 'handler_unavailable';
  static const handlerFailed = 'handler_failed';
}

/// Message kinds that may travel over LAN. Everything else (data requests,
/// settings, offers...) is refused: it stays on its existing Internet path,
/// or is not available over LAN.
enum LanMessageKind {
  /// Phone A to Phone B: a forwarding job (`forwarded_sms`).
  forwardedSms,

  /// Phone B to Phone A: the final confirmation of a job.
  forwardingConfirmation,

  /// Phone A to Phone B: receipt of that final confirmation.
  confirmationReceipt,

  /// Phone B to Phone A (reply only): durable receipt of a job.
  receiptAck,

  /// Phone A to Phone C: run an offer's alternative code
  /// (`process_alt_request`).
  alternativeRequest,

  /// Phone C to Phone A (reply only): durable receipt of that request.
  alternativeRequestReceipt,

  /// Phone C to Phone A: the alternative code's result
  /// (`forwarded_alt_result`).
  alternativeResult,

  /// Phone A to Phone C (reply only): receipt of that result.
  alternativeResultReceipt,
}

final RegExp _jobIdPattern = RegExp(r'^[A-Za-z0-9_\-]{4,128}$');
final RegExp _requestIdPattern = RegExp(r'^[0-9a-f]{32}$');
final RegExp _controlCharacters = RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]');

const int maxLanBodyChars = 2000;
const int maxLanNameChars = 100;
const int maxLanFieldChars = 200;

const Map<LanMessageKind, Set<String>> _requiredKeys = {
  LanMessageKind.forwardedSms: {
    'type',
    'body',
    'transactionId',
    'forwardingJobId',
    'senderDeviceName',
    'recipientDeviceName',
  },
  LanMessageKind.forwardingConfirmation: {
    'type',
    'ackKind',
    'status',
    'forwardingJobId',
    'senderDeviceName',
    'recipientDeviceName',
  },
  LanMessageKind.confirmationReceipt: {
    'type',
    'ackKind',
    'status',
    'forwardingJobId',
    'senderDeviceName',
    'recipientDeviceName',
  },
  LanMessageKind.receiptAck: _messageAckRequiredKeys,
  LanMessageKind.alternativeRequest: {
    'type',
    'transactionId',
    'forwardingJobId',
    'senderDeviceName',
    'recipientDeviceName',
    'ussdCode',
  },
  LanMessageKind.alternativeRequestReceipt: _messageAckRequiredKeys,
  LanMessageKind.alternativeResult: {
    'type',
    'transactionId',
    'forwardingJobId',
    'status',
    'senderDeviceName',
    'recipientDeviceName',
  },
  LanMessageKind.alternativeResultReceipt: _messageAckRequiredKeys,
};

const Set<String> _messageAckRequiredKeys = {
  'type',
  'ackKind',
  'status',
  'originalType',
  'forwardingJobId',
  'senderDeviceName',
  'recipientDeviceName',
};

const Set<String> _messageAckOptionalKeys = {
  'messageId',
  'requestId',
  'transactionId',
  'receivedAt',
  'resultStatus',
  'body',
  'title',
};

const Map<LanMessageKind, Set<String>> _optionalKeys = {
  LanMessageKind.forwardedSms: {'title', 'messageId', 'forwardingStatus'},
  LanMessageKind.forwardingConfirmation: {
    'resultStatus',
    'requiredTopUp',
    'targetAmount',
    'transactionId',
  },
  LanMessageKind.confirmationReceipt: {},
  LanMessageKind.receiptAck: _messageAckOptionalKeys,
  LanMessageKind.alternativeRequest: {
    'isAdvanced',
    'smsMessage',
    'body',
    'title',
  },
  LanMessageKind.alternativeRequestReceipt: _messageAckOptionalKeys,
  LanMessageKind.alternativeResult: {'ussdReply'},
  LanMessageKind.alternativeResultReceipt: _messageAckOptionalKeys,
};

/// Free-text fields: as long as a body, and may contain line breaks.
const Set<String> _textKeys = {'body', 'smsMessage', 'ussdReply'};

/// The kind of a forwarding `data` map, or null when it is not a LAN kind.
LanMessageKind? lanMessageKindOf(Map<String, Object?> data) {
  final type = data['type'];
  final ackKind = data['ackKind'];
  if (type == 'forwarded_sms') return LanMessageKind.forwardedSms;
  if (type == 'forwarded_sms_ack' && ackKind == 'confirmed') {
    return LanMessageKind.forwardingConfirmation;
  }
  if (type == 'forwarded_sms_ack' && ackKind == 'confirmation_received') {
    return LanMessageKind.confirmationReceipt;
  }
  if (type == 'MESSAGE_ACK' &&
      ackKind == 'received' &&
      data['originalType'] == 'forwarded_sms') {
    return LanMessageKind.receiptAck;
  }
  if (type == 'process_alt_request') return LanMessageKind.alternativeRequest;
  if (type == 'MESSAGE_ACK' &&
      ackKind == 'alternative_received' &&
      data['originalType'] == 'process_alt_request') {
    return LanMessageKind.alternativeRequestReceipt;
  }
  if (type == 'forwarded_alt_result') return LanMessageKind.alternativeResult;
  if (type == 'MESSAGE_ACK' &&
      ackKind == 'alternative_result_received' &&
      data['originalType'] == 'forwarded_alt_result') {
    return LanMessageKind.alternativeResultReceipt;
  }
  return null;
}

/// Kinds a client may send as a request.
const Set<LanMessageKind> lanRequestKinds = {
  LanMessageKind.forwardedSms,
  LanMessageKind.forwardingConfirmation,
  LanMessageKind.confirmationReceipt,
  LanMessageKind.alternativeRequest,
  LanMessageKind.alternativeResult,
};

/// Kinds a server may send as a reply to [request].
Set<LanMessageKind> lanReplyKindsFor(LanMessageKind request) =>
    switch (request) {
      LanMessageKind.forwardedSms => {LanMessageKind.receiptAck},
      LanMessageKind.forwardingConfirmation => {
          LanMessageKind.confirmationReceipt,
        },
      LanMessageKind.alternativeRequest => {
          LanMessageKind.alternativeRequestReceipt,
        },
      LanMessageKind.alternativeResult => {
          LanMessageKind.alternativeResultReceipt,
        },
      _ => const {},
    };

/// A structurally valid forwarding map, with every value as a string (the
/// shape an FCM data payload has when it reaches the existing handlers).
class LanForwardingData {
  final LanMessageKind kind;
  final Map<String, String> data;

  const LanForwardingData(this.kind, this.data);

  String get forwardingJobId => data['forwardingJobId'] ?? '';
  String get senderDeviceName => data['senderDeviceName'] ?? '';
  String get recipientDeviceName => data['recipientDeviceName'] ?? '';
}

class LanMessageException implements Exception {
  final String reason;
  final String detail;

  const LanMessageException(this.reason, this.detail);

  @override
  String toString() => 'LanMessageException($reason): $detail';
}

String? _scalarString(Object? value) => switch (value) {
      String() => value,
      int() || bool() => value.toString(),
      _ => null,
    };

/// Validates a forwarding map received over LAN.
///
/// * Only the kinds in [allowed] are accepted; unknown keys are refused.
/// * Values must be strings, integers or booleans within size limits.
/// * The job ID must be well formed.
/// * [authenticatedPeerDeviceName] is the BSAT device the peer's pinned key
///   was paired with. The message must name it as its sender, and must be
///   addressed to [ownDeviceName]. A name written in the message is never
///   trusted on its own.
///
/// Throws [LanMessageException].
LanForwardingData validateLanForwardingData(
  Object? raw, {
  required Set<LanMessageKind> allowed,
  required String authenticatedPeerDeviceName,
  required String ownDeviceName,
}) {
  if (raw is! Map) {
    throw const LanMessageException(
        LanRejectReasons.invalidMessage, 'data is not an object');
  }
  final map = <String, Object?>{};
  for (final entry in raw.entries) {
    if (entry.key is! String) {
      throw const LanMessageException(
          LanRejectReasons.invalidMessage, 'non-string key');
    }
    map[entry.key as String] = entry.value;
  }
  final kind = lanMessageKindOf(map);
  if (kind == null || !allowed.contains(kind)) {
    throw const LanMessageException(
        LanRejectReasons.unsupportedType, 'message type not allowed');
  }
  final required = _requiredKeys[kind]!;
  final permitted = {...required, ..._optionalKeys[kind]!};
  for (final key in required) {
    if (!map.containsKey(key)) {
      throw LanMessageException(
          LanRejectReasons.invalidMessage, 'missing field $key');
    }
  }
  final data = <String, String>{};
  for (final entry in map.entries) {
    if (!permitted.contains(entry.key)) {
      throw LanMessageException(
          LanRejectReasons.invalidMessage, 'unexpected field ${entry.key}');
    }
    if (entry.value == null) continue;
    final value = _scalarString(entry.value);
    final limit = switch (entry.key) {
      _ when _textKeys.contains(entry.key) => maxLanBodyChars,
      'senderDeviceName' || 'recipientDeviceName' => maxLanNameChars,
      _ => maxLanFieldChars,
    };
    if (value == null || value.length > limit) {
      throw LanMessageException(
          LanRejectReasons.invalidMessage, 'invalid field ${entry.key}');
    }
    if (!_textKeys.contains(entry.key) && _controlCharacters.hasMatch(value)) {
      throw LanMessageException(
          LanRejectReasons.invalidMessage, 'invalid field ${entry.key}');
    }
    data[entry.key] = value;
  }
  final jobId = data['forwardingJobId'] ?? '';
  if (!_jobIdPattern.hasMatch(jobId)) {
    throw const LanMessageException(
        LanRejectReasons.invalidMessage, 'invalid forwarding job ID');
  }
  if (kind == LanMessageKind.alternativeRequest ||
      kind == LanMessageKind.alternativeResult) {
    final transactionId = int.tryParse(data['transactionId'] ?? '');
    if (transactionId == null || transactionId <= 0) {
      throw const LanMessageException(
          LanRejectReasons.invalidMessage, 'invalid transaction ID');
    }
  }
  if (kind == LanMessageKind.alternativeRequest &&
      (data['ussdCode'] ?? '').trim().isEmpty) {
    throw const LanMessageException(
        LanRejectReasons.invalidMessage, 'empty alternative code');
  }
  if (kind == LanMessageKind.forwardedSms) {
    final transactionId = int.tryParse(data['transactionId'] ?? '');
    if (transactionId == null || transactionId <= 0) {
      throw const LanMessageException(
          LanRejectReasons.invalidMessage, 'invalid transaction ID');
    }
    if ((data['body'] ?? '').trim().isEmpty) {
      throw const LanMessageException(
          LanRejectReasons.invalidMessage, 'empty body');
    }
  }
  final peer = authenticatedPeerDeviceName.trim();
  if (peer.isEmpty || (data['senderDeviceName'] ?? '').trim() != peer) {
    throw const LanMessageException(LanRejectReasons.unexpectedSender,
        'sender is not the authenticated peer');
  }
  final own = ownDeviceName.trim();
  if (own.isEmpty || (data['recipientDeviceName'] ?? '').trim() != own) {
    throw const LanMessageException(LanRejectReasons.unexpectedRecipient,
        'message is not addressed to this device');
  }
  return LanForwardingData(kind, data);
}

final Random _random = Random.secure();

/// 32 lowercase hex characters from a secure random source.
String newLanRequestId() {
  final buffer = StringBuffer();
  for (var i = 0; i < 16; i++) {
    buffer.write(_random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}

bool isValidLanRequestId(Object? value) =>
    value is String && _requestIdPattern.hasMatch(value);
