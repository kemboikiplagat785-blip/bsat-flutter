import 'package:flutter_contacts/flutter_contacts.dart';

import 'shared_preferences_service.dart';

class ContactsService {
  SharedPreferencesService _sharedPreferencesService =
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
      final contacts = await FlutterContacts.getContacts();
      return contacts.any((contact) =>
          contact.phones.any((phone) => phone.number == phoneNumber));
    }
    return false;
  }
}
