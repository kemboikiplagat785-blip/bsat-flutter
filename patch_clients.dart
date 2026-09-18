import 'dart:io';

void main() {
  var file = File('lib/screens/clients/clients.dart');
  var content = file.readAsStringSync();

  if (!content.contains('_showAddClientDialog')) {
    var insertMethodPos = content.lastIndexOf('}');
    content =
        '''${content.substring(0, insertMethodPos)}  Future<void> _showAddClientDialog(BuildContext context) async {
    final firstNameController = TextEditingController();
    final lastNameController = TextEditingController();
    final phoneController = TextEditingController();

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
                
                await _sqliteService.insertStuff(client.toMap(), 'clients');
                if (context.mounted) Navigator.pop(context, true);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == true) {
      _getClients();
    }
  }
}
''';
  }

  content = content.replaceAll('return Scaffold(', '''return Scaffold(
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAddClientDialog(context),
        backgroundColor: kPrimaryColor,
        foregroundColor: Colors.white,
        child: const Icon(CupertinoIcons.add),
      ),''');

  file.writeAsStringSync(content);
  // print('Injected in clients.dart');
}
