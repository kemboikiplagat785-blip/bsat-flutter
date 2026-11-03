import 'dart:async';

import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/code_signature.dart';
import 'phone_service.dart';

const String _alternativeUssdRequestEvent = 'executeAlternativeUssd';
const String _alternativeUssdResultEvent = 'alternativeUssdResult';
const String _mainEnginePingEvent = 'mainEnginePing';
const String _mainEnginePongEvent = 'mainEnginePong';

/// Register in the UI isolate. MainActivity owns the `runUssdSequence`
/// MethodChannel, so background service requests must be executed here.
void registerMainEngineAlternativeUssdBridge() {
  final service = FlutterBackgroundService();
  service.on(_mainEnginePingEvent).listen((event) {
    service.invoke(_mainEnginePongEvent, {'requestId': event?['requestId']});
  });
  service.on(_alternativeUssdRequestEvent).listen((event) async {
    if (event == null) return;

    final requestId = event['requestId']?.toString() ?? '';
    final code = event['code']?.toString() ?? '';
    final subscriptionId =
        int.tryParse(event['subscriptionId']?.toString() ?? '') ?? -1;
    final isAdvanced = event['isAdvanced'] == true ||
        event['isAdvanced']?.toString().toLowerCase() == 'true';

    try {
      final signatureData = event['codeSignature'];
      final signature = signatureData is Map
          ? CodeSignature.fromMap(Map<String, dynamic>.from(signatureData))
          : null;
      final result = isAdvanced
          ? await PhoneService().makeAdvancedRequest(
              code,
              subscriptionId,
              codeSignature: signature,
            )
          : await PhoneService().makeMyRequest(code, subscriptionId);

      service.invoke(_alternativeUssdResultEvent, {
        'requestId': requestId,
        'response': result.isNotEmpty ? result.first.toString() : '',
        'status': result.length > 1 ? result[1].toString() : '',
      });
    } catch (error) {
      service.invoke(_alternativeUssdResultEvent, {
        'requestId': requestId,
        'response': 'Alternative USSD execution failed: $error',
        'status': 'alternative-failed',
      });
    }
  });
}

/// Called from the background isolate. False when the main Flutter engine is
/// not running (the app was closed), so nothing can dial an Advanced code.
Future<bool> isMainEngineRunning(ServiceInstance service) async {
  final requestId = DateTime.now().microsecondsSinceEpoch.toString();
  final pong = service
      .on(_mainEnginePongEvent)
      .firstWhere((event) => event?['requestId'] == requestId);
  service.invoke(_mainEnginePingEvent, {'requestId': requestId});
  try {
    await pong.timeout(const Duration(seconds: 3));
    return true;
  } on TimeoutException {
    return false;
  }
}

/// Called from the background isolate. Waits for the main Flutter engine to
/// perform the platform-channel USSD call and return its response.
Future<List<String>> executeAlternativeUssdOnMainEngine({
  required ServiceInstance service,
  required String code,
  required int subscriptionId,
  required bool isAdvanced,
  CodeSignature? codeSignature,
  Duration timeout = const Duration(minutes: 3),
}) async {
  final requestId =
      '${DateTime.now().microsecondsSinceEpoch}_${code.hashCode}';
  final completer = Completer<List<String>>();
  late final StreamSubscription<Map<String, dynamic>?> subscription;

  subscription = service.on(_alternativeUssdResultEvent).listen((event) {
    if (event == null || event['requestId']?.toString() != requestId) return;
    if (!completer.isCompleted) {
      completer.complete([
        event['response']?.toString() ?? '',
        event['status']?.toString() ?? '',
      ]);
    }
  });

  service.invoke(_alternativeUssdRequestEvent, {
    'requestId': requestId,
    'code': code,
    'subscriptionId': subscriptionId,
    'isAdvanced': isAdvanced,
    if (codeSignature != null) 'codeSignature': codeSignature.toMap(),
  });

  try {
    return await completer.future.timeout(timeout);
  } on TimeoutException {
    return [
      'Timed out waiting for the main engine to execute alternative USSD.',
      'alternative-failed',
    ];
  } finally {
    await subscription.cancel();
  }
}
