import 'dart:convert';
import 'dart:io';

import 'package:bsat/models/client.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';

import '../../components/dialogs/show_error_dialog.dart';
import '../../components/dialogs/success_dialog.dart';
import '../../components/header.dart';
// import '../../components/button.dart';

class ImportFromFilePage extends StatefulWidget {
  const ImportFromFilePage({super.key});

  @override
  State<ImportFromFilePage> createState() => _ImportFromFilePageState();
}

enum FileTypeStatus { unknown, csv, vcf }

class _ImportFromFilePageState extends State<ImportFromFilePage> {
  FileTypeStatus selectedType = FileTypeStatus.unknown;
  String? filePath;

  // CSV Mapping State
  List<List<dynamic>> csvTable = [];
  List<String> headers = [];
  List<String> selectedNameHeaders = [];
  String? selectedPhoneHeader;

  // Track progress
  int processedCount = 0;
  int totalToProcess = 0;

  void _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'vcf'],
    );

    if (result != null && result.files.single.path != null) {
      String ext = result.files.single.extension?.toLowerCase() ?? '';
      setState(() {
        filePath = result.files.single.path!;
        selectedType = ext == 'csv'
            ? FileTypeStatus.csv
            : (ext == 'vcf' ? FileTypeStatus.vcf : FileTypeStatus.unknown);
      });

      if (selectedType == FileTypeStatus.csv) {
        await _parseCSV();
      } else if (selectedType == FileTypeStatus.vcf) {
        // vcf handles immediately mapped logic
      }
    }
  }

  Future<void> _parseCSV() async {
    try {
      final input = File(filePath!).openRead();
      final fields = await input
          .transform(utf8.decoder)
          .transform(const CsvToListConverter())
          .toList();

      if (fields.isNotEmpty) {
        setState(() {
          csvTable = fields;
          headers = fields[0].map((e) => e.toString()).toList();
          selectedNameHeaders.clear();
          selectedPhoneHeader = null;
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error parsing CSV: $e')),
      );
    }
  }

  Future<void> _importContacts() async {
    if (filePath == null) return;

    if (selectedType == FileTypeStatus.csv) {
      if (selectedNameHeaders.isEmpty || selectedPhoneHeader == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Please select headers for Name(s) and Phone Number.'),
          ),
        );
        return;
      }
      await _processCSV();
    } else if (selectedType == FileTypeStatus.vcf) {
      await _processVCF();
    }
  }

  Future<void> _processCSV() async {
    if (!mounted) return;

    try {
      totalToProcess = csvTable.length - 1; // excluding header
      int nameIndices = 0;
      List<int> nameIndexes = [];
      int phoneIndex = -1;

      // Find indexes
      for (int i = 0; i < headers.length; i++) {
        if (selectedNameHeaders.contains(headers[i])) {
          nameIndexes.add(i);
        }
        if (headers[i] == selectedPhoneHeader) {
          phoneIndex = i;
        }
      }

      int addedCount = 0;
      bool isCancelled = false;
      ValueNotifier<int> itemsLeftNotifier = ValueNotifier(totalToProcess);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (progressContext) {
          return ValueListenableBuilder<int>(
            valueListenable: itemsLeftNotifier,
            builder: (valContext, value, child) {
              return SimpleDialog(
                children: [
                  const SizedBox(height: kPagePadding),
                  const Center(child: CupertinoActivityIndicator()),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: Text(
                      "Processing $value items ...",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        isCancelled = true;
                        Navigator.pop(progressContext);
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      for (int i = 1; i < csvTable.length; i++) {
        if (isCancelled) break;
        var row = csvTable[i];
        if (row.length <= phoneIndex) continue;

        String phone =
            row[phoneIndex].toString().replaceAll(RegExp(r'\s+'), '');
        if (phone.isEmpty) continue;

        List<String> nameParts = [];
        for (int idx in nameIndexes) {
          if (row.length > idx) {
            String val = row[idx].toString().trim();
            if (val.isNotEmpty) nameParts.add(val);
          }
        }
        String fullName = nameParts.join(' ');
        if (fullName.isEmpty) continue; // Optional: skip if no name

        List<String> fnParts = fullName.split(RegExp(r'\s+'));
        String firstName = fnParts.first;
        String lastName =
            fnParts.length > 1 ? fnParts.sublist(1).join(' ') : '';

        final client = Client(
          firstName: firstName,
          lastName: lastName,
          phoneNumber: phone,
          createdAt: DateTime.now(),
        );

        List<Map<String, dynamic>> similarClients = await SQLiteService()
            .queryAll('clients',
                where: 'phoneNumber = ?', whereArgs: [client.phoneNumber]);

        if (similarClients.isEmpty) {
          await SQLiteService().insertStuff(client.toMap(), 'clients');
          addedCount++;
        }

        itemsLeftNotifier.value--;
      }

      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog

      if (isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import cancelled')),
        );
      } else {
        showSuccessDialog(context,
            text: "Successfully imported $addedCount clients!");
      }

      Navigator.of(context).pop(); // Go back
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog
      showErrorDialog(context, "", "Error importing from CSV: $e");
    }
  }

  Future<void> _processVCF() async {
    if (!mounted) return;

    try {
      final fileContent = await File(filePath!).readAsString();

      // Basic manual parse of VCF logic as regex since parser plugin might not be available
      // Matches BEGIN:VCARD to END:VCARD
      final cards = fileContent.split('BEGIN:VCARD');
      int addedCount = 0;
      int totalCards = cards.length - 1; // excluding empty first element
      bool isCancelled = false;
      ValueNotifier<int> itemsLeftNotifier = ValueNotifier(totalCards);

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (progressContext) {
          return ValueListenableBuilder<int>(
            valueListenable: itemsLeftNotifier,
            builder: (valContext, value, child) {
              return SimpleDialog(
                children: [
                  const SizedBox(height: kPagePadding),
                  const Center(child: CupertinoActivityIndicator()),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: Text(
                      "Processing $value items ...",
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: kPagePadding),
                  Center(
                    child: TextButton(
                      onPressed: () {
                        isCancelled = true;
                        Navigator.pop(progressContext);
                      },
                      child: const Text(
                        "Cancel",
                        style: TextStyle(color: Colors.red),
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      );

      for (String card in cards) {
        if (isCancelled) break;
        if (card.trim().isEmpty) continue;

        String name = '';
        String phone = '';

        // Extract FN (Formatted Name)
        RegExp nameRegex = RegExp(r'^FN:(.*?)$', multiLine: true);
        Match? nameMatch = nameRegex.firstMatch(card);
        if (nameMatch != null) {
          name = nameMatch.group(1)?.trim() ?? '';
        }

        // Extract TEL
        RegExp phoneRegex = RegExp(r'^TEL.*?:(.*?)$', multiLine: true);
        Match? phoneMatch = phoneRegex.firstMatch(card);
        if (phoneMatch != null) {
          phone = phoneMatch.group(1)?.replaceAll(RegExp(r'[^\d+]'), '') ?? '';
        }

        if (phone.isNotEmpty && name.isNotEmpty) {
          List<String> fnParts = name.split(RegExp(r'\s+'));
          String firstName = fnParts.first;
          String lastName =
              fnParts.length > 1 ? fnParts.sublist(1).join(' ') : '';

          final client = Client(
            firstName: firstName,
            lastName: lastName,
            phoneNumber: phone,
            createdAt: DateTime.now(),
          );

          List<Map<String, dynamic>> similarClients = await SQLiteService()
              .queryAll('clients',
                  where: 'phoneNumber = ?', whereArgs: [client.phoneNumber]);

          if (similarClients.isEmpty) {
            await SQLiteService().insertStuff(client.toMap(), 'clients');
            addedCount++;
          }
        }

        itemsLeftNotifier.value--;
      }

      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog

      if (isCancelled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Import cancelled')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Successfully imported $addedCount clients!')),
        );
      }

      Navigator.of(context).pop(); // Go back
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close progress dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error importing VCF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            header(context, "Import Contacts"),
            const SizedBox(height: kPagePadding),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                children: [
                  const Text(
                    "Step 1: Choose File",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Upload a .csv or .vcf file containing your clients.",
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 16),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _pickFile,
                      icon: const Icon(CupertinoIcons.doc_text),
                      label: Text(
                          filePath == null ? "Select File" : "Change File"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.all(16),
                        backgroundColor:
                            filePath == null ? kPrimaryColor : Colors.grey[200],
                        foregroundColor:
                            filePath == null ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  if (filePath != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      "Selected: ${filePath!.split('/').last}",
                      style: const TextStyle(
                          fontWeight: FontWeight.w600, color: kPrimaryColor),
                    ),
                  ],
                  const SizedBox(height: 32),
                  if (selectedType == FileTypeStatus.csv &&
                      headers.isNotEmpty) ...[
                    const Text(
                      "Step 2: Map Columns",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Select which column(s) represent the Name. You can select multiple for multi-part names. Then select the column for Phone Number.",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: kPagePadding),

                    // Mapping UI
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.grey.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text("Name Column(s):",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: headers.map((header) {
                              bool isSelected =
                                  selectedNameHeaders.contains(header);
                              return ChoiceChip(
                                label: Text(header),
                                selected: isSelected,
                                selectedColor:
                                    kPrimaryColor.withValues(alpha: 0.2),
                                onSelected: (selected) {
                                  setState(() {
                                    if (selected) {
                                      selectedNameHeaders.add(header);
                                    } else {
                                      selectedNameHeaders.remove(header);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const Divider(height: 32),
                          const Text("Phone Number Column:",
                              style: TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: headers.map((header) {
                              bool isSelected = selectedPhoneHeader == header;
                              return ChoiceChip(
                                label: Text(header),
                                selected: isSelected,
                                selectedColor:
                                    kIndigoColor.withValues(alpha: 0.2),
                                onSelected: (selected) {
                                  setState(() {
                                    selectedPhoneHeader =
                                        selected ? header : null;
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (selectedType == FileTypeStatus.vcf) ...[
                    const Text(
                      "Step 2: Confirm",
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "VCF files automatically map Name and Phone formats. Click import below to begin.",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                  const SizedBox(height: 48),
                ],
              ),
            ),
            if (filePath != null)
              Padding(
                padding: const EdgeInsets.all(kPagePadding),
                child: SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _importContacts,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text("Import to Clients",
                        style: TextStyle(fontSize: 18)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
