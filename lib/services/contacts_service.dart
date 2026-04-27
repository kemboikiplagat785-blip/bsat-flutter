import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'backend_service.dart';
import 'shared_preferences_service.dart';

class ContactsService {
  final SharedPreferencesService _sharedPreferencesService =
      SharedPreferencesService();

  Future<String> addNewContact(String name, String phoneNumber) async {
    if (await FlutterContacts.requestPermission()) {
      String postfix =
          await _sharedPreferencesService.getPostfixContactName() ?? "Bingwa";
      final newContact = Contact()
        ..name.first = name
        ..name.last = postfix
        ..phones = [Phone(phoneNumber)];

      await newContact.insert();

      return 'Contact added successfully';
    } else {
      return 'Permission denied';
    }
  }

  // see if contact is already in the phonebook
  Future<bool> contactExists(String phoneNumber) async {
    if (await FlutterContacts.requestPermission()) {
      final contacts = await FlutterContacts.getContacts(withProperties: true);
      return contacts.any((contact) =>
          contact.phones.any((phone) => phone.number == phoneNumber));
    }
    return false;
  }

  Future<List<Contact>> getAllContacts() async {
    if (await FlutterContacts.requestPermission()) {
      return await FlutterContacts.getContacts(withProperties: true);
    }
    return [];
  }

  // Sender methods

  /// Orchestrates the full transfer flow
  Future<String?> startContactsTransfer(String recipientDeviceName) async {
    try {
      // a. Collect and encode
      final json = await exportContactsToJson();
      final payload = gzipAndBase64(json);
      final chunks = splitIntoChunks(payload, 450 * 1024); // ~450 KB chunks

      final myDeviceName = await _sharedPreferencesService.getDeviceName() ?? "Unknown";

      // b. Initialize transfer
      final initResp = await BackendService().post('/api/fcm/contacts-transfer/init', body: {
        "senderDeviceName": myDeviceName,
        "recipientDeviceName": recipientDeviceName,
        "totalChunks": chunks.length,
        "totalContacts": (jsonDecode(json) as List).length,
        "payloadEncoding": "gzip+base64"
      });

      if (initResp['success'] != true) return null;
      final transferId = initResp['data']['transferId'];

      // c. Upload chunks sequentially
      for (int i = 0; i < chunks.length; i++) {
        bool success = false;
        int retries = 0;
        while (!success && retries < 3) {
          final chunkResp = await BackendService().post('/api/fcm/contacts-transfer/chunk', body: {
            "transferId": transferId,
            "chunkIndex": i,
            "chunkData": chunks[i]
          });
          if (chunkResp['success'] == true) {
            success = true;
          } else {
            retries++;
            await Future.delayed(Duration(seconds: 2 * retries));
          }
        }
        if (!success) return null;
      }

      // d. Complete transfer
      final completeResp = await BackendService().post('/api/fcm/contacts-transfer/complete', body: {
        "transferId": transferId
      });

      return completeResp['success'] == true ? transferId : null;
    } catch (e) {
      if (kDebugMode) print('Contacts transfer failed: $e');
      return null;
    }
  }

  Future<String> exportContactsToJson() async {
    final contacts = await getAllContacts();
    final List<Map<String, dynamic>> contactsList = contacts.map((c) => c.toJson()).toList();
    return jsonEncode(contactsList);
  }

  String gzipAndBase64(String json) {
    final bytes = utf8.encode(json);
    final gzipped = gzip.encode(bytes);
    return base64Encode(gzipped);
  }

  List<String> splitIntoChunks(String base64Payload, int maxChunkChars) {
    List<String> chunks = [];
    for (var i = 0; i < base64Payload.length; i += maxChunkChars) {
      int end = i + maxChunkChars;
      if (end > base64Payload.length) end = base64Payload.length;
      chunks.add(base64Payload.substring(i, end));
    }
    return chunks;
  }

  // Receiver methods

  Future<void> handleTransferReady(String transferId) async {
    try {
      // e. Download transfer
      final downloadResp = await BackendService().get('/api/fcm/contacts-transfer/$transferId/download');
      if (downloadResp['success'] == true) {
        final payloadData = downloadResp['data']['payloadData'];
        // totalContacts and payloadEncoding are also available if needed
        
        final jsonStr = decodeAndUngzip(payloadData);
        final List contactsJson = jsonDecode(jsonStr);
        await importContacts(contactsJson);
      }
    } catch (e) {
      if (kDebugMode) print('Failed to handle transfer ready: $e');
    }
  }

  String decodeAndUngzip(String payloadData) {
    final bytes = base64Decode(payloadData);
    final ungzipped = gzip.decode(bytes);
    return utf8.decode(ungzipped);
  }

  Future<void> importContacts(List contactsJson) async {
    if (await FlutterContacts.requestPermission()) {
      for (var contactMap in contactsJson) {
        try {
          final contact = Contact.fromJson(Map<String, dynamic>.from(contactMap));
          // Use insert to write locally. 
          // Note: IDs from sender might conflict if we don't clear them, 
          // but flutter_contacts insert() usually handles new creation.
          await contact.insert();
        } catch (e) {
          if (kDebugMode) print('Error importing contact: $e');
        }
      }
    }
  }
}
