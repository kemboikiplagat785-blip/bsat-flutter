 import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/material.dart';

import '../../models/client.dart';

Future<void> showAddClientDialog(BuildContext context, {String? phoneNumber}) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final phoneController = TextEditingController(text: phoneNumber?.trim() ?? '');

    final result = await showDialog<bool>(
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
                  decoration: const InputDecoration(labelText: 'Phone Number (Required)'),
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
