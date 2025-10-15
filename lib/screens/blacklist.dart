import 'package:bsat/components/dialogs/blacklist_entry.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BlacklistPage extends StatefulWidget {
  @override
  _BlacklistPageState createState() => _BlacklistPageState();
}

class _BlacklistPageState extends State<BlacklistPage> {
  // Sample list of maps containing "number" and "id"
  final _sqliteService = SQLiteService();

  List<Map<String, dynamic>> items = [];

  void getData() async {
    items = await _sqliteService.queryAll('blacklist');

    setState(() {});
  }

  void searchList(String query) async {
    if (query.isNotEmpty && query[0] == '0') {
      query = query.substring(1);
    }

    items = await _sqliteService
        .queryCustom('blacklist', 'CAST(number AS TEXT) LIKE ?', ['%$query%']);

    // print(items.length);
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    getData();
  }

  Future<void> deleteNumber(int id) async {
    await _sqliteService.deleteStuff(id, 'blacklist');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, 'Blacklst'),
            Padding(
              padding: kPagePaddingInsets,
              child: TextField(
              // keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: 'Search numbers...',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(kBorderRadius),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
                onChanged: (value) async {
                  // smsList = await searchSms(value);
                  // setState(() {
                  //   print(smsList.length);
                  // });
                  searchList(value);
                },
              ),
            ),
            Container(
              padding: kPagePaddingInsets,
              height: MediaQuery.of(context).size.height * 0.8,
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    // title: Text(
                    //   '${index + 1}',
                    //   style: TextStyle(
                    //       color: Theme.of(context).hintColor.withOpacity(.2)),
                    // ),
                    subtitle: Text('0${items[index]['number']}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.copy_all,
                              color: Theme.of(context).indicatorColor),
                          onPressed: () async {
                            await Clipboard.setData(
                              ClipboardData(
                                text: "0${items[index]['number']}",
                              ),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '0${items[index]['number']} copied to clipboard'),
                              ),
                            );
                          },
                        ),
                        const SizedBox(width: kPagePadding / 2),
                        IconButton(
                          icon: Icon(Icons.delete, color: kErrorColor),
                          onPressed: () async {
                            deleteNumber(items[index]['id']).then(
                              (value) => getData(),
                            );
                          },
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
          showBlacklistEntryDialog(context).then((value) => getData());
        },
        child: Icon(Icons.add),
      ),
    );
  }
}
