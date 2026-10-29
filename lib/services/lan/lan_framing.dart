// LAN forwarding wire framing. Adapted from the BSAT Local Lab prototype
// (lib/src/protocol.dart); only the framing and JSON decoding are kept. The
// prototype's synthetic test-message schema is not used: BSAT messages are
// validated by lan_messages.dart.
//
// Frame layout:
//   [4-byte unsigned big-endian payload length][payload: UTF-8 JSON object]
//
// The payload length excludes the 4-byte header, must be at least 1 byte and
// at most [maxFramePayloadBytes].

import 'dart:convert';
import 'dart:typed_data';

/// Secure protocol version used by handshake frames and by the application
/// messages carried inside encrypted records.
const int secureProtocolVersion = 1;

/// Maximum JSON payload size of one frame (16 KiB). A larger declared length
/// is a fatal protocol error and the connection is closed, because the stream
/// can no longer be trusted to be aligned on frame boundaries.
const int maxFramePayloadBytes = 16 * 1024;

const int frameHeaderBytes = 4;

enum FrameErrorCode { emptyFrame, oversizedFrame, decoderClosed }

class FrameException implements Exception {
  final FrameErrorCode code;
  final String detail;

  const FrameException(this.code, this.detail);

  @override
  String toString() => 'FrameException(${code.name}): $detail';
}

enum ProtocolErrorCode {
  malformedJson,
  notAnObject,
  unsupportedVersion,
  unknownType,
  invalidField,
}

class ProtocolException implements Exception {
  final ProtocolErrorCode code;
  final String detail;

  const ProtocolException(this.code, this.detail);

  String get wireCode => switch (code) {
        ProtocolErrorCode.malformedJson => 'malformed_json',
        ProtocolErrorCode.notAnObject => 'not_an_object',
        ProtocolErrorCode.unsupportedVersion => 'unsupported_version',
        ProtocolErrorCode.unknownType => 'unknown_type',
        ProtocolErrorCode.invalidField => 'invalid_field',
      };

  @override
  String toString() => 'ProtocolException($wireCode): $detail';
}

/// Frames payload bytes exactly as given (used where a transcript must hash
/// the precise bytes that were sent).
Uint8List encodeFramePayload(List<int> payload) {
  if (payload.isEmpty || payload.length > maxFramePayloadBytes) {
    throw FrameException(
      FrameErrorCode.oversizedFrame,
      'Encoded payload is ${payload.length} bytes; '
      'limit is $maxFramePayloadBytes.',
    );
  }
  final frame = Uint8List(frameHeaderBytes + payload.length);
  ByteData.sublistView(frame).setUint32(0, payload.length, Endian.big);
  frame.setRange(frameHeaderBytes, frame.length, payload);
  return frame;
}

/// Encodes one JSON object as a length-prefixed frame.
Uint8List encodeFrame(Map<String, Object?> message) =>
    encodeFramePayload(utf8.encode(jsonEncode(message)));

/// Reassembles frames from arbitrary TCP read boundaries.
///
/// After a [FrameException] the decoder is closed: the remaining stream is
/// unaligned and the caller must close the connection.
class FrameDecoder {
  final int maxPayloadBytes;
  final BytesBuilder _buffer = BytesBuilder(copy: true);
  bool _closed = false;

  FrameDecoder({this.maxPayloadBytes = maxFramePayloadBytes});

  int get bufferedBytes => _buffer.length;

  /// Adds one chunk and returns every complete frame payload it completes.
  List<Uint8List> add(List<int> chunk) {
    if (_closed) {
      throw const FrameException(
        FrameErrorCode.decoderClosed,
        'Decoder was closed after a previous framing error.',
      );
    }
    _buffer.add(chunk);
    final frames = <Uint8List>[];
    var bytes = _buffer.takeBytes();
    var offset = 0;
    while (bytes.length - offset >= frameHeaderBytes) {
      final length = ByteData.sublistView(bytes, offset, offset + 4)
          .getUint32(0, Endian.big);
      if (length == 0) {
        _closed = true;
        throw const FrameException(
          FrameErrorCode.emptyFrame,
          'Frame declares a zero-length payload.',
        );
      }
      if (length > maxPayloadBytes) {
        _closed = true;
        throw FrameException(
          FrameErrorCode.oversizedFrame,
          'Frame declares $length bytes; limit is $maxPayloadBytes.',
        );
      }
      if (bytes.length - offset - frameHeaderBytes < length) break;
      final start = offset + frameHeaderBytes;
      frames.add(Uint8List.fromList(bytes.sublist(start, start + length)));
      offset = start + length;
    }
    if (offset < bytes.length) {
      _buffer.add(bytes.sublist(offset));
    }
    return frames;
  }
}

/// Decodes one frame payload as a JSON object. Throws [ProtocolException].
Map<String, Object?> decodeJsonObject(Uint8List framePayload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(framePayload));
  } on FormatException {
    throw const ProtocolException(
      ProtocolErrorCode.malformedJson,
      'Frame payload is not valid UTF-8 JSON.',
    );
  }
  if (decoded is! Map<String, dynamic>) {
    throw const ProtocolException(
      ProtocolErrorCode.notAnObject,
      'Frame payload is not a JSON object.',
    );
  }
  return decoded;
}
