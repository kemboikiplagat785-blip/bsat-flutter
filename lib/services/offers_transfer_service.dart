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
    'offerName',
  ];

  static const List<String> _allowedVariantColumns = [
    'code',
    'startTime',
    'endTime',
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

    final List<Map<String, dynamic>> variants = await _sqliteService.queryAll(
      'ussdCodeVariants',
      orderBy: 'ussdCodeId ASC, id ASC',
    );

    final Map<int, List<Map<String, dynamic>>> variantsByOfferId = {};
    for (final variant in variants) {
      final cleanedVariant = _sanitizeVariantForTransfer(variant);
      if (cleanedVariant.isEmpty) {
        continue;
      }
      final offerId = int.tryParse(variant['ussdCodeId']?.toString() ?? '') ?? -1;
      variantsByOfferId.putIfAbsent(offerId, () => []).add(cleanedVariant);
    }

    final List<Map<String, dynamic>> serializableOffers = offers
        .map((offer) {
          final cleanedOffer = _sanitizeOfferForTransfer(offer);
          if (cleanedOffer.isEmpty) {
            return <String, dynamic>{};
          }

          final offerId = int.tryParse(offer['id']?.toString() ?? '') ?? -1;
          cleanedOffer['variants'] = variantsByOfferId[offerId] ?? [];
          return cleanedOffer;
        })
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
      await _sqliteService.clearTable('ussdCodeVariants');
    }

    int importedCount = 0;

    for (final offer in parsedOffers) {
      final offerRow = _sanitizeOfferForTransfer(offer);
      if (offerRow.isEmpty) {
        continue;
      }

      final List<Map<String, dynamic>> variantsToInsert = [];
      final dynamic rawVariants = offer['variants'];

      if (rawVariants is List) {
        for (final rawVariant in rawVariants) {
          if (rawVariant is! Map) {
            continue;
          }

          final cleanedVariant = _sanitizeVariantForTransfer(
            Map<String, dynamic>.from(rawVariant),
          );
          if (cleanedVariant.isNotEmpty) {
            variantsToInsert.add(cleanedVariant);
          }
        }
      }

      if (variantsToInsert.isEmpty) {
        final legacyCode = offer['code']?.toString().trim() ?? '';
        if (legacyCode.isNotEmpty) {
          final legacyVariant = _sanitizeVariantForTransfer({
            'code': legacyCode,
            'startTime': offer['startTime'],
            'endTime': offer['endTime'],
            'alternativeUssdCode': offer['alternativeUssdCode'],
            'runAltOn': offer['runAltOn'],
            'altIsAdvanced': offer['altIsAdvanced'],
          });
          if (legacyVariant.isNotEmpty) {
            variantsToInsert.add(legacyVariant);
          }
        }
      }

      if (variantsToInsert.isEmpty) {
        continue;
      }

      final offerId = await _sqliteService.insertStuff(offerRow, 'ussdCodes');

      for (final variant in variantsToInsert) {
        variant['ussdCodeId'] = offerId;
        await _sqliteService.insertStuff(variant, 'ussdCodeVariants');
      }

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
          key == 'bongaPointsPerTransaction') {
        value = int.tryParse(value.toString()) ?? 0;
      }

      cleaned[key] = value;
    }

    if (cleaned['amount'] == null) {
      return {};
    }

    cleaned['enabled'] ??= 1;
    cleaned['canRetry'] ??= 0;
    cleaned['isAdvanced'] ??= 0;

    return cleaned;
  }

  Map<String, dynamic> _sanitizeVariantForTransfer(Map<String, dynamic> row) {
    final Map<String, dynamic> cleaned = {};

    for (final key in _allowedVariantColumns) {
      if (!row.containsKey(key)) {
        continue;
      }

      dynamic value = row[key];
      if (value == null) {
        continue;
      }

      if (key == 'altIsAdvanced') {
        value = int.tryParse(value.toString()) ?? 0;
      }

      cleaned[key] = value;
    }

    if ((cleaned['code']?.toString().trim().isEmpty ?? true)) {
      return {};
    }

    cleaned['altIsAdvanced'] ??= 0;
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
      'ussdCodeVariants',
      'alternativeUssdCode',
      'TEXT',
      defaultValue: 'NULL',
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodeVariants',
      'runAltOn',
      'TEXT',
      defaultValue: 'NULL',
    );
    await _sqliteService.addColumnIfNotExists(
      'ussdCodeVariants',
      'altIsAdvanced',
      'INTEGER',
      defaultValue: 0,
    );
  }
}