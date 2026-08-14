import 'package:bsat/components/card_with_number.dart';
import 'package:bsat/components/dialogs/choose_sim.dart';
import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/loading_dialog.dart';
import 'package:bsat/components/dialogs/success_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/screens/offers/edit_offer.dart';
import 'package:bsat/screens/offers/download_offers_page.dart';
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
  final Set<String> _expandedCodes = {};

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

  Future<void> addOffers() async {
    for (var i in kNoAutoretryCodes) {
      final id = await _sqliteService.insertStuff(
        {
          'amount': i["amount"],
          'fromSim': _fromSim,
          'dialSim': _dialSim,
          'canRetry': 0,
          'isAdvanced': 1,
          'enabled': 1,
          'offerName': i["offerName"] ?? 'Ksh ${i["amount"]}',
        },
        'ussdCodes',
      );

      try {
        await _sqliteService.insertStuff({
          'ussdCodeId': id,
          'code': i["code"],
          'startTime': null,
          'endTime': null,
        },
        'ussdCodeVariants');
      } catch (e) {}
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
    // Self-heal any ussdCodes rows still missing a ussdCodeVariants row
    // (historical migration gaps, or offers created via CSV import/FCM push)
    // before listing offers, so they show up within this running session.
    await _sqliteService.backfillOrphanedUssdCodeVariants();

    // Join ussdCodes with ussdCodeVariants so each returned row has a `code` field
    final rows = await _sqliteService.rawQueryInput(
        'SELECT u.id as id, v.code as code, u.amount as amount, u.fromSim as fromSim, u.dialSim as dialSim, u.enabled as enabled, u.offerName as offerName FROM ussdCodes u JOIN ussdCodeVariants v ON u.id = v.ussdCodeId ORDER BY u.amount, v.code',
        []);
    setState(() {
      ussdCodes = rows;
    });
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
                                _sqliteService.deleteWhere(
                                  'ussdCodeVariants',
                                  'ussdCodeId = ?',
                                  [id],
                                );
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
                        child: Builder(builder: (context) {
                          // Group offers by the USSD code string
                          final Map<String, List<Map<String, dynamic>>> grouped = {};
                          for (var item in ussdCodes) {
                            final code = item['code'] ?? '';
                            grouped.putIfAbsent(code, () => []).add(item);
                          }

                          return Column(
                            children: grouped.entries.map((entry) {
                              final code = entry.key;
                              final items = entry.value;

                              return Padding(
                                padding: const EdgeInsets.only(bottom: kPagePadding / 2),
                                child: items.length == 1
                                    ? _buildOfferCard(items.first)
                                    : _buildOfferGroupCard(code, items),
                              );
                            }).toList(),
                          );
                        }),
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

  // --- Offer list rendering helpers ---

  void _openOffer(int id) {
    if (_selectionMode) {
      setState(() {
        if (_selectedTransactionIds.contains(id)) {
          _selectedTransactionIds.remove(id);
          if (_selectedTransactionIds.isEmpty) _selectionMode = false;
        } else {
          _selectedTransactionIds.add(id);
        }
      });
      return;
    }
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

  void _startSelecting(int id) {
    setState(() {
      _selectionMode = true;
      _selectedTransactionIds.add(id);
    });
  }

  Future<void> _deleteOffer(int id) async {
    final confirmed = await showConfirmDeleteDialog(
          context,
          title: 'Delete',
          message: 'Delete this offer?',
        ) ??
        false;
    if (!confirmed) return;
    await _sqliteService.deleteWhere(
      'ussdCodeVariants',
      'ussdCodeId = ?',
      [id],
    );
    await _sqliteService.deleteStuff(id, 'ussdCodes');
    getAllUSSDCodes();
  }

  Widget _amountChip(Map<String, dynamic> item) {
    final bool isEnabled = (item['enabled'] ?? 1) == 1;
    final Color color = isEnabled ? kPrimaryColor : Theme.of(context).hintColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: isEnabled
            ? kPrimaryColor.withOpacity(0.1)
            : Theme.of(context).dividerColor.withOpacity(0.08),
        borderRadius: BorderRadius.circular(kBorderRadius / 2),
        border: Border.all(
          color: isEnabled
              ? kPrimaryColor.withOpacity(0.3)
              : Theme.of(context).dividerColor.withOpacity(0.2),
        ),
      ),
      child: Text(
        'KSH ${item['amount']}',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
          decoration: isEnabled ? null : TextDecoration.lineThrough,
        ),
      ),
    );
  }

  Widget _codeChip(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: kPagePadding / 3, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).indicatorColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(kBorderRadius / 2),
      ),
      child: Text(
        code,
        style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _pausedTag() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kGrayColor,
        borderRadius: BorderRadius.circular(kBorderRadius / 2),
      ),
      child: const Text(
        'PAUSED',
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 0.5),
      ),
    );
  }

  Widget _statusBadge(int activeCount, int total) {
    final bool allActive = activeCount == total;
    final bool allPaused = activeCount == 0;
    final Color color = allActive
        ? kPrimaryColor
        : (allPaused ? kErrorColor : kWarningColor);
    final String label = allActive
        ? 'All active'
        : (allPaused ? 'All paused' : '$activeCount/$total active');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(kBorderRadius / 2),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color),
      ),
    );
  }

  Widget _simRow(int fromSim, int dialSim) {
    return Row(
      children: [
        Text('From', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
        const SizedBox(width: kPagePadding / 4),
        getSimCards(fromSim),
        const SizedBox(width: kPagePadding),
        Text('Dial', style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor)),
        const SizedBox(width: kPagePadding / 4),
        getSimCards(dialSim),
      ],
    );
  }

  Widget _buildOfferCard(Map<String, dynamic> item) {
    final int id = item['id'];
    final bool isEnabled = (item['enabled'] ?? 1) == 1;
    final bool isSelected = _selectedTransactionIds.contains(id);
    final String? offerName = item['offerName'];
    final bool hasCustomName =
        offerName != null && offerName.isNotEmpty && offerName != 'Ksh ${item['amount']}';

    return GestureDetector(
      onLongPress: () => _startSelecting(id),
      onTap: () => _openOffer(id),
      child: Container(
        padding: kPagePaddingInsets,
        decoration: BoxDecoration(
          color: isSelected
              ? kPrimaryColor.withOpacity(0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(kBorderRadius),
          border: isSelected ? Border.all(color: kPrimaryColor, width: 1.5) : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('KSH ', style: Theme.of(context).textTheme.labelSmall),
                      Text('${item['amount']}', style: Theme.of(context).textTheme.titleLarge),
                      if (!isEnabled) ...[
                        const SizedBox(width: 8),
                        _pausedTag(),
                      ],
                    ],
                  ),
                  if (hasCustomName)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        offerName,
                        style: TextStyle(color: Theme.of(context).hintColor, fontSize: 13),
                      ),
                    ),
                  const SizedBox(height: kPagePadding / 2),
                  _simRow(item['fromSim'], item['dialSim']),
                  const SizedBox(height: kPagePadding / 2),
                  _codeChip(item['code'] ?? ''),
                ],
              ),
            ),
            const SizedBox(width: kPagePadding / 2),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isEnabled,
                  onChanged: (value) => enableOffer(value, id),
                ),
                IconButton(
                  icon: const Icon(CupertinoIcons.delete, color: kErrorColor, size: 20),
                  onPressed: () => _deleteOffer(id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOfferGroupCard(String code, List<Map<String, dynamic>> items) {
    final bool isExpanded = _expandedCodes.contains(code);
    final int activeCount =
        items.where((it) => (it['enabled'] ?? 1) == 1).length;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(kBorderRadius),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedCodes.remove(code);
                } else {
                  _expandedCodes.add(code);
                }
              });
            },
            child: Padding(
              padding: kPagePaddingInsets,
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.layers, size: 14, color: Theme.of(context).hintColor),
                            const SizedBox(width: 6),
                            Text(
                              '${items.length} tiers on this code',
                              style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor),
                            ),
                          ],
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: (List<Map<String, dynamic>>.from(items)
                                ..sort((a, b) => ((a['amount'] ?? 0) as int)
                                    .compareTo((b['amount'] ?? 0) as int)))
                              .map((it) => _amountChip(it))
                              .toList(),
                        ),
                        const SizedBox(height: kPagePadding / 2),
                        _codeChip(code),
                        const SizedBox(height: kPagePadding / 2),
                        Row(
                          children: [
                            Expanded(child: _simRow(items.first['fromSim'], items.first['dialSim'])),
                            _statusBadge(activeCount, items.length),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(isExpanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1, color: Colors.white24),
            ...items.map((it) => _buildTierRow(it)),
          ],
        ],
      ),
    );
  }

  Widget _buildTierRow(Map<String, dynamic> item) {
    final int id = item['id'];
    final bool isEnabled = (item['enabled'] ?? 1) == 1;
    final bool isSelected = _selectedTransactionIds.contains(id);
    final String? offerName = item['offerName'];
    final bool hasCustomName =
        offerName != null && offerName.isNotEmpty && offerName != 'Ksh ${item['amount']}';

    return GestureDetector(
      onLongPress: () => _startSelecting(id),
      onTap: () => _openOffer(id),
      child: Container(
        color: isSelected ? kPrimaryColor.withOpacity(0.12) : null,
        padding: const EdgeInsets.symmetric(horizontal: kPagePadding, vertical: kPagePadding / 3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('KSH ${item['amount']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      if (!isEnabled) ...[
                        const SizedBox(width: 8),
                        _pausedTag(),
                      ],
                    ],
                  ),
                  if (hasCustomName)
                    Text(
                      offerName,
                      style: TextStyle(color: Theme.of(context).hintColor, fontSize: 12),
                    ),
                ],
              ),
            ),
            Switch(
              value: isEnabled,
              onChanged: (value) => enableOffer(value, id),
            ),
            IconButton(
              icon: const Icon(Icons.edit, color: kPrimaryColor, size: 20),
              onPressed: () => _openOffer(id),
            ),
            IconButton(
              icon: const Icon(CupertinoIcons.delete, color: kErrorColor, size: 20),
              onPressed: () => _deleteOffer(id),
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
              } else if (value == 'getOffersFromAnotherPhone') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const DownloadOffersPage(),
                  ),
                );
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
              PopupMenuItem(
                value: 'getOffersFromAnotherPhone',
                child: Text('Download offers from another phone'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
