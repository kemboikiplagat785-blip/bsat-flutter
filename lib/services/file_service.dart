import 'dart:convert';
import 'dart:io';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';

class FileService {
  Future<List> getOffersFromCsv() async {
    FilePickerResult? result = await FilePicker.platform
        .pickFiles(type: FileType.custom, allowedExtensions: ['csv']);
    if (result == null) return [];

    File file = File(result.files.single.path!);
    String csvString = await file.readAsString();

    List<List<dynamic>> csvTable =
        const CsvToListConverter().convert(csvString, eol: '\n');

    List<String> headers = csvTable.first.map((e) => e.toString()).toList();
    List<List<dynamic>> rows = csvTable.sublist(1);

    return [headers, rows];
  }

  Future<void> updateFromFile() async {
    List codes = await getOffersFromCsv();

    if (codes.isEmpty) return;
    List<String> headers = codes[0].map((e) => e.toString()).toList();
    List rows = codes.sublist(1);

    SQLiteService sqLiteService = SQLiteService();
    await sqLiteService.deleteWhere('ussdCodes', 'id > -1', []);

    for (var row in rows) {
      Map<String, dynamic> offer = {};
      for (int i = 0; i < headers.length; i++) {
        offer[headers[i]] = row[i];
      }

      sqLiteService.insertStuff(offer, 'ussdCodes');
    }
  }

  Future<String> createTransactionFile(
    DateTime startDate,
    DateTime endDate,
  ) async {
    SQLiteService sqLiteService = SQLiteService();
    List<Map<String, dynamic>> transactions = await sqLiteService.queryCustom(
      'transactions',
      'date >= ? AND date <= ?',
      [getNormalDate(startDate), getNormalDate(endDate)],
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

    String fileName =
        'BSAT_transactions_${getNormalDate(startDate)}_to_${getNormalDate(endDate)}.csv';

    if (transactions.isEmpty) return "";
    List<String> headers = transactions.first.keys.toList();
    List<List<dynamic>> csvData = [
      headers,
      ...transactions.map((tx) => headers.map((h) => tx[h]).toList())
    ];
    String csvString = const ListToCsvConverter().convert(csvData);
    String filePath = await saveContentToFile(csvString, fileName);

    return filePath;
  }

  static Future<String> downloadOffersToCsv() async {
    // await Permission.accessMediaLocation
    SQLiteService sqLiteService = SQLiteService();
    List<Map<String, dynamic>> offers =
        await sqLiteService.queryAll('ussdCodes');

    String fileName = 'BSAT_offers_${DateTime.now().toIso8601String()}.csv';

    if (offers.isEmpty) return "";
    List<String> headers = offers.first.keys.toList();
    List<List<dynamic>> csvData = [
      headers,
      ...offers.map((offer) => headers.map((h) => offer[h]).toList())
    ];

    String csvString = const ListToCsvConverter().convert(csvData);
    String filePath = await saveContentToFile(csvString, fileName);

    return filePath;
  }

  static Future<String> saveContentToFile(
      String content, String fileName) async {
    try {
      String? outputPath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save your file',
        fileName: fileName,
      );
      if (outputPath == null) return "";
      final file = File(outputPath);
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      await file.writeAsBytes(utf8.encode(content));
      return file.path;
    } catch (e) {
      //print('Error saving file: $e');
      return "";
    }
  }
}
