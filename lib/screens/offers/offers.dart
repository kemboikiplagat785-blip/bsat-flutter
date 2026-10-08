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
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:another_telephony/telephony.dart';

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
  List<SubscriptionInfo> sims = [];

  final int _fromSim = -1;
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
  }

  // ---------------------------------------------------------------------------
  // PAGE REFRESH
  // ---------------------------------------------------------------------------

  Future<void> refreshPage() async {
    if (!mounted) return;

    showLoadingDialog(context);

    try {
      await getAllUSSDCodes();
      await getAndProcessCards();
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
        setState(() {});
      }
    }
  }

  // ---------------------------------------------------------------------------
  // ENABLE / DISABLE OFFER
  // ---------------------------------------------------------------------------

  Future<void> enableOffer(bool isEnabled, int id) async {
    final existingOffer = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [id],
      columns: ['enabled'],
      limit: 1,
    );
    final wasPaused = existingOffer.isNotEmpty &&
        int.tryParse(existingOffer.first['enabled']?.toString() ?? '') == 0;

    await _sqliteService.updateStuff(
      {
        'enabled': isEnabled ? 1 : 0,
      },
      'id = ?',
      [id],
      'ussdCodes',
    );

    final resume = isEnabled && wasPaused
        ? TransactionController().resumePausedTransactionsForOffer(id)
        : Future<void>.value();
    if (mounted) {
      await refreshPage();
    }
    await resume;
  }

  // ---------------------------------------------------------------------------
  // ADD DEFAULT OFFERS
  // ---------------------------------------------------------------------------

  Future<void> addOffers() async {
    for (final i in kNoAutoretryCodes) {
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
        await _sqliteService.insertStuff(
          {
            'ussdCodeId': id,
            'code': i["code"],
            'startTime': null,
            'endTime': null,
          },
          'ussdCodeVariants',
        );
      } catch (e) {
        debugPrint('Error adding USSD variant: $e');
      }
    }

    await getAllUSSDCodes();
  }

  // ---------------------------------------------------------------------------
  // SIM CARD HANDLING
  //
  // Uses another_telephony like 4.1.0.
  // ---------------------------------------------------------------------------

  Future<void> getAndProcessCards() async {
    try {
      final value = await Telephony.instance.getSubscriptionList();

      if (!mounted) return;

      setState(() {
        sims = value;
      });
    } catch (e) {
      debugPrint('Error getting SIM cards: $e');

      if (!mounted) return;

      setState(() {
        sims = [];
      });
    }
  }

  // ---------------------------------------------------------------------------
  // LOAD ALL OFFERS
  // ---------------------------------------------------------------------------

  Future<void> getAllUSSDCodes() async {
    try {
      // Self-heal any ussdCodes rows still missing a
      // ussdCodeVariants row.
      await _sqliteService.backfillOrphanedUssdCodeVariants();

      // Join ussdCodes with ussdCodeVariants so each returned
      // row has its USSD code and time window.
      final rows = await _sqliteService.rawQueryInput(
        '''
        SELECT
          u.id as id,
          v.code as code,
          v.startTime as startTime,
          v.endTime as endTime,
          v.alternativeUssdCode as alternativeUssdCode,
          v.runAltOn as runAltOn,
          v.altIsAdvanced as altIsAdvanced,
          v.altDelayMinutes as altDelayMinutes,
          u.amount as amount,
          u.fromSim as fromSim,
          u.dialSim as dialSim,
          u.enabled as enabled,
          u.offerName as offerName
        FROM ussdCodes u
        JOIN ussdCodeVariants v
          ON u.id = v.ussdCodeId
        ORDER BY u.amount, v.code
        ''',
        [],
      );

      if (!mounted) return;

      setState(() {
        ussdCodes = rows;
      });

      debugPrint(
        'All Offers: ${await _sqliteService.queryAll('ussdCodes')}',
      );

      debugPrint(
        'All Variants: '
        '${await _sqliteService.queryAll('ussdCodeVariants')}',
      );
    } catch (e) {
      debugPrint('Error loading offers: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // DATABASE MIGRATION
  // ---------------------------------------------------------------------------

  Future<void> addAdvancedColumn() async {
    await _sqliteService.addColumnIfNotExists(
      'ussdCodes',
      'isAdvanced',
      'INTEGER',
    );
  }

  // ---------------------------------------------------------------------------
  // SIM NAME
  // ---------------------------------------------------------------------------

  String getSimNames(List sims, int subId) {
    String res = "";
    int count = 0;

    for (final sim in sims) {
      if (subId < 0) {
        return "All Cards";
      }

      if (sim.subscriptionId == subId) {
        res += (count > 0) ? ", " : "";

        res += " ${sim.displayName} (${(sim.simSlotIndex ?? 0) + 1})";

        count++;
      }
    }

    return res;
  }

  // ---------------------------------------------------------------------------
  // SIM CARD ICONS
  // ---------------------------------------------------------------------------

  Widget getSimCards(int subId) {
    final List<Widget> cards = [];

    for (final sim in sims) {
      final int slotIndex = sim.simSlotIndex ?? 0;

      if (subId < 0 || sim.subscriptionId == subId) {
        cards.add(
          SimCardIconWithNumber(
            number: slotIndex + 1,
          ),
        );
      }
    }

    if (cards.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: kPagePadding / 5,
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: Colors.grey,
          ),
          borderRadius: BorderRadius.circular(
            kBorderRadius / 2,
          ),
        ),
        child: const Text(
          "Default (1st)",
          style: TextStyle(
            fontSize: 14,
          ),
        ),
      );
    }

    return Row(
      children: cards,
    );
  }

  // ---------------------------------------------------------------------------
  // CHANGE DEFAULT DIAL SIM
  // ---------------------------------------------------------------------------

  Future<void> changeSimCard() async {
    final SubscriptionInfo? simCard = await chooseSim(
      context,
      sims,
    );

    if (simCard != null) {
      final int? subscriptionId = simCard.subscriptionId;

      if (subscriptionId != null) {
        _dialSim = subscriptionId;

        await _sqliteService.updateStuff(
          {
            'dialSim': _dialSim,
          },
          'dialSim > ?',
          [-1],
          'ussdCodes',
        );
      }

      if (mounted) {
        setState(() {});
      }
    }

    if (mounted) {
      await refreshPage();
    }
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          setState(() {
            _selectionMode = false;
            _selectedTransactionIds.clear();
          });

          return false;
        }

        return true;
      },
      child: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // -------------------------------------------------------------
                // SELECTION BAR
                // -------------------------------------------------------------

                if (_selectionMode)
                  Container(
                    padding: kPagePaddingInsets,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(
                          kBorderRadius,
                        ),
                        bottomRight: Radius.circular(
                          kBorderRadius,
                        ),
                      ),
                      color: Theme.of(context).cardColor,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Select all
                        IconButton(
                          icon: Icon(
                            _selectedTransactionIds.length ==
                                    ussdCodes.map((e) => e['id']).toSet().length
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                          ),
                          onPressed: () {
                            setState(() {
                              final ids = ussdCodes
                                  .map(
                                    (code) => code['id'] as int,
                                  )
                                  .toSet();

                              if (_selectedTransactionIds.length ==
                                  ids.length) {
                                _selectedTransactionIds.clear();
                                _selectionMode = false;
                              } else {
                                _selectedTransactionIds
                                  ..clear()
                                  ..addAll(ids);
                              }
                            });
                          },
                        ),

                        // Delete selected
                        IconButton(
                          icon: const Icon(
                            CupertinoIcons.delete,
                          ),
                          onPressed: () async {
                            final bool isConfirmed =
                                await showConfirmDeleteDialog(
                                      context,
                                      title: "Delete",
                                      message:
                                          "Are you sure you want to delete the selected offers?",
                                    ) ??
                                    false;

                            if (!isConfirmed) return;

                            final ids = Set<int>.from(_selectedTransactionIds);

                            for (final id in ids) {
                              await _sqliteService.deleteWhere(
                                'ussdCodeVariants',
                                'ussdCodeId = ?',
                                [id],
                              );

                              await _sqliteService.deleteStuff(
                                id,
                                'ussdCodes',
                              );
                            }

                            if (mounted) {
                              showSuccessDialog(
                                context,
                                text: 'Deleted offers successfully',
                              );

                              setState(() {
                                _selectionMode = false;
                                _selectedTransactionIds.clear();
                              });
                            }

                            await getAllUSSDCodes();
                          },
                        ),
                      ],
                    ),
                  )
                else
                  header(
                    context,
                    'My Offers',
                  ),

                const SizedBox(
                  height: kPagePadding / 2,
                ),

                // -------------------------------------------------------------
                // TOP BAR
                // -------------------------------------------------------------

                Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: _topBar(),
                ),

                // -------------------------------------------------------------
                // EMPTY / OFFER LIST
                // -------------------------------------------------------------

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
                              color: Theme.of(context).cardColor,
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  CupertinoIcons.question_square,
                                  color: Theme.of(context).indicatorColor,
                                ),
                                SizedBox(
                                  width: kPagePadding / 4,
                                ),
                                const Text(
                                  'How to make an offer',
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    : Padding(
                        padding: kPagePaddingInsets,
                        child: Builder(
                          builder: (context) {
                            // -------------------------------------------------
                            // GROUP 1:
                            // Same offer ID with multiple USSD variants.
                            // -------------------------------------------------

                            final Map<int, List<Map<String, dynamic>>> byId =
                                {};

                            for (final item in ussdCodes) {
                              final int id = item['id'] as int;

                              byId.putIfAbsent(id, () => []).add(item);
                            }

                            // -------------------------------------------------
                            // GROUP 2:
                            // Single-variant offers sharing the same USSD
                            // code but representing different amounts/tiers.
                            // -------------------------------------------------

                            final Map<String, List<Map<String, dynamic>>>
                                codeGroups = {};

                            for (final item in ussdCodes) {
                              final int id = item['id'] as int;

                              if (byId[id]!.length == 1) {
                                final String code =
                                    (item['code'] ?? '').toString();

                                codeGroups
                                    .putIfAbsent(
                                      code,
                                      () => [],
                                    )
                                    .add(item);
                              }
                            }

                            // -------------------------------------------------
                            // Preserve original amount/code ordering.
                            // -------------------------------------------------

                            final List<Widget> tiles = [];

                            final Set<int> seenIds = {};
                            final Set<String> seenCodes = {};

                            for (final item in ussdCodes) {
                              final int id = item['id'] as int;

                              // Multiple variants under one offer ID.
                              if (byId[id]!.length > 1) {
                                if (seenIds.add(id)) {
                                  tiles.add(
                                    _buildOfferCardWithVariants(
                                      byId[id]!,
                                    ),
                                  );
                                }

                                continue;
                              }

                              // Different tiers sharing the same code.
                              final String code =
                                  (item['code'] ?? '').toString();

                              if (seenCodes.add(code)) {
                                final items = codeGroups[code]!;

                                tiles.add(
                                  items.length == 1
                                      ? _buildOfferCard(
                                          items.first,
                                        )
                                      : _buildOfferGroupCard(
                                          code,
                                          items,
                                        ),
                                );
                              }
                            }

                            return Column(
                              children: tiles
                                  .map(
                                    (tile) => Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: kPagePadding / 2,
                                      ),
                                      child: tile,
                                    ),
                                  )
                                  .toList(),
                            );
                          },
                        ),
                      ),

                const SizedBox(
                  height: kPagePadding * 2,
                ),
              ],
            ),
          ),
        ),

        // ---------------------------------------------------------------------
        // ADD OFFER
        // ---------------------------------------------------------------------

        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.of(context)
                .push(
                  PageRouteBuilder(
                    pageBuilder: (
                      context,
                      animation,
                      secondaryAnimation,
                    ) =>
                        const EditOfferPage(),
                    transitionsBuilder: (
                      context,
                      animation,
                      secondaryAnimation,
                      child,
                    ) {
                      return CupertinoPageTransition(
                        primaryRouteAnimation: animation,
                        secondaryRouteAnimation: secondaryAnimation,
                        linearTransition: true,
                        child: child,
                      );
                    },
                  ),
                )
                .then(
                  (_) => getAllUSSDCodes(),
                );
          },
          child: const Icon(
            CupertinoIcons.plus,
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // OPEN OFFER
  // ---------------------------------------------------------------------------

  void _openOffer(int id) {
    if (_selectionMode) {
      setState(() {
        if (_selectedTransactionIds.contains(id)) {
          _selectedTransactionIds.remove(id);

          if (_selectedTransactionIds.isEmpty) {
            _selectionMode = false;
          }
        } else {
          _selectedTransactionIds.add(id);
        }
      });

      return;
    }

    Navigator.of(context)
        .push(
          PageRouteBuilder(
            pageBuilder: (
              context,
              animation,
              secondaryAnimation,
            ) =>
                EditOfferPage(
              ruleId: id,
            ),
            transitionsBuilder: (
              context,
              animation,
              secondaryAnimation,
              child,
            ) {
              return CupertinoPageTransition(
                primaryRouteAnimation: animation,
                secondaryRouteAnimation: secondaryAnimation,
                linearTransition: true,
                child: child,
              );
            },
          ),
        )
        .then(
          (_) => getAllUSSDCodes(),
        );
  }

  // ---------------------------------------------------------------------------
  // START MULTI-SELECTION
  // ---------------------------------------------------------------------------

  void _startSelecting(int id) {
    setState(() {
      _selectionMode = true;
      _selectedTransactionIds.add(id);
    });
  }

  // ---------------------------------------------------------------------------
  // DELETE SINGLE OFFER
  // ---------------------------------------------------------------------------

  Future<void> _deleteOffer(int id) async {
    final bool confirmed = await showConfirmDeleteDialog(
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

    await _sqliteService.deleteStuff(
      id,
      'ussdCodes',
    );

    await getAllUSSDCodes();
  }

  // ---------------------------------------------------------------------------
  // AMOUNT CHIP
  // ---------------------------------------------------------------------------

  Widget _amountChip(
    Map<String, dynamic> item,
  ) {
    final bool isEnabled = (item['enabled'] ?? 1) == 1;

    final Color color = isEnabled ? kPrimaryColor : Theme.of(context).hintColor;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: isEnabled
            ? kPrimaryColor.withValues(alpha: 0.1)
            : Theme.of(context).dividerColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(
          kBorderRadius / 2,
        ),
        border: Border.all(
          color: isEnabled
              ? kPrimaryColor.withValues(alpha: 0.3)
              : Theme.of(context).dividerColor.withValues(alpha: 0.2),
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

  // ---------------------------------------------------------------------------
  // CODE CHIP
  // ---------------------------------------------------------------------------

  Widget _codeChip(String code) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kPagePadding / 3,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).indicatorColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
          kBorderRadius / 2,
        ),
      ),
      child: Text(
        code,
        style: const TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PAUSED TAG
  // ---------------------------------------------------------------------------

  Widget _pausedTag() {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: kGrayColor,
        borderRadius: BorderRadius.circular(
          kBorderRadius / 2,
        ),
      ),
      child: const Text(
        'PAUSED',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // STATUS BADGE
  // ---------------------------------------------------------------------------

  Widget _statusBadge(
    int activeCount,
    int total,
  ) {
    final bool allActive = activeCount == total;

    final bool allPaused = activeCount == 0;

    final Color color =
        allActive ? kPrimaryColor : (allPaused ? kErrorColor : kWarningColor);

    final String label = allActive
        ? 'All active'
        : (allPaused ? 'All paused' : '$activeCount/$total active');

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(
          kBorderRadius / 2,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TIME WINDOW
  // ---------------------------------------------------------------------------

  Widget? _timeWindowChip(
    Map<String, dynamic> item,
  ) {
    final String start = (item['startTime'] ?? '').toString();

    final String end = (item['endTime'] ?? '').toString();

    if (start.isEmpty || end.isEmpty) {
      return null;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: kIndigoColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(
          kBorderRadius / 2,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            CupertinoIcons.clock,
            size: 11,
            color: kIndigoColor,
          ),
          const SizedBox(width: 4),
          Text(
            '$start - $end',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: kIndigoColor,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SIM ROW
  // ---------------------------------------------------------------------------

  Widget _simRow(
    int fromSim,
    int dialSim,
  ) {
    return Row(
      children: [
        Text(
          'From',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).hintColor,
          ),
        ),
        const SizedBox(
          width: kPagePadding / 4,
        ),
        getSimCards(fromSim),
        const SizedBox(
          width: kPagePadding,
        ),
        Text(
          'Dial',
          style: TextStyle(
            fontSize: 11,
            color: Theme.of(context).hintColor,
          ),
        ),
        const SizedBox(
          width: kPagePadding / 4,
        ),
        getSimCards(dialSim),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // SINGLE OFFER CARD
  // ---------------------------------------------------------------------------

  Widget _buildOfferCard(
    Map<String, dynamic> item,
  ) {
    final int id = item['id'] as int;

    final bool isEnabled = (item['enabled'] ?? 1) == 1;

    final bool isSelected = _selectedTransactionIds.contains(id);

    final String? offerName = item['offerName']?.toString();

    final bool hasCustomName = offerName != null &&
        offerName.isNotEmpty &&
        offerName != 'Ksh ${item['amount']}';

    return GestureDetector(
      onLongPress: () => _startSelecting(id),
      onTap: () => _openOffer(id),
      child: Container(
        padding: kPagePaddingInsets,
        decoration: BoxDecoration(
          color: isSelected
              ? kPrimaryColor.withValues(alpha: 0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(
            kBorderRadius,
          ),
          border: isSelected
              ? Border.all(
                  color: kPrimaryColor,
                  width: 1.5,
                )
              : null,
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
                      Text(
                        'KSH ',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        '${item['amount']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (!isEnabled) ...[
                        const SizedBox(width: 8),
                        _pausedTag(),
                      ],
                    ],
                  ),
                  if (hasCustomName)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 2,
                      ),
                      child: Text(
                        offerName,
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(
                    height: kPagePadding / 2,
                  ),
                  _simRow(
                    item['fromSim'] as int,
                    item['dialSim'] as int,
                  ),
                  const SizedBox(
                    height: kPagePadding / 2,
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _codeChip(
                        (item['code'] ?? '').toString(),
                      ),
                      if (_timeWindowChip(item) != null) _timeWindowChip(item)!,
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(
              width: kPagePadding / 2,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isEnabled,
                  onChanged: (value) => enableOffer(
                    value,
                    id,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.delete,
                    color: kErrorColor,
                    size: 20,
                  ),
                  onPressed: () => _deleteOffer(id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MULTIPLE VARIANTS FOR SAME OFFER
  // ---------------------------------------------------------------------------

  Widget _buildOfferCardWithVariants(
    List<Map<String, dynamic>> items,
  ) {
    final Map<String, dynamic> first = items.first;

    final int id = first['id'] as int;

    final bool isEnabled = (first['enabled'] ?? 1) == 1;

    final bool isSelected = _selectedTransactionIds.contains(id);

    final String? offerName = first['offerName']?.toString();

    final bool hasCustomName = offerName != null &&
        offerName.isNotEmpty &&
        offerName != 'Ksh ${first['amount']}';

    return GestureDetector(
      onLongPress: () => _startSelecting(id),
      onTap: () => _openOffer(id),
      child: Container(
        padding: kPagePaddingInsets,
        decoration: BoxDecoration(
          color: isSelected
              ? kPrimaryColor.withValues(alpha: 0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(
            kBorderRadius,
          ),
          border: isSelected
              ? Border.all(
                  color: kPrimaryColor,
                  width: 1.5,
                )
              : null,
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
                      Text(
                        'KSH ',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                      Text(
                        '${first['amount']}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      if (!isEnabled) ...[
                        const SizedBox(width: 8),
                        _pausedTag(),
                      ],
                    ],
                  ),
                  if (hasCustomName)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: 2,
                      ),
                      child: Text(
                        offerName,
                        style: TextStyle(
                          color: Theme.of(context).hintColor,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  const SizedBox(
                    height: kPagePadding / 2,
                  ),
                  _simRow(
                    first['fromSim'] as int,
                    first['dialSim'] as int,
                  ),
                  const SizedBox(
                    height: kPagePadding / 2,
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: List.generate(
                      items.length,
                      (index) {
                        final Map<String, dynamic> it = items[index];

                        final Widget? timeWindow = _timeWindowChip(it);

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: index == items.length - 1 ? 0 : 6,
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(
                                    context,
                                  ).hintColor.withValues(
                                        alpha: 0.12,
                                      ),
                                  borderRadius: BorderRadius.circular(
                                    kBorderRadius / 2,
                                  ),
                                ),
                                child: Text(
                                  'Code ${index + 1}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(
                                      context,
                                    ).hintColor,
                                  ),
                                ),
                              ),
                              const SizedBox(
                                width: 6,
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    _codeChip(
                                      (it['code'] ?? '').toString(),
                                    ),
                                    if (timeWindow != null) timeWindow,
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(
              width: kPagePadding / 2,
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: isEnabled,
                  onChanged: (value) => enableOffer(
                    value,
                    id,
                  ),
                ),
                IconButton(
                  icon: const Icon(
                    CupertinoIcons.delete,
                    color: kErrorColor,
                    size: 20,
                  ),
                  onPressed: () => _deleteOffer(id),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // GROUPED TIERS SHARING SAME USSD CODE
  // ---------------------------------------------------------------------------

  Widget _buildOfferGroupCard(
    String code,
    List<Map<String, dynamic>> items,
  ) {
    final bool isExpanded = _expandedCodes.contains(code);

    final int activeCount = items
        .where(
          (it) => (it['enabled'] ?? 1) == 1,
        )
        .length;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(
          kBorderRadius,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(
              kBorderRadius,
            ),
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
                            Icon(
                              Icons.layers,
                              size: 14,
                              color: Theme.of(
                                context,
                              ).hintColor,
                            ),
                            const SizedBox(
                              width: 6,
                            ),
                            Text(
                              '${items.length} tiers on this code',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(
                                  context,
                                ).hintColor,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(
                          height: kPagePadding / 2,
                        ),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: (List<Map<String, dynamic>>.from(
                            items,
                          )..sort(
                                  (a, b) {
                                    final int amountA =
                                        (a['amount'] ?? 0) as int;

                                    final int amountB =
                                        (b['amount'] ?? 0) as int;

                                    return amountA.compareTo(
                                      amountB,
                                    );
                                  },
                                ))
                              .map(
                                (it) => _amountChip(it),
                              )
                              .toList(),
                        ),
                        const SizedBox(
                          height: kPagePadding / 2,
                        ),
                        _codeChip(code),
                        const SizedBox(
                          height: kPagePadding / 2,
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: _simRow(
                                items.first['fromSim'] as int,
                                items.first['dialSim'] as int,
                              ),
                            ),
                            _statusBadge(
                              activeCount,
                              items.length,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(
              height: 1,
              color: Colors.white24,
            ),
            ...items.map(
              (it) => _buildTierRow(it),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INDIVIDUAL TIER
  // ---------------------------------------------------------------------------

  Widget _buildTierRow(
    Map<String, dynamic> item,
  ) {
    final int id = item['id'] as int;

    final bool isEnabled = (item['enabled'] ?? 1) == 1;

    final bool isSelected = _selectedTransactionIds.contains(id);

    final String? offerName = item['offerName']?.toString();

    final bool hasCustomName = offerName != null &&
        offerName.isNotEmpty &&
        offerName != 'Ksh ${item['amount']}';

    return GestureDetector(
      onLongPress: () => _startSelecting(id),
      onTap: () => _openOffer(id),
      child: Container(
        color: isSelected ? kPrimaryColor.withValues(alpha: 0.12) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: kPagePadding,
          vertical: kPagePadding / 3,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'KSH ${item['amount']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (!isEnabled) ...[
                        const SizedBox(
                          width: 8,
                        ),
                        _pausedTag(),
                      ],
                    ],
                  ),
                  if (hasCustomName)
                    Text(
                      offerName,
                      style: TextStyle(
                        color: Theme.of(context).hintColor,
                        fontSize: 12,
                      ),
                    ),
                  if (_timeWindowChip(item) != null) ...[
                    const SizedBox(
                      height: 4,
                    ),
                    _timeWindowChip(item)!,
                  ],
                ],
              ),
            ),
            Switch(
              value: isEnabled,
              onChanged: (value) => enableOffer(
                value,
                id,
              ),
            ),
            IconButton(
              icon: const Icon(
                Icons.edit,
                color: kPrimaryColor,
                size: 20,
              ),
              onPressed: () => _openOffer(id),
            ),
            IconButton(
              icon: const Icon(
                CupertinoIcons.delete,
                color: kErrorColor,
                size: 20,
              ),
              onPressed: () => _deleteOffer(id),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // TOP SETTINGS MENU
  // ---------------------------------------------------------------------------

  Widget _topBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        PopupMenuButton<String>(
          icon: const Icon(
            CupertinoIcons.gear,
          ),
          onSelected: (value) async {
            // ---------------------------------------------------------------
            // CHANGE SIM
            // ---------------------------------------------------------------

            if (value == 'changeSimCard') {
              await changeSimCard();
              return;
            }

            // ---------------------------------------------------------------
            // DOWNLOAD OFFERS
            // ---------------------------------------------------------------

            if (value == 'downloadOffers') {
              if (!mounted) return;

              final String? format = await showDialog<String>(
                context: context,
                builder: (dialogContext) {
                  return AlertDialog(
                    title: const Text('Download offers'),
                    content: const Text(
                      'Choose the file format:',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop('csv');
                        },
                        child: const Text('CSV'),
                      ),
                      TextButton(
                        onPressed: () {
                          Navigator.of(dialogContext).pop('vcf');
                        },
                        child: const Text('VCF'),
                      ),
                    ],
                  );
                },
              );

              if (!mounted || format == null) return;

              showLoadingDialog(
                context,
                text: "Downloading",
              );

              try {
                final String filePath;

                if (format == 'vcf') {
                  filePath = await FileService.downloadOffersToVcf();
                } else {
                  filePath = await FileService.downloadOffersToCsv();
                }

                if (!mounted) return;

                Navigator.of(context).pop();

                if (filePath.isNotEmpty) {
                  showSuccessDialog(
                    context,
                    text: "File downloaded to $filePath",
                  );
                }
              } catch (e) {
                if (!mounted) return;

                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Download failed: $e',
                    ),
                  ),
                );
              }

              return;
            }

            // ---------------------------------------------------------------
            // UPDATE OFFERS
            // ---------------------------------------------------------------

            if (value == 'updateOffers') {
              if (!mounted) return;

              showLoadingDialog(
                context,
                text: "Updating offers",
              );

              try {
                await FileService().updateFromFile();

                if (!mounted) return;

                await getAllUSSDCodes();

                if (!mounted) return;

                Navigator.of(context).pop();

                showSuccessDialog(
                  context,
                  text: "Offers updated successfully",
                );
              } catch (e) {
                if (!mounted) return;

                Navigator.of(context).pop();

                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      'Update failed: $e',
                    ),
                  ),
                );
              }

              return;
            }

            // ---------------------------------------------------------------
            // TUTORIAL
            // ---------------------------------------------------------------

            if (value == 'makeOfferTutorial') {
              makeOfferTutorialDialog(context);
              return;
            }

            // ---------------------------------------------------------------
            // DOWNLOAD FROM ANOTHER PHONE
            // ---------------------------------------------------------------

            if (value == 'getOffersFromAnotherPhone') {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const DownloadOffersPage(),
                ),
              );

              if (mounted) {
                await getAllUSSDCodes();
              }
            }
          },
          itemBuilder: (BuildContext context) => [
            const PopupMenuItem(
              value: 'changeSimCard',
              child: Text(
                'Change SIM Card',
              ),
            ),
            const PopupMenuItem(
              value: 'downloadOffers',
              child: Text(
                'Download offers',
              ),
            ),
            const PopupMenuItem(
              value: 'updateOffers',
              child: Text(
                'Update offers (from file)',
              ),
            ),
            const PopupMenuItem(
              value: 'makeOfferTutorial',
              child: Text(
                'How to make an offer',
              ),
            ),
            const PopupMenuItem(
              value: 'getOffersFromAnotherPhone',
              child: Text(
                'Download offers from another phone',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
