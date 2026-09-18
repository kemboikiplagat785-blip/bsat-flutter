import 'package:flutter/material.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';

class CustomStatusesPage extends StatefulWidget {
  const CustomStatusesPage({super.key});

  @override
  State<CustomStatusesPage> createState() => _CustomStatusesPageState();
}

class _CustomStatusesPageState extends State<CustomStatusesPage> {
  final SQLiteService _sqliteService = SQLiteService();

  List<Map<String, dynamic>> _codes = [];
  bool _loading = true;

  late final List<String> _statusOptions;

  @override
  void initState() {
    super.initState();
    _statusOptions = TransactionStatuses.statuses.values
        .toSet()
        .map((e) => e.toString())
        .toList()
      ..sort();
    _loadCodes();
  }

  Future<void> _loadCodes() async {
    final data = await _sqliteService.getCustomCodes();
    if (!mounted) return;
    setState(() {
      _codes = data;
      _loading = false;
    });
  }

  Future<void> _showEditor({Map<String, dynamic>? item}) async {
    final TextEditingController patternController =
        TextEditingController(text: (item?['pattern'] ?? '').toString());
    String selectedStatus = (item?['transactionStatus'] ?? '').toString();
    bool isCaseSensitive = (item?['isCaseSensitive'] ?? 0) == 1;

    if (selectedStatus.isEmpty && _statusOptions.isNotEmpty) {
      selectedStatus = _statusOptions.first;
    }

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(item == null ? 'Add Custom Code' : 'Edit Custom Code'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: patternController,
                    decoration: const InputDecoration(
                      labelText: 'Words to watch out for match',
                      hintText: 'e.g. successfully recommended',
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue:
                        selectedStatus.isEmpty ? null : selectedStatus,
                    items: _statusOptions
                        .map(
                          (s) => DropdownMenuItem<String>(
                            value: s,
                            child: Text(s),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setDialogState(() {
                        selectedStatus = v ?? '';
                      });
                    },
                    decoration:
                        const InputDecoration(labelText: 'Transaction status'),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Case sensitive'),
                    value: isCaseSensitive,
                    onChanged: (v) {
                      setDialogState(() {
                        isCaseSensitive = v;
                      });
                    },
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final pattern = patternController.text.trim();
                  if (pattern.isEmpty || selectedStatus.isEmpty) return;

                  if (item == null) {
                    await _sqliteService.insertCustomCode(
                      pattern: pattern,
                      transactionStatus: selectedStatus,
                      isCaseSensitive: isCaseSensitive,
                    );
                  } else {
                    await _sqliteService.updateCustomCode(
                      item['id'] as int,
                      pattern: pattern,
                      transactionStatus: selectedStatus,
                      isCaseSensitive: isCaseSensitive,
                    );
                  }

                  if (!mounted) return;
                  Navigator.pop(context);
                  await _loadCodes();
                },
                child: const Text('Save'),
              ),
            ],
          );
        });
      },
    );
  }

  Future<void> _deleteCode(int id) async {
    await _sqliteService.deleteCustomCode(id);
    await _loadCodes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Custom Codes'),
        actions: [
          IconButton(
            onPressed: () => _showEditor(),
            icon: const Icon(Icons.add),
            tooltip: 'Add',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _codes.isEmpty
              ? const Center(child: Text('No custom codes yet'))
              : ListView.separated(
                  itemCount: _codes.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = _codes[index];
                    return ListTile(
                      title: Text((item['pattern'] ?? '').toString()),
                      subtitle: Text(
                        'Status: ${(item['transactionStatus'] ?? '').toString()}'
                        ' • ${((item['isCaseSensitive'] ?? 0) == 1) ? "Case-sensitive" : "Case-insensitive"}',
                      ),
                      trailing: Wrap(
                        spacing: 6,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.edit),
                            onPressed: () => _showEditor(item: item),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete),
                            onPressed: () => _deleteCode(item['id'] as int),
                          ),
                        ],
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
