import 'package:bsat/components/dialogs/choose_sim.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/add_client_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sim_data/sim_data.dart';

import '../services/sqlite_service.dart';

class DialPadScreen extends StatefulWidget {
  @override
  _DialPadScreenState createState() => _DialPadScreenState();
}

class _DialPadScreenState extends State<DialPadScreen> {
  String dialedNumber = '';
  final TextEditingController _controller = TextEditingController();
  final FocusNode focusNode = FocusNode();

  String clipboardContent = '';
  List<SimCard> sims = [];

  final SQLiteService _sqLiteService = SQLiteService();

  List myOffers = [];

  @override
  void initState() {
    super.initState();
    _fetchOffers();

    _getClipboardContent();

    SimDataPlugin.getSimData().then((value) {
      setState(() {
        sims = value.cards;
        // debugPrint("Got cards");
      });
    });
  }

  Future<void> _fetchOffers() async {
    List offers = await _sqLiteService.queryAll('ussdCodes');
    setState(() {
      myOffers = List<Map<String, dynamic>>.from(offers.map((offer) => {
            'amount': offer['amount'],
            'isAdvanced': offer['isAdvanced'],
            'code': offer['code'],
          }));
    });
  }

  // Future<void> _getContacts() async {
  //   if (await FlutterContacts.requestPermission()) {
  //     List<Contact> contacts = await FlutterContacts.getContacts();
  //     // debugPrint(contacts);
  //   }
  // }

  Future<void> _getClipboardContent() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    setState(() {
      clipboardContent =
          data?.text!.replaceAll(' ', '').replaceAll(new RegExp(r"\D"), "") ??
              '';
    });

    _controller.text = clipboardContent;
  }

  Future<void> transact(String selectedCode, String number, int simSubId,
      int amount, bool isAdvanced) async {
    final TransactionController transactionController = TransactionController();

    await transactionController.transactGivenUssdAndDialSim(
      transactionController.replaceNWithNumber(selectedCode, int.parse(number)),
      simSubId,
      amount,
      isAdvanced,
      int.parse(number),
    );
  }

  @override
  Widget build(BuildContext context) {
    var titleLarge = Theme.of(context).textTheme.titleLarge;
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, 'Dialpad'),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(kBorderRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: TextField(
                  controller: _controller,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: "Enter number",
                    prefixIcon:
                        Icon(CupertinoIcons.phone, color: kPrimaryColor),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste),
                      onPressed: _getClipboardContent,
                      tooltip: "Paste",
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      borderSide: BorderSide.none,
                    ),
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: kPagePadding, vertical: kPagePadding * 0.8),
                  ),
                  onChanged: (text) {
                    setState(() {
                      clipboardContent = text;
                    });
                  },
                ),
              ),
            ),
            const SizedBox(height: kPagePadding * 1.5),
            if (clipboardContent.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        "Offers for $clipboardContent",
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (clipboardContent.isNotEmpty)
                      ElevatedButton.icon(
                        onPressed: () => showAddClientDialog(context, phoneNumber: clipboardContent),
                        icon: const Icon(CupertinoIcons.person_add, size: 16),
                        label: const Text('Add Client'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          backgroundColor: kIndigoColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: kPagePadding),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: kPagePadding,
                  mainAxisSpacing: kPagePadding,
                  childAspectRatio: 1.2,
                ),
                itemCount: myOffers.length,
                itemBuilder: (context, index) {
                  final offer = myOffers[index];
                  return Material(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(kBorderRadius),
                    elevation: 1,
                    shadowColor: Colors.black.withOpacity(0.05),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      onTap: () async {
                        SimCard? chosen = await chooseSim(context, sims);

                        if (chosen == null) {
                          return;
                        }

                        await transact(
                          offer['code'],
                          _controller.text,
                          chosen.subscriptionId,
                          offer['amount'],
                          offer['isAdvanced'] == 1,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          border: Border.all(
                            color: kGrayColor.withOpacity(0.1),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '${offer['amount']}',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                color: kPrimaryColor,
                              ),
                            ),
                            Text(
                              'Ksh',
                              style: TextStyle(
                                fontSize: 10,
                                color: Theme.of(context).hintColor,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              offer['code'],
                              style: TextStyle(
                                fontSize: 9,
                                color: Theme.of(context).hintColor,
                                fontFamily: 'Monospace',
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: kPagePadding * 2),
          ],
        ),
      ),
    );
  }
}
