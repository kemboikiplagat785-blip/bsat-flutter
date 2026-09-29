import 'package:bsat/components/dialogs/choose_sim.dart';
import 'package:bsat/components/dialogs/add_client_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:another_telephony/telephony.dart';

import '../services/sqlite_service.dart';

class DialPadScreen extends StatefulWidget {
  const DialPadScreen({super.key});

  @override
  _DialPadScreenState createState() => _DialPadScreenState();
}

class _DialPadScreenState extends State<DialPadScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode focusNode = FocusNode();
  final SQLiteService _sqLiteService = SQLiteService();

  List<SubscriptionInfo> sims = [];
  List<Map<String, dynamic>> myOffers = [];

  @override
  void initState() {
    super.initState();
    _fetchOffers();
    _getClipboardContent();

    Telephony.instance.getSubscriptionList().then((value) {
      if (mounted) {
        setState(() {
          sims = value;
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  Future<void> _fetchOffers() async {
    try {
      final rows = await _sqLiteService.rawQueryInput(
          'SELECT u.amount as amount, u.isAdvanced as isAdvanced, v.code as code, v.startTime as startTime, v.endTime as endTime FROM ussdCodes u JOIN ussdCodeVariants v ON u.id = v.ussdCodeId ORDER BY u.amount',
          []);
      if (mounted) {
        setState(() {
          myOffers = List<Map<String, dynamic>>.from(rows.map((offer) => {
                'amount': offer['amount'],
                'isAdvanced': offer['isAdvanced'],
                'code': offer['code'],
                'startTime': offer['startTime'],
                'endTime': offer['endTime'],
              }));
        });
      }
    } catch (e) {
      // fallback to legacy
      List offers = await _sqLiteService.queryAll('ussdCodes');
      if (mounted) {
        setState(() {
          myOffers = List<Map<String, dynamic>>.from(offers.map((offer) => {
                'amount': offer['amount'],
                'isAdvanced': offer['isAdvanced'],
                'code': offer['code'],
                'startTime': null,
                'endTime': null,
              }));
        });
      }
    }
  }

  String? _timeWindowLabel(Map<String, dynamic> offer) {
    final String start = (offer['startTime'] ?? '').toString();
    final String end = (offer['endTime'] ?? '').toString();
    if (start.isEmpty || end.isEmpty) return null;
    return '$start-$end';
  }

  Future<void> _getClipboardContent() async {
    ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    String cleanText =
        data?.text?.replaceAll(' ', '').replaceAll(RegExp(r"\D"), "") ?? '';
    if (cleanText.isNotEmpty) {
      _controller.text = cleanText;
    }
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
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
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
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: TextField(
                      controller: _controller,
                      focusNode: focusNode,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        hintText: "Enter number",
                        prefixIcon: const Icon(CupertinoIcons.phone,
                            color: kPrimaryColor),
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
                          horizontal: kPagePadding,
                          vertical: kPagePadding * 0.8,
                        ),
                      ),
                      // REMOVED onChanged: setState() to prevent entire screen rebuilds on keystrokes
                    ),
                  ),
                ),
                const SizedBox(height: kPagePadding * 1.5),
              ],
            ),
          ),

          // Isolate the reactive text using ValueListenableBuilder
          SliverToBoxAdapter(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: _controller,
              builder: (context, value, child) {
                if (value.text.isEmpty) return const SizedBox.shrink();

                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Offers for ${value.text}",
                          style: TextStyle(
                            color: Theme.of(context).hintColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => showAddClientDialog(context,
                            phoneNumber: value.text),
                        icon: const Icon(CupertinoIcons.person_add, size: 16),
                        label: const Text('Add Client'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          backgroundColor: kIndigoColor,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: kPagePadding)),

          // Use SliverGrid for high performance lazy-loading
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: kPagePadding,
                mainAxisSpacing: kPagePadding,
                childAspectRatio: 1.2,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final offer = myOffers[index];
                  return Material(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(kBorderRadius),
                    elevation: 1,
                    shadowColor: Colors.black.withValues(alpha: 0.05),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      onTap: () async {
                        // Directly access the controller's text when tapped
                        final currentNumber = _controller.text;
                        if (currentNumber.isEmpty) return;

                        SubscriptionInfo? chosen =
                            await chooseSim(context, sims);
                        if (chosen == null) return;
                        if (chosen.subscriptionId == null) return;

                        await transact(
                          offer['code'],
                          currentNumber,
                          chosen.subscriptionId!,
                          offer['amount'],
                          offer['isAdvanced'] == 1,
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(kBorderRadius),
                          border: Border.all(
                            color: kGrayColor.withValues(alpha: 0.1),
                            width: 1,
                          ),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${offer['amount']}',
                                  style: const TextStyle(
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
                                const SizedBox(height: 3),
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
                                if (_timeWindowLabel(offer) != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color:
                                            kIndigoColor.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(
                                            kBorderRadius / 2),
                                      ),
                                      child: Text(
                                        _timeWindowLabel(offer)!,
                                        style: const TextStyle(
                                          fontSize: 7,
                                          fontWeight: FontWeight.w700,
                                          color: kIndigoColor,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
                childCount: myOffers.length,
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: kPagePadding * 2)),
        ],
      ),
    );
  }
}
