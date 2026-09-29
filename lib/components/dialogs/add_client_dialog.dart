import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/material.dart';

import '../../models/client.dart';

Future<void> showAddClientDialog(BuildContext context,
    {String? firstName,
    String? lastName,
    String? phoneNumber,
    String? alternativePhoneNumber}) async {
  final firstNameController =
      TextEditingController(text: firstName?.trim() ?? '');
  final lastNameController =
      TextEditingController(text: lastName?.trim() ?? '');
  final phoneController =
      TextEditingController(text: phoneNumber?.trim() ?? '');
  final alternativePhoneController =
      TextEditingController(text: alternativePhoneNumber?.trim() ?? '');

  await showDialog<bool>(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: const Text('Add Client'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: firstNameController,
                decoration: const InputDecoration(labelText: 'First Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: lastNameController,
                decoration: const InputDecoration(labelText: 'Last Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: phoneController,
                decoration:
                    const InputDecoration(labelText: 'Phone Number (Required)'),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: alternativePhoneController,
                decoration: const InputDecoration(
                    labelText: 'Alternative Phone Number'),
                keyboardType: TextInputType.phone,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (phoneController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Phone number is required')),
                );
                return;
              }

              final client = Client(
                firstName: firstNameController.text.trim(),
                lastName: lastNameController.text.trim(),
                phoneNumber: phoneController.text.trim(),
                alternativePhoneNumber:
                    alternativePhoneController.text.trim().isEmpty
                        ? null
                        : alternativePhoneController.text.trim(),
                createdAt: DateTime.now(),
              );

              await SQLiteService().insertStuff(client.toMap(), 'clients');
              if (context.mounted) Navigator.pop(context, true);
            },
            child: const Text('Save'),
          ),
        ],
      );
    },
  );
}
