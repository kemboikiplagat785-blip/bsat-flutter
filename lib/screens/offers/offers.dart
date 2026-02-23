import 'package:bsat/components/card_with_number.dart';
import 'package:bsat/components/dialogs/choose_sim.dart';
import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/offers/edit_offer.dart';
import 'package:bsat/services/file_service.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sim_data/sim_data.dart';

import '../../components/dialogs/make_offer_tutorial_dialog.dart';
import '../../utils/constants.dart';

class OffersPage extends StatefulWidget {
  const OffersPage({super.key});

  @override
  State<OffersPage> createState() => _OffersPageState();
}

class _OffersPageState extends State<OffersPage> {
  final _sqliteService = SQLiteService();

  List<Map<String, dynamic>> ussdCodes = [];
  List<SimCard> sims = [];

  int _fromSim = -1;
  int _dialSim = -1;

  bool _selectionMode = false;

  final Set<int> _selectedTransactionIds = {};

  @override
  void initState() {
    super.initState();

    getAllUSSDCodes();
    getAndProcessCards();

    addAdvancedColumn();

    _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'enabled',
      'INTEGER',
      defaultValue: 1,
    );

    // addOffers();
  }

  void refreshPage() async {
    showLoadingDialog(context);
    await getAllUSSDCodes();
    await getAndProcessCards();
    Navigator.pop(context);
    setState(() {});
  }

  void enableOffer(bool isEnabled, int id) {
    // add enabled column if it doesn't exist, default to true
    _sqliteService.updateStuff(
      {'enabled': isEnabled ? 1 : 0},
      'id = ?',
      [id],
      'ussdCodes',
    );

    refreshPage();
  }

  void addOffers() {
    for (var i in kNoAutoretryCodes) {
      _sqliteService.insertStuff(
        {
          'amount': i["amount"],
          'code': i["code"],
          'fromSim': _fromSim,
          'dialSim': _dialSim,
          'canRetry': 0,
          'isAdvanced': 1,
        },
        'ussdCodes',
      );
    }
  }

  Future<void> getAndProcessCards() async {
    await SimDataPlugin.getSimData().then((value) {
      setState(() {
        sims = value.cards;
      });
      // debugPrint("Got cards");
    });
  }

  Future<void> getAllUSSDCodes() async {
    await _sqliteService.queryAll('ussdCodes').then(
      (value) {
        setState(() {
          ussdCodes = value;
        });
        // debugPrint('${ussdCodes.length}');
      },
    );
  }

  void addAdvancedColumn() async {
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'isAdvanced',
      'INTEGER',
    );
  }

  String getSimNames(List sims, int subId) {
    String res = "";
    int count = 0;
    for (var sim in sims) {
      if (subId < 0) {
        return "All Cards";
      }
      if (sim.subscriptionId == subId) {
        res += (count > 0) ? ", " : "";
        res += " ${sim.displayName} (${sim.slotIndex + 1})";
        count++;
      }
    }

    return res;
  }

  Widget getSimCards(int subId) {
    List<Widget> cards = [];
    for (var sim in sims) {
      if (subId < 0 || sim.subscriptionId == subId) {
        cards.add(
          SimCardIconWithNumber(number: sim.slotIndex + 1),
        );
      }
    }

    if (cards.isEmpty) {
      return Container(
        padding: EdgeInsets.symmetric(
          horizontal: kPagePadding / 5,
          // vertical: kPagePadding / 4,
        ),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(kBorderRadius / 2),
        ),
        child: Text(
          "Default (1st)",
          style: TextStyle(fontSize: 14),
        ),
      );
    }

    return Row(
      children: cards,
    );
  }

  Future<void> changeSimCard() async {
    SimCard? simCard = await chooseSim(context, sims);

    if (simCard != null) {
      _dialSim = simCard.subscriptionId;

      await _sqliteService.updateStuff(
        {'dialSim': _dialSim},
        'dialSim > ?',
        [-1],
        'ussdCodes',
      );

      setState(() {});
    } else {}

    refreshPage();
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          setState(() {
            _selectionMode = false;
            _selectedTransactionIds.clear();
          });
          return false; // Prevents popping the page
        }
        return true; // Allows popping the page
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // editUSSDEntry(context, textTheme),
                if (_selectionMode)
                  Container(
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(kBorderRadius),
                        bottomRight: Radius.circular(kBorderRadius),
                      ),
                      color: Theme.of(context).cardColor,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // retry all selected transactions
                        IconButton(
                          icon: Icon(
                            _selectedTransactionIds.length == ussdCodes.length
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_selectedTransactionIds.length ==
                                  ussdCodes.length) {
                                _selectedTransactionIds.clear();
                                _selectionMode = false;
                              } else {
                                _selectedTransactionIds.clear();
                                for (var code in ussdCodes) {
                                  _selectedTransactionIds.add(code['id']);
                                }
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.delete),
                          onPressed: () async {
                            bool isConfirmed = await showConfirmDeleteDialog(
                                    context,
                                    title: "Delete",
                                    message:
                                        "Are you sure you want to delete the selected offers?") ??
                                false;
                            if (isConfirmed) {
                              for (var id in _selectedTransactionIds) {
                                _sqliteService.deleteStuff(
                                  id,
                                  'ussdCodes',
                                );
                              }
                              showSuccessDialog(context,
                                  text: 'Deleted offers successfully');
                              setState(() {
                                _selectionMode = false;
                                _selectedTransactionIds.clear();
                              });
                            }

                            getAllUSSDCodes();
                          },
                        ),
                      ],
                    ),
                  )
                else
                  header(context, 'My Offers'),
                const SizedBox(height: kPagePadding / 2),
                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _topBar(),
                ),
                ussdCodes.isEmpty
                    ? Padding(
                        padding: kPagePaddingInsets,
                        child: GestureDetector(
                          onTap: () {
                            makeOfferTutorialDialog(context);
                          },
                          child: Container(
                            padding: kPagePaddingInsets,
                            decoration: BoxDecoration(
                                color: Theme.of(context).cardColor),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.question_square,
                                  color: Theme.of(context).indicatorColor,
                                ),
                                SizedBox(width: kPagePadding / 4),
                                Text('How to make an offer'),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: kPagePaddingInsets,
                        child: Wrap(
                          spacing: kPagePadding / 4,
                          runSpacing: kPagePadding / 2,
                          children: ussdCodes.map(
                            (ussdCode) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                    bottom: kPagePadding / 2),
                                child: ussdCodeListItem(
                                  context,
                                  ussdCode['id'],
                                  ussdCode['code'],
                                  ussdCode['amount'],
                                  ussdCode['fromSim'],
                                  ussdCode['dialSim'],
                                  sims,
                                  ussdCode['enabled'] == 1,
                                ),
                              );
                            },
                          ).toList(),
                        ),
                      ),
                const SizedBox(height: kPagePadding * 2),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context)
                .push(
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const EditOfferPage(),
                    transitionsBuilder:
                        (context, animation, secondaryAnimation, child) {
                      // Define your custom animation here
                      // return FadeTransition(opacity: animation, child: child);
                      return CupertinoPageTransition(
                        primaryRouteAnimation: animation,
                        secondaryRouteAnimation: secondaryAnimation,
                        linearTransition: true,
                        child: child,
                      );
                    },
                  ),
                )
                .then((value) => getAllUSSDCodes());
          },
          child: Icon(CupertinoIcons.plus),
        ),
      ),
    );
  }

  Widget ussdCodeListItem(
    BuildContext context,
    int id,
    String code,
    int amount,
    int fromSim,
    int dialSim,
    List sims,
    bool isEnabled,
    // VoidCallback onBack,
  ) {
    var textTheme = Theme.of(context).textTheme;

    var isSelected = _selectedTransactionIds.contains(id);

    return GestureDetector(
      onLongPress: () {
        setState(() {
          _selectionMode = true;
          _selectedTransactionIds.add(id);
        });
      },
      onTap: () {
        if (_selectionMode) {
          setState(() {
            if (isSelected) {
              _selectedTransactionIds.remove(id);
              if (_selectedTransactionIds.isEmpty) _selectionMode = false;
            } else {
              _selectedTransactionIds.add(id);
            }
          });
        } else {
          Navigator.of(context)
              .push(
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      EditOfferPage(ruleId: id),
                  transitionsBuilder:
                      (context, animation, secondaryAnimation, child) {
                    return CupertinoPageTransition(
                      primaryRouteAnimation: animation,
                      secondaryRouteAnimation: secondaryAnimation,
                      linearTransition: true,
                      child: child,
                    );
                  },
                ),
              )
              .then((value) => getAllUSSDCodes());
        }
      },
      child: Container(
        padding: kPagePaddingInsets,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.blue.withOpacity(0.2)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      "KSH",
                      style: textTheme.labelSmall,
                    ),
                    Text(
                      " $amount",
                      style: textTheme.titleLarge,
                      // !.merge(
                      //   const TextStyle(color: kPrimaryColor),
                      // ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "from",
                      // style: textTheme.labelSmall!.merge(kTitleText),
                      style: textTheme.labelSmall,
                    ),
                    const SizedBox(width: kPagePadding / 4),
                    getSimCards(fromSim),
                    const SizedBox(width: kPagePadding),
                    Text(
                      "Dial",
                      style: textTheme.labelSmall,
                    ),
                    const SizedBox(width: kPagePadding / 4),
                    getSimCards(dialSim),
                  ],
                ),
                const SizedBox(height: kPagePadding / 1.5),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: kPagePadding / 3,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(context).indicatorColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(kBorderRadius / 2),
                  ),
                  child: Text(
                    code,
                    style: TextStyle(
                      fontSize: 14,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Switch(
                  value: isEnabled,
                  // activeColor: Theme.of(context).indicatorColor,
                  onChanged: (value) {
                    enableOffer(value, id);
                    getAllUSSDCodes();
                  },
                ),
                const SizedBox(height: kPagePadding),
                Icon(
                  Icons.edit,
                  color: kPrimaryColor,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _topBar() {
    return Container(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          PopupMenuButton<String>(
            icon: Icon(CupertinoIcons.gear),
            onSelected: (value) async {
              // Handle menu option selection here
              if (value == 'changeSimCard') {
                changeSimCard();
                // Navigate to settings or show dialog
              } else if (value == 'downloadOffers') {
                showLoadingDialog(context, text: "Downloading");
                String filePath = await FileService.downloadOffersToCsv();
                Navigator.pop(context);
                if (filePath.isNotEmpty) {
                  showSuccessDialog(context,
                      text: "File downloaded to $filePath");
                }
              } else if (value == 'updateOffers') {
                // Call a function to update offers
                // addOffers();
                // getAllUSSDCodes();
              } else if (value == 'makeOfferTutorial') {
                makeOfferTutorialDialog(context);
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                value: 'changeSimCard',
                child: Text('Change SIM Card'),
              ),
              PopupMenuItem(
                value: 'downloadOffers',
                child: Text('Download offers'),
              ),
              PopupMenuItem(
                value: 'updateOffers',
                child: Text('Update offers (from file)'),
              ),
              PopupMenuItem(
                value: 'makeOfferTutorial',
                child: Text('How to make an offer'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
