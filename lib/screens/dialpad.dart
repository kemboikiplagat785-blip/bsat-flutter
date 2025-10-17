import 'package:bsat/components/dialogs/choose_sim.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
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
      myOffers = offers
          .map((offer) => {
                'amount': offer['amount'],
                'isAdvanced': offer['isAdvanced'],
                'code': offer['code'],
              })
          .toList();
    });
  }

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
    return Scaffold(
      body: SingleChildScrollView(
        child: Column(
          children: [
            header(context, 'Dialpad'),
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: TextField(
                // focusNode: focusNode,
                controller: _controller,
                // readOnly: true, // Disable typing with keyboard
                style: const TextStyle(fontSize: 20),
                decoration: const InputDecoration(
                    // border: InputBorder.none,
                    ),
                showCursor: true,
                onTap: () {
                  // focusNode.unfocus();
                },
                onChanged: (text) {
                  setState(() {
                    clipboardContent = text;
                  });
                },
              ),
            ),
            // Dialpad keys
            Column(
              children: [
                Container(
                  padding: kPagePaddingInsets / 2,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(kBorderRadius / 2),
                  ),
                  child: Text(
                    clipboardContent.isNotEmpty
                        ? "Select offer to recommend for ${_controller.text}"
                        : "",
                  ),
                ),
                Wrap(
                  children: myOffers.map((offer) {
                    return GestureDetector(
                      onTap: () async {
                        // debugPrint("Offer: $offer");
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
                        padding: kPagePaddingInsets,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              decoration: BoxDecoration(),
                              child: Text('Ksh ${offer['amount']} '),
                            ),
                            Text(
                              offer['code'],
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).indicatorColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: kPagePadding * 2),
          ],
        ),
      ),
    );
  }
}
