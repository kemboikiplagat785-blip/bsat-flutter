import 'dart:convert';

import 'package:bsat/services/offers_transfer_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';

import 'lan_forwarding_service.dart';
import 'lan_messages.dart';

/// Why offers could not be downloaded, in words for the user.
class LanOffersDownloadException implements Exception {
  final String message;

  const LanOffersDownloadException(this.message);

  @override
  String toString() => message;
}

/// Splits the offers into pieces that each fit one LAN record. Base64 keeps
/// offer names in any language within the field rules.
List<String> splitOffersForLan(String offersJson) {
  final encoded = base64Encode(utf8.encode(offersJson));
  final chunks = <String>[
    for (var start = 0; start < encoded.length; start += maxLanOffersChunkChars)
      encoded.substring(
        start,
        start + maxLanOffersChunkChars < encoded.length
            ? start + maxLanOffersChunkChars
            : encoded.length,
      ),
  ];
  if (chunks.length > maxLanOffersChunks) {
    throw StateError('Too many offers to send over LAN');
  }
  return chunks;
}

/// The offers from all the [replies] of one download, or null when any piece
/// is missing, out of order or damaged. Nothing partial is ever imported.
String? joinLanOffersChunks(List<LanForwardingData> replies) {
  final chunks = replies.where((r) => r.kind == LanMessageKind.offersChunk);
  if (chunks.isEmpty) return null;
  final total = chunks.first.data['totalParts'];
  final buffer = StringBuffer();
  var expected = 0;
  for (final chunk in chunks) {
    if (chunk.data['part'] != expected.toString() ||
        chunk.data['totalParts'] != total) {
      return null;
    }
    buffer.write(chunk.data['chunk']);
    expected++;
  }
  if (expected.toString() != total) return null;
  try {
    return utf8.decode(base64Decode(buffer.toString()));
  } on FormatException {
    return null;
  }
}

/// The phone being downloaded from: sends its offers back on the session that
/// asked. With "Download offers" off it sends nothing.
Future<void> serveLanOffersRequest(
  LanForwardingData request,
  LanReplySink reply, {
  OffersTransferService? offersTransferService,
  SharedPreferencesService? sharedPreferencesService,
}) async {
  final preferences = sharedPreferencesService ?? SharedPreferencesService();
  if (!(await preferences.getDownloadOffers() ?? true)) return;

  final offers = offersTransferService ?? OffersTransferService();
  final chunks = splitOffersForLan(await offers.exportOffersJson());
  for (var part = 0; part < chunks.length; part++) {
    await reply({
      'data': {
        'type': lanOffersChunkType,
        'forwardingJobId': request.forwardingJobId,
        'senderDeviceName': request.recipientDeviceName,
        'recipientDeviceName': request.senderDeviceName,
        'part': part,
        'totalParts': chunks.length,
        'chunk': chunks[part],
      },
    });
  }
}

/// Downloads the offers of the paired phone [deviceName] and replaces this
/// phone's offers with them. Returns how many were imported; on any failure
/// this phone's offers are left as they were.
Future<int> downloadOffersOverLan({
  required LanForwardingClient client,
  required String ownDeviceName,
  required String deviceName,
  OffersTransferService? offersTransferService,
}) async {
  final jobId = 'offers_${newLanRequestId()}';
  final result = await client.exchange(
    recipientDeviceName: deviceName,
    data: {
      'type': lanOffersRequestType,
      'forwardingJobId': jobId,
      'senderDeviceName': ownDeviceName,
      'recipientDeviceName': deviceName,
    },
    isFinalReply: (reply) =>
        reply.kind == LanMessageKind.offersChunk &&
        int.parse(reply.data['part']!) ==
            int.parse(reply.data['totalParts']!) - 1,
    // The offers are read below, only from this download's own replies.
    onReply: (_, __) async {},
  );
  if (result.outcome != LanExchangeOutcome.completed) {
    throw LanOffersDownloadException(_failureMessage(result, deviceName));
  }

  final offersJson = joinLanOffersChunks(result.replies);
  if (offersJson == null) {
    throw LanOffersDownloadException(
      'The offers from $deviceName arrived incomplete. Please try again.',
    );
  }
  final imported = await (offersTransferService ?? OffersTransferService())
      .importOffersFromPayload(offersJson);
  if (imported == 0) {
    throw LanOffersDownloadException('$deviceName has no offers to download.');
  }
  return imported;
}

String _failureMessage(LanExchangeResult result, String deviceName) =>
    switch (result.outcome) {
      LanExchangeOutcome.noReply =>
        '$deviceName has "Download offers" turned off in Settings.',
      LanExchangeOutcome.refused =>
        result.reason == LanRejectReasons.unsupportedType
            ? 'Update BSAT on $deviceName, then try again.'
            : '$deviceName refused the request.',
      LanExchangeOutcome.notConfigured ||
      LanExchangeOutcome.unpaired =>
        'This phone is not paired with $deviceName over LAN.',
      LanExchangeOutcome.revoked =>
        'The LAN pairing with $deviceName was revoked.',
      LanExchangeOutcome.unreachable =>
        'Could not reach $deviceName. Check that both phones are on the same '
            'network and BSAT is open on $deviceName.',
      LanExchangeOutcome.authenticationFailed =>
        'Could not verify $deviceName. Pair the phones again.',
      _ => 'The download from $deviceName did not finish. Please try again.',
    };
