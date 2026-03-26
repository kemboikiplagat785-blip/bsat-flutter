import 'dart:io';

void main() {
  var file = File('lib/screens/clients/single_client.dart');
  var content = file.readAsStringSync();
  
  if (content.contains('_showEditClientDialog')) return;

  var insertMethodPos = content.lastIndexOf('}');
  content = content.substring(0, insertMethodPos) + '''
  Future<void> _showEditClientDialog(BuildContext context) async {
    final firstNameController = TextEditingController(text: _client!.firstName);
    final lastNameController = TextEditingController(text: _client!.lastName);
    final phoneController = TextEditingController(text: _client!.phoneNumber);

    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Client'),
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
                
                final updatedClient = Client(
                  id: _client!.id,
                  firstName: firstNameController.text.trim(),
                  lastName: lastNameController.text.trim(),
                  phoneNumber: phoneController.text.trim(),
                  createdAt: _client!.createdAt,
                  lastBought: _client!.lastBought,
                  noOfPurchases: _client!.noOfPurchases,
                  daysSinceLastPurchase: _client!.daysSinceLastPurchase,
                  totalSpent: _client!.totalSpent,
                );
                
                await _sqliteService.updateStuff(
                  updatedClient.toMap(),
                  'id = ?',
                  [updatedClient.id],
                  'clients',
                );
                
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      if (mounted) {
        setState(() {
          _isLoading = true;
        });
        getStuff();
      }
    }
  }
}
''';

  var editButtonCode = '''
                                      toolButton(
                                        () => _showEditClientDialog(context),
                                        Icon(
                                          CupertinoIcons.pencil,
                                          color: Colors.orange,
                                          size: 14,
                                        ),
                                        "Edit",
                                        context,
                                        textSize: 13,
                                      ),
                                      // Edit and delete could act here if controllers/dialogs existed''';

  content = content.replaceAll('// Edit and delete could act here if controllers/dialogs existed', editButtonCode);

  file.writeAsStringSync(content);
  // print('Injected Edit to single_client.dart');
}
