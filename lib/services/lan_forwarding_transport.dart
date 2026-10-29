import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:bsat/services/forwarding_transport.dart';
import 'package:bsat/services/lan/lan_forwarding_service.dart';
import 'package:bsat/services/lan/lan_messages.dart';
import 'package:bsat/services/sqlite_service.dart';

/// Forwarding over an authenticated LAN session to a paired device.
///
/// Submits the same message the Internet transport submits; only its `data`
/// map travels, exactly as FCM would deliver it. Like every transport it
/// submits once and never retries: callers keep their existing durable
/// schedules and claims.
///
/// [ForwardingSubmissionResult.accepted] is stricter than for the Internet
/// transport, where it only means the backend accepted the request:
///
/// * forwarded SMS: the destination durably claimed the job and its receipt
///   ACK was accepted by the existing receipt validation on this device;
/// * final confirmation: the origin's confirmation receipt arrived (and was
///   processed by the existing handler);
/// * confirmation receipt: the destination handled it.
///
/// It never means that a purchase succeeded.
class LanForwardingTransport implements ForwardingTransport {
  final LanForwardingClient? _client;
  final Future<bool> Function(String forwardingJobId) _isDeliveryAcknowledged;

  LanForwardingTransport({
    LanForwardingClient? client,
    Future<bool> Function(String forwardingJobId)? isDeliveryAcknowledged,
  })  : _client = client,
        _isDeliveryAcknowledged = isDeliveryAcknowledged ??
            ((jobId) => SQLiteService().isForwardingDeliveryAcknowledged(jobId));

  @override
  Future<ForwardingSubmissionResult> submit(
    ForwardingSubmission submission,
  ) async {
    final client = _client ?? LanForwardingService.instance;
    if (client == null) {
      // Not the main isolate: the main isolate owns the LAN identity and
      // runs the whole submission. No main isolate means LAN is unavailable.
      return LanServiceRegistry.submit(submission);
    }
    final data = submission.request['data'];
    final recipient =
        submission.request['recipientDeviceName']?.toString() ?? '';
    if (data is! Map) return _result(false, 'invalid_request');
    final payload = Map<String, dynamic>.from(data);
    final kind = lanMessageKindOf(payload);
    if (kind == null || !lanRequestKinds.contains(kind) || recipient.isEmpty) {
      return _result(false, 'unsupported_message');
    }
    final jobId = payload['forwardingJobId']?.toString() ?? '';
    final finalKinds = lanReplyKindsFor(kind);
    final result = await client.exchange(
      recipientDeviceName: recipient,
      data: payload,
      isFinalReply: (reply) =>
          finalKinds.contains(reply.kind) && reply.forwardingJobId == jobId,
    );
    final completed = result.outcome == LanExchangeOutcome.completed;
    final accepted = switch (kind) {
      LanMessageKind.forwardedSms =>
        completed && await _isDeliveryAcknowledged(jobId),
      _ => completed,
    };
    return _result(accepted, result.outcome.name, reason: result.reason);
  }

  static ForwardingSubmissionResult _result(
    bool accepted,
    String outcome, {
    String? reason,
  }) =>
      ForwardingSubmissionResult(
        accepted: accepted,
        statusCode: null,
        details: {
          'success': accepted,
          'statusCode': null,
          'transport': 'lan',
          'lanOutcome': outcome,
          if (reason != null) 'lanReason': reason,
        },
      );
}

/// Lets other isolates (background service, FCM and SMS background handlers)
/// use the main isolate's [LanForwardingService] through
/// [IsolateNameServer]. When no main isolate is registered, LAN is reported
/// unavailable; nothing falls back to the Internet.
class LanServiceRegistry {
  static const String portName = 'bsat_lan_forwarding_service';
  static const Duration submitTimeout = Duration(seconds: 60);
  /// Covers the main isolate's own probe bound (probe reply plus a whole
  /// 30 s handshake) with some margin.
  static const Duration probeTimeout = Duration(seconds: 45);
  static ReceivePort? _port;

  /// Main isolate only.
  static void register(LanForwardingService service) {
    _port?.close();
    final port = ReceivePort();
    _port = port;
    IsolateNameServer.removePortNameMapping(portName);
    IsolateNameServer.registerPortWithName(port.sendPort, portName);
    port.listen((message) async {
      if (message is! Map) return;
      final reply = message['reply'];
      if (reply is! SendPort) return;
      try {
        switch (message['op']) {
          case 'submit':
            final request = message['request'];
            if (request is! Map) throw ArgumentError('request');
            final result = await LanForwardingTransport(client: service)
                .submit(ForwardingSubmission(Map<String, dynamic>.from(request)));
            reply.send({
              'accepted': result.accepted,
              'details': result.details,
            });
          case 'probe':
            final reachability =
                await service.probe(message['deviceName']?.toString() ?? '');
            reply.send({'reachability': reachability.name});
          default:
            reply.send(null);
        }
      } catch (_) {
        reply.send(null);
      }
    });
  }

  static Future<Object?> _call(
    Map<String, Object?> message,
    Duration timeout,
  ) async {
    final port = IsolateNameServer.lookupPortByName(portName);
    if (port == null) return null;
    final response = ReceivePort();
    try {
      port.send({...message, 'reply': response.sendPort});
      return await response.first.timeout(timeout, onTimeout: () => null);
    } catch (_) {
      return null;
    } finally {
      response.close();
    }
  }

  static Future<ForwardingSubmissionResult> submit(
    ForwardingSubmission submission,
  ) async {
    final response = await _call(
      {'op': 'submit', 'request': submission.request},
      submitTimeout,
    );
    if (response is Map && response['accepted'] is bool) {
      final details = response['details'];
      return ForwardingSubmissionResult(
        accepted: response['accepted'] as bool,
        statusCode: null,
        details: details is Map
            ? Map<String, dynamic>.from(details)
            : const {'transport': 'lan'},
      );
    }
    return LanForwardingTransport._result(false, 'lan_service_unavailable');
  }

  static Future<LanReachability> probe(String deviceName) async {
    final service = LanForwardingService.instance;
    if (service != null) return service.probe(deviceName);
    final response = await _call(
      {'op': 'probe', 'deviceName': deviceName},
      probeTimeout,
    );
    if (response is Map) {
      for (final value in LanReachability.values) {
        if (value.name == response['reachability']) return value;
      }
    }
    return LanReachability.notConfigured;
  }
}
