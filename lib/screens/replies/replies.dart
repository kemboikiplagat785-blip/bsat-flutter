// stateful widget called RepliesPage

import 'dart:convert';

import 'package:bsat/components/dialogs/confirm_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/screens/replies/edit_reply.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../components/header.dart';
import '../../services/sqlite_service.dart';
import '../../utils/constants.dart';

class RepliesPage extends StatefulWidget {
  const RepliesPage({super.key});

  @override
  _RepliesPageState createState() => _RepliesPageState();
}

class _RepliesPageState extends State<RepliesPage> {
  List<Map<String, dynamic>> items = [];

  final _sqliteService = SQLiteService();

  void getData() async {
    items = await _sqliteService.queryAll('replies');

    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    getData();

    requestSmsPermission();
  }

  Future<void> requestSmsPermission() async {
    PermissionStatus status = await Permission.sms.request();

    if (status.isGranted) {
      // Proceed with sending SMS
      // print("SMS permission granted");
    } else {
      // print("SMS permission denied");
    }
  }

  Future<void> deleteReply(int id) async {
    await _sqliteService.deleteStuff(id, 'replies');

    getData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            header(context, 'My Replies'),
            Container(
              padding: kPagePaddingInsets,
              decoration: BoxDecoration(
                // color: Theme.of(context).cardColor.withOpacity(.5),
                borderRadius: BorderRadius.circular(kBorderRadius),
              ),
              height: MediaQuery.of(context).size.height * 0.8,
              child: items.isEmpty
                  ? Center(
                      child: Text(
                        'No replies found. Tap the + button to add a new reply.',
                        style: TextStyle(color: Theme.of(context).hintColor),
                      ),
                    )
                  : ListView.separated(
                      itemCount: items.length,
                      separatorBuilder: (context, index) {
                        return SizedBox(
                          height: kPagePadding / 2,
                        );
                      },
                      itemBuilder: (context, index) {
                        List amounts =
                            jsonDecode(items[index]['amounts'] ?? '[]');
                        return ListTile(
                          // minVerticalPadding: kPagePadding / 2,
                          tileColor: Theme.of(context).cardColor,
                          leading: Switch(
                            value: items[index]['conditionAmount'] == 1,
                            onChanged: (bool newValue) async {
                              // debugPrint('Switched to $newValue');
                              await _sqliteService.updateStuff(
                                {'conditionAmount': newValue ? 1 : 0},
                                'id = ?',
                                [items[index]['id']],
                                'replies',
                              );
                              getData();
                            },
                          ),
                          title: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${TransactionStatuses.statuses[items[index]['condition']] == TransactionStatuses.done ? "transaction-pending-confirmation" : TransactionStatuses.statuses[items[index]['condition']]}',
                                style: TextStyle(fontSize: 14),
                              ),
                              Container(
                                padding: kPagePaddingInsets / 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  amounts.isNotEmpty
                                      ? 'Amounts: ${amounts.join(", ")}'
                                      : 'Any amount',
                                  style: TextStyle(fontSize: 12),
                                ),
                              ),
                              const SizedBox(height: kPagePadding / 2),
                            ],
                          ),
                          subtitle: Text('${items[index]['reply']}'),
                          trailing: Column(
                            children: [
                              InkWell(
                                child: Icon(Icons.edit, color: kPrimaryColor, size: 18,),
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (context) => EditReplyPage(
                                        replyId: items[index]['id'],
                                      ),
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: kPagePadding),
                              InkWell(
                                onTap: () async {
                                  bool del = await showConfirmDialog(context, title: 'Warning', message: 'Are you sure you want to delete this reply?',) ?? false;
                                  if (del) {
                                    showLoadingDialog(context);
                                    await _sqliteService.deleteStuff(items[index]['id'], 'replies');
                                    getData();
                                    if (mounted) Navigator.pop(context);
                                  }
                                },
                                child: Icon(
                                  Icons.delete,
                                  color: kErrorColor,
                                  size: 18,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: kPagePadding * 2),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (context) => EditReplyPage(replyId: -1),
            ),
          );
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
