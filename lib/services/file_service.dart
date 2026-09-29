import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:typed_data';

import 'package:bsat/services/offers_transfer_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

class FileService {
  // ---------------------------------------------------------------------------
  // OFFERS - IMPORT
  // ---------------------------------------------------------------------------

  Future<String?> _pickOfferFile() async {
    final FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'vcf'],
    );

    if (result == null || result.files.single.path == null) {
      return null;
    }

    return result.files.single.path;
  }

  Future<List> getOffersFromCsv() async {
    final String? path = await _pickOfferFile();

    if (path == null) return [];

    final String extension = path.split('.').last.toLowerCase();

    if (extension != 'csv') {
      return [];
    }

    final File file = File(path);
    final String csvString = await file.readAsString();

    final List<List<dynamic>> csvTable = const CsvToListConverter().convert(
      csvString,
      eol: '\n',
    );

    if (csvTable.isEmpty) return [];

    final List<String> headers =
        csvTable.first.map((e) => e.toString()).toList();

    final List<List<dynamic>> rows =
        csvTable.length > 1 ? csvTable.sublist(1) : [];

    return [headers, rows];
  }

  Future<List<Map<String, dynamic>>> _getOffersFromCsvFile(
    String path,
  ) async {
    final File file = File(path);
    final String csvString = await file.readAsString();

    final List<List<dynamic>> csvTable = const CsvToListConverter().convert(
      csvString,
      eol: '\n',
    );

    if (csvTable.isEmpty) return [];

    final List<String> headers =
        csvTable.first.map((e) => e.toString().trim()).toList();

    final List<List<dynamic>> rows =
        csvTable.length > 1 ? csvTable.sublist(1) : [];

    final List<Map<String, dynamic>> offers = [];

    for (final row in rows) {
      if (row.isEmpty) continue;

      final Map<String, dynamic> offer = {};

      for (int i = 0; i < headers.length && i < row.length; i++) {
        final String header = headers[i];

        if (header.isEmpty) continue;

        offer[header] = row[i];
      }

      if (offer.isNotEmpty) {
        offers.add(offer);
      }
    }

    return offers;
  }

  // ---------------------------------------------------------------------------
  // OFFERS - VCF HELPERS
  // ---------------------------------------------------------------------------

  String _unescapeVcfText(String value) {
    return value
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\N', '\n')
        .replaceAll(r'\;', ';')
        .replaceAll(r'\,', ',')
        .replaceAll(r'\\', '\\');
  }

  Map<String, dynamic>? _decodeOfferPayload(String value) {
    try {
      final String cleaned = value.trim();

      if (cleaned.isEmpty) return null;

      final List<int> bytes = base64Url.decode(cleaned);
      final String jsonString = utf8.decode(bytes);

      final dynamic decoded = jsonDecode(jsonString);

      if (decoded is! Map) return null;

      return Map<String, dynamic>.from(decoded);
    } catch (e) {
      log(
        'Failed to decode BSAT VCF offer payload: $e',
        name: 'FileService',
      );
      return null;
    }
  }

  String? _getVcfProperty(
    Map<String, String> properties,
    String property,
  ) {
    for (final entry in properties.entries) {
      final String key = entry.key.split(';').first.toUpperCase();

      if (key == property.toUpperCase()) {
        return entry.value;
      }
    }

    return null;
  }

  List<Map<String, String>> _parseVcfCards(String content) {
    final List<Map<String, String>> cards = [];

    final List<String> lines =
        content.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

    Map<String, String>? currentCard;

    for (String rawLine in lines) {
      final String line = rawLine.trimRight();

      if (line.toUpperCase() == 'BEGIN:VCARD') {
        currentCard = {};
        continue;
      }

      if (line.toUpperCase() == 'END:VCARD') {
        if (currentCard != null) {
          cards.add(currentCard);
        }

        currentCard = null;
        continue;
      }

      if (currentCard == null || line.isEmpty) continue;

      final int separator = line.indexOf(':');

      if (separator <= 0) continue;

      final String key = line.substring(0, separator).trim();
      final String value = line.substring(separator + 1);

      currentCard[key] = value;
    }

    return cards;
  }

  List<Map<String, dynamic>> _parseOffersFromVcf(String content) {
    final List<Map<String, String>> cards = _parseVcfCards(content);

    final List<Map<String, dynamic>> offers = [];

    for (final card in cards) {
      final String? encodedPayload = _getVcfProperty(
        card,
        'X-BSAT-DATA',
      );

      if (encodedPayload != null && encodedPayload.isNotEmpty) {
        final Map<String, dynamic>? decoded =
            _decodeOfferPayload(encodedPayload);

        if (decoded != null) {
          offers.add(decoded);
          continue;
        }
      }

      // -----------------------------------------------------------------------
      // Legacy / human-readable VCF fallback.
      //
      // This allows VCF files created by the previous exporter to still be
      // recognized, although those old files cannot contain variant codes.
      // -----------------------------------------------------------------------

      final String? fn = _getVcfProperty(card, 'FN');
      final String? note = _getVcfProperty(card, 'NOTE');

      final Map<String, dynamic> offer = {};

      if (fn != null && fn.trim().isNotEmpty) {
        offer['offerName'] = _unescapeVcfText(fn).trim();
      }

      if (note != null) {
        final String decodedNote = _unescapeVcfText(note);

        for (final String rawPart in decodedNote.split('\n')) {
          final String part = rawPart.trim();

          final int separator = part.indexOf(':');

          if (separator <= 0) continue;

          final String label =
              part.substring(0, separator).trim().toLowerCase();

          final String value = part.substring(separator + 1).trim();

          switch (label) {
            case 'amount':
              offer['amount'] = int.tryParse(value) ?? value;
              break;

            case 'from sim':
              offer['fromSim'] = int.tryParse(value) ?? value;
              break;

            case 'dial sim':
              offer['dialSim'] = int.tryParse(value) ?? value;
              break;

            case 'fallback code':
              offer['fallbackCode'] = value;
              break;

            case 'balance check code':
              offer['balanceCheckCode'] = value;
              break;

            case 'start time':
              offer['startTime'] = value;
              break;

            case 'end time':
              offer['endTime'] = value;
              break;
          }
        }
      }

      if (offer.isNotEmpty) {
        offers.add(offer);
      }
    }

    return offers;
  }

  Future<List<Map<String, dynamic>>> _getOffersFromVcfFile(
    String path,
  ) async {
    final File file = File(path);

    final String content = await file.readAsString();

    return _parseOffersFromVcf(content);
  }

  // ---------------------------------------------------------------------------
  // OFFERS - UPDATE FROM FILE
  // ---------------------------------------------------------------------------

  Future<void> updateFromFile() async {
    final String? path = await _pickOfferFile();

    if (path == null) return;

    final String extension = path.split('.').last.toLowerCase();

    List<Map<String, dynamic>> offers;

    if (extension == 'vcf') {
      offers = await _getOffersFromVcfFile(path);
    } else if (extension == 'csv') {
      offers = await _getOffersFromCsvFile(path);
    } else {
      throw Exception(
        'Unsupported offer file format: .$extension',
      );
    }

    if (offers.isEmpty) {
      throw Exception(
        'No valid offers were found in the selected file.',
      );
    }

    final int importedCount =
        await OffersTransferService().importOffersFromPayload(
      offers,
      replaceExisting: true,
    );

    if (importedCount == 0) {
      throw Exception(
        'No offers containing valid USSD codes were imported.',
      );
    }

    log(
      'Imported $importedCount offers from .$extension file',
      name: 'FileService',
    );
  }

  // ---------------------------------------------------------------------------
  // TRANSACTIONS
  // ---------------------------------------------------------------------------

  Future<String> createTransactionFile(
    DateTime startDate,
    DateTime endDate,
  ) async {
    final SQLiteService sqLiteService = SQLiteService();

    final List<Map<String, dynamic>> transactions =
        await sqLiteService.queryCustom(
      'transactions',
      'date >= ? AND date <= ?',
      [
        getNormalDate(startDate),
        getNormalDate(endDate),
      ],
      columns: [
        'id',
        'source',
        'number',
        'amount',
        'date',
        'time',
        'timeStamp',
        'transactionId',
      ],
    );

    final String fileName =
        'BSAT_transactions_${getNormalDate(startDate)}_to_${getNormalDate(endDate)}.csv';

    if (transactions.isEmpty) return "";

    final List<String> headers = transactions.first.keys.toList();

    final List<List<dynamic>> csvData = [
      headers,
      ...transactions.map(
        (tx) => headers.map((h) => tx[h]).toList(),
      ),
    ];

    final String csvString = const ListToCsvConverter().convert(csvData);

    return await saveContentToFile(
      csvString,
      fileName,
    );
  }

  // ---------------------------------------------------------------------------
  // OFFERS - CSV EXPORT
  // ---------------------------------------------------------------------------

  static Future<String> downloadOffersToCsv() async {
    final SQLiteService sqLiteService = SQLiteService();

    final List<Map<String, dynamic>> offers =
        await sqLiteService.queryAll('ussdCodes');

    final String fileName =
        'BSAT_offers_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';

    if (offers.isEmpty) return "";

    final List<String> headers = offers.first.keys.toList();

    final List<List<dynamic>> csvData = [
      headers,
      ...offers.map(
        (offer) => headers.map((h) => offer[h]).toList(),
      ),
    ];

    final String csvString = const ListToCsvConverter().convert(csvData);

    return await saveContentToFile(
      csvString,
      fileName,
    );
  }

  // ---------------------------------------------------------------------------
  // OFFERS - VCF EXPORT
  // ---------------------------------------------------------------------------

  static Future<String> downloadOffersToVcf() async {
    final SQLiteService sqLiteService = SQLiteService();

    final List<Map<String, dynamic>> offers = await sqLiteService.queryAll(
      'ussdCodes',
      orderBy: 'id ASC',
    );

    final List<Map<String, dynamic>> variants = await sqLiteService.queryAll(
      'ussdCodeVariants',
      orderBy: 'ussdCodeId ASC, id ASC',
    );

    if (offers.isEmpty) return "";

    final String fileName =
        'BSAT_offers_${DateTime.now().toIso8601String().replaceAll(':', '-')}.vcf';

    final Map<int, List<Map<String, dynamic>>> variantsByOfferId = {};

    for (final variant in variants) {
      final int offerId = int.tryParse(
            variant['ussdCodeId']?.toString() ?? '',
          ) ??
          -1;

      if (offerId < 0) continue;

      variantsByOfferId.putIfAbsent(offerId, () => []).add({
        'code': variant['code'],
        'startTime': variant['startTime'],
        'endTime': variant['endTime'],
        'alternativeUssdCode': variant['alternativeUssdCode'],
        'runAltOn': variant['runAltOn'],
        'altIsAdvanced': variant['altIsAdvanced'],
        'altDelayMinutes': variant['altDelayMinutes'],
      });
    }

    final StringBuffer vcfContent = StringBuffer();

    try {
      for (final offer in offers) {
        final int offerId = int.tryParse(
              offer['id']?.toString() ?? '',
            ) ??
            -1;

        final String offerName =
            offer['offerName']?.toString().trim().isNotEmpty == true
                ? offer['offerName'].toString().trim()
                : 'BSAT Offer';

        final Map<String, dynamic> payload = {
          'amount': offer['amount'],
          'fromSim': offer['fromSim'],
          'dialSim': offer['dialSim'],
          'canRetry': offer['canRetry'],
          'isAdvanced': offer['isAdvanced'],
          'enabled': offer['enabled'],
          'usesBongaPoints': offer['usesBongaPoints'],
          'fallbackCode': offer['fallbackCode'],
          'balanceCheckCode': offer['balanceCheckCode'],
          'bongaPointsPerTransaction': offer['bongaPointsPerTransaction'],
          'offerName': offer['offerName'],
          'startTime': offer['startTime'],
          'endTime': offer['endTime'],
          'variants': variantsByOfferId[offerId] ?? [],
        };

        final String encodedPayload = base64UrlEncode(
          utf8.encode(
            jsonEncode(payload),
          ),
        );

        final String escapedName = offerName
            .replaceAll('\\', '\\\\')
            .replaceAll('\n', '\\n')
            .replaceAll('\r', '')
            .replaceAll(';', '\\;')
            .replaceAll(',', '\\,');

        vcfContent.writeln('BEGIN:VCARD');
        vcfContent.writeln('VERSION:3.0');
        vcfContent.writeln('FN:$escapedName');
        vcfContent.writeln('N:$escapedName;;;;');
        vcfContent.writeln('X-BSAT-DATA:$encodedPayload');
        vcfContent.writeln('END:VCARD');
      }

      return await saveContentToFile(
        vcfContent.toString(),
        fileName,
      );
    } catch (e) {
      log(
        'Error generating offers VCF: $e',
        name: 'FileService',
      );

      return "";
    }
  }

  // ---------------------------------------------------------------------------
  // CLIENTS
  // ---------------------------------------------------------------------------

  static Future<String> downloadClientsToCsv() async {
    final SQLiteService sqLiteService = SQLiteService();

    final List<Map<String, dynamic>> clients =
        await sqLiteService.queryAll('clients');

    if (clients.isEmpty) return "";

    final String fileName =
        'BSAT_clients_${DateTime.now().toIso8601String().replaceAll(':', '-')}.csv';

    final List<String> headers = clients.first.keys.toList();

    final List<List<dynamic>> csvData = [
      headers,
      ...clients.map(
        (client) => headers.map((h) => client[h]).toList(),
      ),
    ];

    final String csvString = const ListToCsvConverter().convert(csvData);

    return await saveContentToFile(
      csvString,
      fileName,
    );
  }

  static Future<String> downloadClientsToJson() async {
    final SQLiteService sqLiteService = SQLiteService();

    final List<Map<String, dynamic>> clients =
        await sqLiteService.queryAll('clients');

    if (clients.isEmpty) return "";

    final String fileName =
        'BSAT_clients_${DateTime.now().toIso8601String().replaceAll(':', '-')}.json';

    final String jsonString = jsonEncode(clients);

    return await saveContentToFile(
      jsonString,
      fileName,
    );
  }

  static Future<String> downloadClientsToVcf() async {
    final SQLiteService sqLiteService = SQLiteService();

    final List<Map<String, dynamic>> clients =
        await sqLiteService.queryAll('clients');

    if (clients.isEmpty) return "";

    final String fileName =
        'BSAT_clients_${DateTime.now().toIso8601String().replaceAll(':', '-')}.vcf';

    final StringBuffer vcfContent = StringBuffer();

    try {
      for (final client in clients) {
        vcfContent.writeln('BEGIN:VCARD');
        vcfContent.writeln('VERSION:3.0');

        final String firstName = client['firstName']?.toString() ?? '';

        final String lastName = client['lastName']?.toString() ?? '';

        final String phone = client['phoneNumber']?.toString() ?? '';

        final String altPhone =
            client['alternativePhoneNumber']?.toString() ?? '';

        vcfContent.writeln(
          'N:$lastName;$firstName;;;',
        );

        vcfContent.writeln(
          'FN:${firstName.trim()} ${lastName.trim()}'.trim(),
        );

        if (phone.isNotEmpty) {
          vcfContent.writeln(
            'TEL;TYPE=CELL:$phone',
          );
        }

        if (altPhone.isNotEmpty) {
          vcfContent.writeln(
            'TEL;TYPE=HOME:$altPhone',
          );
        }

        vcfContent.writeln('END:VCARD');
      }

      log(
        "Generated client VCF content",
        name: 'FileService',
      );

      return await saveContentToFile(
        vcfContent.toString(),
        fileName,
      );
    } catch (e) {
      log(
        'Error generating VCF: $e',
        name: 'FileService',
      );
    }

    return "";
  }

  // ---------------------------------------------------------------------------
  // SAVE FILE
  // ---------------------------------------------------------------------------

  static Future<String> saveContentToFile(
    String content,
    String fileName,
  ) async {
    try {
      final Uint8List bytes = Uint8List.fromList(
        utf8.encode(content),
      );

      final String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your file',
        fileName: fileName,
        bytes: bytes,
      );

      if (outputPath == null) return "";

      if (!Platform.isAndroid && !Platform.isIOS) {
        final File file = File(outputPath);

        if (!await file.exists()) {
          await file.create(recursive: true);
        }

        await file.writeAsBytes(bytes);
      }

      return outputPath;
    } catch (e) {
      log(
        'Error saving file: $e',
        name: 'FileService',
      );

      return "";
    }
  }
}
