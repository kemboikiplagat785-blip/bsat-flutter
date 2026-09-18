import 'package:bsat/components/dialogs/add_client_dialog.dart';

import "import_from_file.dart";
import 'package:another_telephony/telephony.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/services/file_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

import '../../components/button_descriptive.dart';
import '../../components/header.dart';
import '../../models/client.dart';
import '../../services/sms_sevice.dart';
import './share_contacts_page.dart';

class SyncDataPage extends StatefulWidget {
  const SyncDataPage({super.key});

  @override
  State<SyncDataPage> createState() => _SyncDataPageState();
}

class _SyncDataPageState extends State<SyncDataPage> {
  int messageIndex = 0;
  void getDataFromMpesaMessages() async {
    // show alert dialog for number of days

    List<SmsMessage> messages = [];

    await showDialog(
      context: context,
      builder: (dialogContext) {
        int days = 30;
        return AlertDialog(
          title: Text("Sync data from mpesa messages"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                  "How many days back do you want to sync data from mpesa messages?"),
              SizedBox(height: kPagePadding),
              TextField(
                keyboardType: TextInputType.number,
                onChanged: (value) {
                  days = int.tryParse(value) ?? 30;
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText: "Number of days",
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                if (!mounted) return;
                showLoadingDialog(context,
                    text: "Syncing data from mpesa messages...");

                messages = await getAllSince(DateTime.now()
                    .subtract(Duration(days: days))
                    .millisecondsSinceEpoch);

                if (!mounted) return;
                Navigator.of(context).pop();

                // Process the retrieved messages and save to database
                messageIndex = messages.length;

                ValueNotifier<int> messagesLeft = ValueNotifier(messageIndex);

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (progressContext) {
                    return ValueListenableBuilder<int>(
                      valueListenable: messagesLeft,
                      builder: (valContext, value, child) {
                        return SimpleDialog(
                          children: [
                            const SizedBox(height: kPagePadding),
                            const Center(child: CupertinoActivityIndicator()),
                            const SizedBox(height: kPagePadding),
                            Center(
                              child: Text(
                                "Processing $value messages ...",
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        );
                      },
                    );
                  },
                );

                for (var message in messages) {
                  try {
                    Client client = Client.fromMpesaMessage(message.body ?? "");

                    List<Map<String, dynamic>> similarClients =
                        await SQLiteService().queryAll('clients',
                            where: 'phoneNumber = ?',
                            whereArgs: [client.phoneNumber]);
                    if (similarClients.isEmpty) {
                      await SQLiteService()
                          .insertStuff(client.toMap(), 'clients');
                    }
                  } catch (e) {
                    // Handle parsing errors
                    print("Error parsing message: ${message.body}");
                  }

                  messagesLeft.value--;
                }

                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: Text("Sync"),
            ),
          ],
        );
      },
    );

    //call getAllSince(timestamp) then Client.fromMpesaMessage for each message and save to database
    // Implementation for syncing data from mpesa messages
  }

  // void getDataFrom334Messages() async {
  //   List<SmsMessage> messages = [];
  //
  //   if (!mounted) return;
  //   showLoadingDialog(context,
  //       text: "Syncing data from 334 messages...");
  //
  //   messages = await getAll334Messages();
  //
  //   if (!mounted) return;
  //   Navigator.of(context).pop();
  //
  //   // Process the retrieved messages and save to database
  //   messageIndex = messages.length;
  //
  //   ValueNotifier<int> messagesLeft = ValueNotifier(messageIndex);
  //
  //   showDialog(
  //     context: context,
  //     barrierDismissible: false,
  //     builder: (progressContext) {
  //       return ValueListenableBuilder<int>(
  //         valueListenable: messagesLeft,
  //         builder: (valContext, value, child) {
  //           return SimpleDialog(
  //             children: [
  //               const SizedBox(height: kPagePadding),
  //               const Center(child: CupertinoActivityIndicator()),
  //               const SizedBox(height: kPagePadding),
  //               Center(
  //                 child: Text(
  //                   "Processing $value messages ...",
  //                   style: const TextStyle(fontWeight: FontWeight.bold),
  //                 ),
  //               ),
  //             ],
  //           );
  //         },
  //       );
  //     },
  //   );
  //
  //   for (var message in messages) {
  //     try {
  //       Client client = Client.from334Message(message.body ?? "");
  //
  //       List<Map<String, dynamic>> similarClients =
  //       await SQLiteService().queryAll('clients',
  //           where: 'phoneNumber = ?',
  //           whereArgs: [client.phoneNumber]);
  //       if (similarClients.isEmpty) {
  //         await SQLiteService()
  //             .insertStuff(client.toMap(), 'clients');
  //       }
  //     } catch (e) {
  //       // Handle parsing errors
  //       print("Error parsing message: ${message.body}");
  //     }
  //
  //     messagesLeft.value--;
  //   }
  //
  //   if (!mounted) return;
  //   Navigator.of(context).pop();
  // }

  void getDataFromContacts() async {
    showLoadingDialog(context, text: 'Getting contacts ...');
    List<Contact> contacts = await ContactsService().getAllContacts();

    if (!mounted) return;
    Navigator.pop(context);

    // Process the retrieved contacts and save to database
    int contactsLeft = contacts.length;
    ValueNotifier<int> contactsLeftNotifier = ValueNotifier(contactsLeft);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (progressContext) {
        return ValueListenableBuilder<int>(
          valueListenable: contactsLeftNotifier,
          builder: (valContext, value, child) {
            return SimpleDialog(
              children: [
                const SizedBox(height: kPagePadding),
                const Center(child: CupertinoActivityIndicator()),
                const SizedBox(height: kPagePadding),
                Center(
                  child: Text(
                    "Processing $value contacts ...",
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );

    for (final contact in contacts) {
      try {
        final phone = contact.phones.isNotEmpty
            ? (contact.phones.first.normalizedNumber ??
                contact.phones.first.number)
            : null;

        if (phone == null || phone.trim().isEmpty) {
          contactsLeftNotifier.value--;
          continue;
        }

        String firstName = '';
        String lastName = '';

        final nameParts = <String>[];

        final contactName = contact.name;

        if (contactName != null) {
          if (contactName.first?.trim().isNotEmpty == true) {
            nameParts.add(contactName.first!.trim());
          }

          if (contactName.middle?.trim().isNotEmpty == true) {
            nameParts.add(contactName.middle!.trim());
          }

          if (contactName.last?.trim().isNotEmpty == true) {
            nameParts.add(contactName.last!.trim());
          }
        }

        if (nameParts.isNotEmpty) {
          firstName = nameParts.first;
          lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';
        }

        if (firstName.isEmpty && lastName.isEmpty) {
          contactsLeftNotifier.value--;
          continue;
        }

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
        }
      } catch (e) {
        print("Error processing contact: ${contact.displayName}");
      }

      contactsLeftNotifier.value--;
    }

    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: SafeArea(
          child: Column(
            children: [
              header(context, "Sync data"),
              const SizedBox(height: kPagePadding),
              Padding(
                padding: const EdgeInsets.all(kPagePadding),
                child: Text(
                  "Antimask - Get your client information to help you manage your business. Sync data from mpesa messages and contacts to get all possible clients and transactions into the app.",
                  style: TextStyle(
                    color: Colors.grey[600],
                  ),
                ),
              ),
              buttonDescriptive(
                context,
                title: "Add clients manually",
                subtitle: "Add clients directly to the app.",
                onTap: () async {
                  await showAddClientDialog(context);
                },
                icon: Icon(
                  CupertinoIcons.plus_app,
                  color: kPrimaryColor,
                ),
              ),
              buttonDescriptive(
                context,
                title: "Import clients from mpesa messages",
                subtitle:
                    "Get all clients from mpesa messages and sync them to the app.",
                onTap: () {
                  getDataFromMpesaMessages();
                },
                icon: Icon(
                  CupertinoIcons.mail,
                  color: kPrimaryColor,
                ),
              ),
              buttonDescriptive(
                context,
                title: "Import clients from my contacts",
                subtitle: "From saved contacts in your phonebook",
                onTap: () {
                  getDataFromContacts();
                },
                icon: Icon(
                  CupertinoIcons.phone_down_circle,
                  color: kWarningColor,
                ),
              ),
              buttonDescriptive(
                context,
                title: "Share contacts with another BSAT phone",
                subtitle:
                    "Pair with another BSAT device, then send your saved contacts to it.",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ShareContactsPage(),
                    ),
                  );
                },
                icon: Icon(
                  CupertinoIcons.person_2_square_stack,
                  color: kPrimaryColor,
                ),
              ),

              // import from vcf file
              buttonDescriptive(
                context,
                title: "Import clients from vcf/csv file",
                subtitle: "Import clients from a vcf/csv file.",
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ImportFromFilePage()),
                  );
                },
                icon: Icon(
                  CupertinoIcons.doc_checkmark,
                  color: kErrorColor,
                ),
              ),
              const SizedBox(height: kPagePadding),
              buttonDescriptive(
                context,
                title: "Export clients to CSV",
                subtitle: "Save all clients to a CSV file.",
                onTap: () async {
                  String path = await FileService.downloadClientsToCsv();
                  if (path.isNotEmpty && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved to $path')),
                    );
                  }
                },
                icon: Icon(
                  CupertinoIcons.doc_text,
                  color: kPrimaryColor,
                ),
              ),
              buttonDescriptive(
                context,
                title: "Export clients to VCF",
                subtitle: "Save all clients to a VCF file.",
                onTap: () async {
                  print("Exporting clients to VCF...");
                  String path = await FileService.downloadClientsToVcf();
                  print(path);
                  if (path.isNotEmpty && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved to $path')),
                    );
                  }
                },
                icon: Icon(
                  CupertinoIcons.person_crop_circle_badge_exclam,
                  color: kWarningColor,
                ),
              ),
              buttonDescriptive(
                context,
                title: "Export clients to JSON",
                subtitle: "Save all clients to a JSON file.",
                onTap: () async {
                  String path = await FileService.downloadClientsToJson();
                  if (path.isNotEmpty && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Saved to $path')),
                    );
                  }
                },
                icon: Icon(
                  CupertinoIcons.doc_plaintext,
                  color: kIndigoColor,
                ),
              ),
              const SizedBox(height: kPagePadding * 2),
            ],
          ),
        ),
      ),
    );
  }
}
