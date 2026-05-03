import 'dart:convert';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'sqlite_service.dart';
import 'shared_preferences_service.dart';

class FirebaseSyncService {
  final SQLiteService _sqliteService = SQLiteService();
  final SharedPreferencesService _sharedPreferencesService =
      SharedPreferencesService();
  final FirebaseDatabase _database = FirebaseDatabase.instance;

  // Get user-specific path
  String get _userPath => 'users/${_getUserId()}';

  String _getUserId() {
    // You can use Firebase Auth user ID or device ID
    // For now, using a simple device identifier
    return 'device_${DateTime.now().millisecondsSinceEpoch}'; // TODO: Replace with actual user ID
  }

  // Sync transactions to Firebase
  Future<void> syncTransactionsToFirebase() async {
    try {
      final transactions = await _sqliteService.queryAll('transactions');
      final ref = _database.ref('$_userPath/transactions');

      // Convert to map with ID as key
      Map<String, dynamic> transactionsMap = {};
      for (var transaction in transactions) {
        transactionsMap[transaction['id'].toString()] = transaction;
      }

      await ref.set(transactionsMap);
      debugPrint(
          'Transactions synced to Firebase: ${transactions.length} records');
    } catch (e) {
      debugPrint('Error syncing transactions to Firebase: $e');
    }
  }

  // Sync USSD codes to Firebase
  Future<void> syncUssdCodesToFirebase() async {
    try {
      final ussdCodes = await _sqliteService.queryAll('ussdCodes');
      final ref = _database.ref('$_userPath/ussdCodes');

      Map<String, dynamic> ussdCodesMap = {};
      for (var code in ussdCodes) {
        ussdCodesMap[code['id'].toString()] = code;
      }

      await ref.set(ussdCodesMap);
      debugPrint('USSD codes synced to Firebase: ${ussdCodes.length} records');
    } catch (e) {
      debugPrint('Error syncing USSD codes to Firebase: $e');
    }
  }

  // Sync clients to Firebase
  Future<void> syncClientsToFirebase() async {
    try {
      final clients = await _sqliteService.queryAll('clients');
      final ref = _database.ref('$_userPath/clients');

      Map<String, dynamic> clientsMap = {};
      for (var client in clients) {
        clientsMap[client['id'].toString()] = client;
      }

      await ref.set(clientsMap);
      debugPrint('Clients synced to Firebase: ${clients.length} records');
    } catch (e) {
      debugPrint('Error syncing clients to Firebase: $e');
    }
  }

  // Sync settings to Firebase
  Future<void> syncSettingsToFirebase() async {
    try {
      final settings = {
        'autoSaveContacts':
            await _sharedPreferencesService.getAutoSaveContacts(),
        'autoDeleteAfterNumberOfDays':
            await _sharedPreferencesService.getAutoDeleteAfterNumberOfDays(),
        'offersMightHaveChanged':
            await _sharedPreferencesService.getOffersMightHaveChanged(),
        'downloadOffers': await _sharedPreferencesService.getDownloadOffers(),
        'autoRenew': await _sharedPreferencesService.getAutoRenew(),
        'deliveryTokens': await _sharedPreferencesService.getDeliveryTokens(),
        'retryMinutes': await _sharedPreferencesService.getRetryMinutes(),
        'appIsActiveState':
            await _sharedPreferencesService.getAppIsActiveState(),
        'smsRunning': await _sharedPreferencesService.isSmsRunning(),
        'dataRunning': await _sharedPreferencesService.isDataRunning(),
        'lastSyncTime': DateTime.now().millisecondsSinceEpoch,
      };

      final ref = _database.ref('$_userPath/settings');
      await ref.set(settings);
      debugPrint('Settings synced to Firebase');
    } catch (e) {
      debugPrint('Error syncing settings to Firebase: $e');
    }
  }

  // Download transactions from Firebase
  Future<void> downloadTransactionsFromFirebase() async {
    try {
      final ref = _database.ref('$_userPath/transactions');
      final snapshot = await ref.get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        for (var entry in data.entries) {
          final transaction = Map<String, dynamic>.from(entry.value);

          // Check if transaction already exists
          final existing = await _sqliteService.queryCustom(
            'transactions',
            'id = ?',
            [int.tryParse(entry.key) ?? 0],
          );

          if (existing.isEmpty) {
            // Remove ID to let SQLite auto-increment
            transaction.remove('id');
            await _sqliteService.insertStuff(transaction, 'transactions');
          }
        }

        debugPrint(
            'Transactions downloaded from Firebase: ${data.length} records');
      }
    } catch (e) {
      debugPrint('Error downloading transactions from Firebase: $e');
    }
  }

  // Download USSD codes from Firebase
  Future<void> downloadUssdCodesFromFirebase() async {
    try {
      final ref = _database.ref('$_userPath/ussdCodes');
      final snapshot = await ref.get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        for (var entry in data.entries) {
          final ussdCode = Map<String, dynamic>.from(entry.value);

          // Check if USSD code already exists
          final existing = await _sqliteService.queryCustom(
            'ussdCodes',
            'id = ?',
            [int.tryParse(entry.key) ?? 0],
          );

          if (existing.isEmpty) {
            ussdCode.remove('id');
            await _sqliteService.insertStuff(ussdCode, 'ussdCodes');
          }
        }

        debugPrint(
            'USSD codes downloaded from Firebase: ${data.length} records');
      }
    } catch (e) {
      debugPrint('Error downloading USSD codes from Firebase: $e');
    }
  }

  // Download clients from Firebase
  Future<void> downloadClientsFromFirebase() async {
    try {
      final ref = _database.ref('$_userPath/clients');
      final snapshot = await ref.get();

      if (snapshot.exists) {
        final data = Map<String, dynamic>.from(snapshot.value as Map);

        for (var entry in data.entries) {
          final client = Map<String, dynamic>.from(entry.value);

          // Check if client already exists by phone number
          final existing = await _sqliteService.queryCustom(
            'clients',
            'phoneNumber = ?',
            [client['phoneNumber']],
          );

          if (existing.isEmpty) {
            client.remove('id');
            await _sqliteService.insertStuff(client, 'clients');
          }
        }

        debugPrint('Clients downloaded from Firebase: ${data.length} records');
      }
    } catch (e) {
      debugPrint('Error downloading clients from Firebase: $e');
    }
  }

  // Download settings from Firebase
  Future<void> downloadSettingsFromFirebase() async {
    try {
      final ref = _database.ref('$_userPath/settings');
      final snapshot = await ref.get();

      if (snapshot.exists) {
        final settings = Map<String, dynamic>.from(snapshot.value as Map);

        // Apply settings
        if (settings['autoSaveContacts'] != null) {
          await _sharedPreferencesService
              .setAutoSaveContacts(settings['autoSaveContacts']);
        }
        if (settings['autoDeleteAfterNumberOfDays'] != null) {
          await _sharedPreferencesService.setAutoDeleteAfterNumberOfDays(
              settings['autoDeleteAfterNumberOfDays']);
        }
        if (settings['offersMightHaveChanged'] != null) {
          await _sharedPreferencesService
              .setOffersMightHaveChanged(settings['offersMightHaveChanged']);
        }
        if (settings['downloadOffers'] != null) {
          await _sharedPreferencesService
              .setDownloadOffers(settings['downloadOffers']);
        }
        if (settings['autoRenew'] != null) {
          await _sharedPreferencesService.setAutoRenew(settings['autoRenew']);
        }
        if (settings['deliveryTokens'] != null) {
          await _sharedPreferencesService
              .setDeliveryTokens(settings['deliveryTokens']);
        }
        if (settings['retryMinutes'] != null) {
          await _sharedPreferencesService
              .setRetryMinutes(settings['retryMinutes']);
        }
        if (settings['appIsActiveState'] != null) {
          await _sharedPreferencesService
              .setAppIsActiveState(settings['appIsActiveState']);
        }

        debugPrint('Settings downloaded from Firebase');
      }
    } catch (e) {
      debugPrint('Error downloading settings from Firebase: $e');
    }
  }

  // Full sync - upload all data to Firebase
  Future<void> fullSyncToFirebase() async {
    debugPrint('Starting full sync to Firebase...');
    await Future.wait([
      syncTransactionsToFirebase(),
      syncUssdCodesToFirebase(),
      syncClientsToFirebase(),
      syncSettingsToFirebase(),
    ]);
    debugPrint('Full sync to Firebase completed');
  }

  // Full sync - download all data from Firebase
  Future<void> fullSyncFromFirebase() async {
    debugPrint('Starting full sync from Firebase...');
    await Future.wait([
      downloadTransactionsFromFirebase(),
      downloadUssdCodesFromFirebase(),
      downloadClientsFromFirebase(),
      downloadSettingsFromFirebase(),
    ]);
    debugPrint('Full sync from Firebase completed');
  }

  // Real-time sync - listen for changes
  void startRealtimeSync() {
    // Listen for transaction changes
    _database.ref('$_userPath/transactions').onChildAdded.listen((event) {
      _handleTransactionAdded(event.snapshot);
    });

    // Listen for USSD code changes
    _database.ref('$_userPath/ussdCodes').onChildAdded.listen((event) {
      _handleUssdCodeAdded(event.snapshot);
    });

    // Listen for settings changes
    _database.ref('$_userPath/settings').onValue.listen((event) {
      _handleSettingsChanged(event.snapshot);
    });

    debugPrint('Real-time sync started');
  }

  void _handleTransactionAdded(DataSnapshot snapshot) async {
    try {
      if (snapshot.exists) {
        final transaction = Map<String, dynamic>.from(snapshot.value as Map);

        // Check if transaction already exists
        final existing = await _sqliteService.queryCustom(
          'transactions',
          'transactionId = ? AND number = ? AND timeStamp = ?',
          [
            transaction['transactionId'],
            transaction['number'],
            transaction['timeStamp'],
          ],
        );

        if (existing.isEmpty) {
          transaction.remove('id');
          await _sqliteService.insertStuff(transaction, 'transactions');
          debugPrint('New transaction synced from Firebase');
        }
      }
    } catch (e) {
      debugPrint('Error handling transaction added: $e');
    }
  }

  void _handleUssdCodeAdded(DataSnapshot snapshot) async {
    try {
      if (snapshot.exists) {
        final ussdCode = Map<String, dynamic>.from(snapshot.value as Map);

        // Check if USSD code already exists
        final existing = await _sqliteService.queryCustom(
          'ussdCodes',
          'code = ? AND amount = ?',
          [ussdCode['code'], ussdCode['amount']],
        );

        if (existing.isEmpty) {
          ussdCode.remove('id');
          await _sqliteService.insertStuff(ussdCode, 'ussdCodes');
          debugPrint('New USSD code synced from Firebase');
        }
      }
    } catch (e) {
      debugPrint('Error handling USSD code added: $e');
    }
  }

  void _handleSettingsChanged(DataSnapshot snapshot) async {
    try {
      if (snapshot.exists) {
        await downloadSettingsFromFirebase();
        debugPrint('Settings updated from Firebase');
      }
    } catch (e) {
      debugPrint('Error handling settings changed: $e');
    }
  }

  // Sync specific transaction
  Future<void> syncSingleTransaction(Map<String, dynamic> transaction) async {
    try {
      final ref = _database.ref('$_userPath/transactions/${transaction['id']}');
      await ref.set(transaction);
      debugPrint('Single transaction synced to Firebase');
    } catch (e) {
      debugPrint('Error syncing single transaction: $e');
    }
  }

  // Check connectivity and sync status
  Future<bool> isConnected() async {
    try {
      final ref = _database.ref('.info/connected');
      final snapshot = await ref.get();
      return snapshot.value == true;
    } catch (e) {
      return false;
    }
  }

  // Get last sync time
  Future<int?> getLastSyncTime() async {
    try {
      final ref = _database.ref('$_userPath/settings/lastSyncTime');
      final snapshot = await ref.get();
      return snapshot.value as int?;
    } catch (e) {
      return null;
    }
  }
}
