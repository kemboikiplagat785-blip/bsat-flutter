import 'dart:convert';

import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/foundation.dart';

class OffersTransferService {
  final SQLiteService _sqliteService = SQLiteService();
  final SharedPreferencesService _sharedPreferencesService =
      SharedPreferencesService();

  static const List<String> _allowedOfferColumns = [
    'code',
    'amount',
    'fromSim',
    'dialSim',
    'canRetry',
    'isAdvanced',
    'enabled',
    'usesBongaPoints',
    'fallbackCode',
    'balanceCheckCode',
    'bongaPointsPerTransaction',
    'alternativeUssdCode',
    'runAltOn',
    'altIsAdvanced',
  ];

  Future<Map<String, dynamic>> requestOffersFromDevice(
    String recipientDeviceName,
  ) async {
    final String myDeviceName =
        await _sharedPreferencesService.getDeviceName() ??
            'Unknown Device ${DateTime.now().millisecondsSinceEpoch}';
    final String requestId = DateTime.now().millisecondsSinceEpoch.toString();

    return BackendService().post(
      '/api/fcm/send-secure',
      body: {
        'title': 'BSAT Offers Request',
        'body': 'Requesting offers from $recipientDeviceName',
        'senderDeviceName': myDeviceName,
        'recipientDeviceName': recipientDeviceName,
        'data': {
          'type': 'OFFERS_REQUEST',
          'requesterDeviceName': myDeviceName,
          'requestId': requestId,
        },
      },
    );
  }

  Future<Map<String, dynamic>> sendOffersToDevice(
    String recipientDeviceName, {
    String? requestId,
  }) async {
    final String myDeviceName =
        await _sharedPreferencesService.getDeviceName() ??
            'Unknown Device ${DateTime.now().millisecondsSinceEpoch}';

    final List<Map<String, dynamic>> offers = await _sqliteService.queryAll(
      'ussdCodes',
      orderBy: 'id ASC',
    );

    final List<Map<String, dynamic>> serializableOffers = offers
        .map(_sanitizeOfferForTransfer)
        .where((row) => row.isNotEmpty)
        .toList();

    return BackendService().post(
      '/api/fcm/send-secure',
      body: {
        'title': 'BSAT Offers Transfer',
        'body': 'Offers from $myDeviceName',
        'senderDeviceName': myDeviceName,
        'recipientDeviceName': recipientDeviceName,
        'data': {
          'type': 'OFFERS_RESPONSE',
          'requestId': requestId,
          'senderDeviceName': myDeviceName,
          'offers': jsonEncode(serializableOffers),
        },
      },
    );
  }

  Future<int> importOffersFromPayload(
    dynamic rawOffers, {
    bool replaceExisting = true,
  }) async {
    final List<Map<String, dynamic>> parsedOffers = _parseOffers(rawOffers);

    if (parsedOffers.isEmpty) {
      return 0;
    }

    await _ensureOfferColumnsExist();

    if (replaceExisting) {
      await _sqliteService.clearTable('ussdCodes');
    }

    int importedCount = 0;

    for (final offer in parsedOffers) {
      final row = _sanitizeOfferForTransfer(offer);
      if (row.isEmpty) {
        continue;
      }

      await _sqliteService.insertStuff(row, 'ussdCodes');
      importedCount++;
    }

    await _sharedPreferencesService.setOffersMightHaveChanged(true);
    return importedCount;
  }

  List<Map<String, dynamic>> _parseOffers(dynamic rawOffers) {
    dynamic offersData = rawOffers;

    if (rawOffers is String) {
      try {
        offersData = jsonDecode(rawOffers);
      } catch (e) {
        if (kDebugMode) {
          print('Failed to parse offers payload: $e');
        }
        return [];
      }
    }

    if (offersData is! List) {
      return [];
    }

    return offersData
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  Map<String, dynamic> _sanitizeOfferForTransfer(Map<String, dynamic> row) {
    final Map<String, dynamic> cleaned = {};

    for (final key in _allowedOfferColumns) {
      if (!row.containsKey(key)) {
        continue;
      }

      dynamic value = row[key];

      if (value == null) {
        continue;
      }

      if (key == 'amount' ||
          key == 'fromSim' ||
          key == 'dialSim' ||
          key == 'canRetry' ||
          key == 'isAdvanced' ||
          key == 'enabled' ||
          key == 'usesBongaPoints' ||
          key == 'bongaPointsPerTransaction' ||
          key == 'altIsAdvanced') {
        value = int.tryParse(value.toString()) ?? 0;
      }

      cleaned[key] = value;
    }

    if ((cleaned['code']?.toString().trim().isEmpty ?? true) ||
        (cleaned['amount'] == null)) {
      return {};
    }

    cleaned['enabled'] ??= 1;
    cleaned['canRetry'] ??= 0;
    cleaned['isAdvanced'] ??= 0;

    return cleaned;
  }

  Future<void> _ensureOfferColumnsExist() async {
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'enabled',
      'INTEGER',
      defaultValue: 1,
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'isAdvanced',
      'INTEGER',
      defaultValue: 0,
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'usesBongaPoints',
      'INTEGER',
      defaultValue: 0,
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'fallbackCode',
      'TEXT',
      defaultValue: 'NULL',
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'balanceCheckCode',
      'TEXT',
      defaultValue: 'NULL',
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'bongaPointsPerTransaction',
      'INTEGER',
      defaultValue: 0,
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'alternativeUssdCode',
      'TEXT',
      defaultValue: 'NULL',
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'runAltOn',
      'TEXT',
      defaultValue: 'NULL',
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'altIsAdvanced',
      'INTEGER',
      defaultValue: 0,
    );
  }
}
