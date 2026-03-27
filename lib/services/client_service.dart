import '../models/client.dart';
import 'sqlite_service.dart';

class ClientService {
  final SQLiteService _sqliteService = SQLiteService();

  Future<void> _ensureAlternativePhoneNumberColumn() async {
    await _sqliteService.addColumnIfNotExists(
        'clients', 'alternativePhoneNumber', 'TEXT');
  }

  // Insert a new client
  Future<int> insertClient(Client client) async {
    await _ensureAlternativePhoneNumberColumn();
    // update name only if number is unique
    final existingClient = await getClientByPhone(client.formattedPhone);

    print("existing client: $existingClient, new client: ${client.toMap()}");

    if (existingClient != null) {
      // Update name if it has changed
      if (existingClient.firstName != client.firstName ||
          existingClient.lastName != client.lastName) {
        final updatedClient = existingClient.copyWith(
          firstName: client.firstName,
          lastName: client.lastName,
        );
        return await updateClient(updatedClient);
      }
      // If name is the same, just return existing client's ID
      return existingClient.id!;
    }

    return await _sqliteService.insertStuff(client.toMap(), 'clients');
  }

  // Get all clients
  Future<List<Client>> getAllClients() async {
    await _ensureAlternativePhoneNumberColumn();
    final maps = await _sqliteService.queryAll('clients');
    return maps.map((map) => Client.fromMap(map)).toList();
  }

  // Get client by ID
  Future<Client?> getClientById(int id) async {
    final maps = await _sqliteService.queryCustom(
      'clients',
      'id = ?',
      [id],
    );
    if (maps.isNotEmpty) {
      return Client.fromMap(maps.first);
    }
    return null;
  }

  // Get client by phone number
  Future<Client?> getClientByPhone(String phoneNumber) async {
    await _ensureAlternativePhoneNumberColumn();
    final maps = await _sqliteService.queryCustom(
      'clients',
      'phoneNumber = ?',
      [phoneNumber],
    );
    if (maps.isNotEmpty) {
      return Client.fromMap(maps.first);
    }
    return null;
  }

  // Search clients by name or phone
  Future<List<Client>> searchClients(String query) async {
    final maps = await _sqliteService.rawQueryInput('''
      SELECT * FROM clients 
      WHERE firstName LIKE ? OR lastName LIKE ? OR phoneNumber LIKE ?
      ORDER BY noOfPurchases DESC, lastBought DESC
    ''', ['%$query%', '%$query%', '%$query%']);

    return maps.map((map) => Client.fromMap(map)).toList();
  }

  // Get top clients by number of purchases
  Future<List<Client>> getTopClients({int limit = 10}) async {
    final maps = await _sqliteService.rawQueryInput('''
      SELECT * FROM clients 
      WHERE noOfPurchases > 0
      ORDER BY noOfPurchases DESC, lastBought DESC
      LIMIT ?
    ''', [limit]);

    return maps.map((map) => Client.fromMap(map)).toList();
  }

  // Get active clients (purchased within last 30 days)
  Future<List<Client>> getActiveClients() async {
    final thirtyDaysAgo =
        DateTime.now().subtract(Duration(days: 30)).millisecondsSinceEpoch;
    final maps = await _sqliteService.rawQueryInput('''
      SELECT * FROM clients 
      WHERE lastBought IS NOT NULL AND lastBought >= ?
      ORDER BY lastBought DESC
    ''', [thirtyDaysAgo]);

    return maps.map((map) => Client.fromMap(map)).toList();
  }

  // Get clients who haven't purchased recently
  Future<List<Client>> getInactiveClients({int days = 30}) async {
    final daysAgo =
        DateTime.now().subtract(Duration(days: days)).millisecondsSinceEpoch;
    final maps = await _sqliteService.rawQueryInput('''
      SELECT * FROM clients 
      WHERE lastBought IS NULL OR lastBought < ?
      ORDER BY lastBought DESC NULLS LAST
    ''', [daysAgo]);

    return maps.map((map) => Client.fromMap(map)).toList();
  }

  // Update client
  Future<int> updateClient(Client client) async {
    await _ensureAlternativePhoneNumberColumn();
    return await _sqliteService.updateStuff(
      client.toMap(),
      'id = ?',
      [client.id],
      'clients',
    );
  }

  // Record a purchase for a client
  Future<void> recordPurchase(
      String phoneNumber, String firstName, String lastName) async {
    final client = await getClientByPhone(phoneNumber);
    if (client != null) {
      // Update existing client
      final updatedClient = client.copyWith(
        lastBought: DateTime.now(),
        noOfPurchases: client.noOfPurchases + 1,
      );
      await updateClient(updatedClient);
    } else {
      // Create new client from SMS data
      await createClientFromPurchase(firstName, lastName, phoneNumber);
    }
  }

  // Create client from purchase (extract name from SMS)
  Future<void> createClientFromPurchase(
      String firstName, String lastName, String phoneNumber) async {
    // This could be enhanced to extract name from SMS message
    final client = Client(
      firstName: firstName,
      lastName: lastName,
      phoneNumber: phoneNumber,
      createdAt: DateTime.now(),
      lastBought: DateTime.now(),
      noOfPurchases: 1,
    );
    await insertClient(client);
  }

  // Delete client
  Future<int> deleteClient(int id) async {
    return await _sqliteService.deleteWhere('clients', 'id = ?', [id]);
  }

  // Get client count
  Future<int> getClientCount() async {
    return await _sqliteService.getCount('clients');
  }

  // Get purchase statistics
  Future<Map<String, dynamic>> getClientStats() async {
    final result = await _sqliteService.rawQueryInput('''
      SELECT 
        COUNT(*) as totalClients,
        COUNT(CASE WHEN lastBought IS NOT NULL THEN 1 END) as clientsWithPurchases,
        COALESCE(SUM(noOfPurchases), 0) as totalPurchases,
        COALESCE(AVG(noOfPurchases), 0) as avgPurchasesPerClient
      FROM clients
    ''', []);

    return result.isNotEmpty ? result.first : {};
  }
}
