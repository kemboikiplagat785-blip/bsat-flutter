import 'dart:async';

import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/transaction_list_item.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:sqflite/sqflite.dart';

import '../../components/dialogs/confirmation_dialog.dart';
import '../../components/dialogs/loading_dialog.dart';
import '../../components/tool_button.dart';
import '../../components/dialogs/till_done_dialogue.dart';

import '../../models/client.dart';
import '../../utils/constants.dart';

class TransactionHistoryPage extends StatefulWidget {
  final String? query;
  final bool isDashboard;

  const TransactionHistoryPage(
      {super.key, this.query, this.isDashboard = false});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  static const int _pageSize = 10;
  String date = getNormalDate(DateTime.now());

  Set<int> _selectedTransactionIds = {};
  bool _selectionMode = false;

  List<dynamic> _transactionList = [];
  List<Widget> _transactionListItems = [];

  int _successfulConfirmedCount = 0;
  int _successfulPendingCount = 0;
  int _failedCount = 0;
  int _secondAttemptCount = 0;
  int _blacklistedCount = 0;
  int _forwardedCount = 0;
  int _unavailableOfferCount = 0;
  int _pausedCount = 0;
  int _advancedCount = 0;
  int _okoaCount = 0;

  final _pagingController = PagingController<int, List<dynamic>>(
    firstPageKey: 0,
  );

  final _searchBarController = TextEditingController();

  var selectedDate = DateTime.now();
  String query = "";

  var databaseHelper = SQLiteService();

  final ScrollController _scrollController = ScrollController();
  double _lastOffset = 0.0;
  bool _isScrollingDown = false;

  void _onScroll() {
    // if (_scrollController.position.userScrollDirection ==
    //     ScrollDirection.reverse) {
    //   // Scrolling down
    //   _isScrollingDown = true;
    //   // debugPrint("Scrolling down: ${_scrollController.offset}");
    //   // Do something if needed
    // } else if (_scrollController.position.userScrollDirection ==
    //     ScrollDirection.forward) {
    //   // Scrolling up
    //   _isScrollingDown = false;
    //   // debugPrint("Scrolling up: ${_scrollController.offset}");
    //   // Do something if needed
    // }
    // _lastOffset = _scrollController.offset;

    // setState(() {});
  }

  Future<void> _selectDate(BuildContext context) async {
    await showDatePicker(
            context: context,
            initialDate: selectedDate,
            firstDate: DateTime(2015, 8),
            lastDate: DateTime(2101))
        .then((value) {
      setState(() {
        selectedDate = value!;
        date = getNormalDate(selectedDate);
      });
      return null;
    }).then((value) => reloadForNewDate());
    // debugPrint("changed date");
  }

  Future<void> reloadForNewDate({
    int? limit,
    int? offset,
  }) async {
    _getCounts();
    _transactionListItems.clear();
    if (!mounted) return;

    if (query.isNotEmpty) {
      // debugPrint('Queryyyyyyyyyy $query');
      List results = await databaseHelper.querySearch(
        'transactions',
        query,
        // limit: limit,
        // offset: offset,
        orderBy: 'timeStamp DESC',
      );
      // debugPrint(results.length.toString());
      //   .then(
      // (value) {
      setState(() => _transactionList = results);
      _pagingController.itemList =
          _transactionList.map((item) => [item]).toList();
      //   },
      // );
    } else {
      // debugPrint('Dayyyyyyyyyy');
      await databaseHelper
          .queryDay(
        'transactions',
        getNormalDate(selectedDate),
        limit: limit,
        offset: offset,
        orderBy: 'timeStamp DESC',
      )
          .then(
        (value) {
          setState(
            () => _transactionList = value,
          );
        },
      );
    }
  }

  Future<void> _getCounts() async {
    _successfulConfirmedCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.doneConfirmed}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _successfulPendingCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.done}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _failedCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.error}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _secondAttemptCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.secondAttempt}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _blacklistedCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE date = '${getNormalDate(selectedDate)}' AND ussdReply LIKE '%blacklisted%'",
    );
    _forwardedCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.forwarded}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _unavailableOfferCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.unavailableOffer}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _pausedCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.paused}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _okoaCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE status = '${TransactionStatuses.hasOkoa}' AND date = '${getNormalDate(selectedDate)}'",
    );
    _advancedCount = await databaseHelper.getCount(
      'transactions',
      appendQuery:
          "WHERE (status = '${TransactionStatuses.advancedUssd}' OR status = '${TransactionStatuses.advancedQueue}')  AND date = '${getNormalDate(DateTime.now())}'",
    );

    setState(() {});
  }

  Future<void> _fetchPage(int pageKey) async {
    try {
      await reloadForNewDate(offset: pageKey, limit: _pageSize);

      final List<List<dynamic>> newItems =
          _transactionList.map((item) => [item]).toList();

      final isLastPage = newItems.length < _pageSize;
      if (isLastPage) {
        // debugPrint('Last page. Page key: $pageKey, page size: $_pageSize');
        _pagingController.appendLastPage(newItems);
      } else {
        final nextPageKey = pageKey + newItems.length;
        _pagingController.appendPage(newItems, nextPageKey);
      }
    } catch (error) {
      _pagingController.error = error;
    }
  }

  @override
  void initState() {
    super.initState();
    // reloadForNewDate();
    query = widget.query ?? "";
    _getCounts();

    _pagingController.addPageRequestListener((pageKey) {
      // debugPrint('Page request listener called');
      _fetchPage(pageKey);
    });

    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _pagingController.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;

    // reloadForNewDate();
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
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kPagePadding * 2),
            Container(
              padding: const EdgeInsets.only(
                right: kPagePadding,
                top: kPagePadding,
                bottom: kPagePadding / 2,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(kBorderRadius),
                  bottomRight: Radius.circular(kBorderRadius),
                ),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _selectionMode
                        ? () {
                            _selectionMode = false;
                            _selectedTransactionIds.clear();
                            setState(() {});
                          }
                        : () => Navigator.of(context).pop(),
                    icon: (!widget.isDashboard || _selectionMode)
                        ? const Icon(
                            CupertinoIcons.back,
                            size: 14,
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(width: kPagePadding / 2),
                  Text(
                    _selectionMode
                        ? '${_selectedTransactionIds.length} selected'
                        : 'History',
                    style: textTheme.titleLarge,
                  ),
                  const Spacer(),
                  if (_selectionMode)
                    Row(
                      children: [
                        // retry all selected transactions
                        IconButton(
                          icon: const Icon(CupertinoIcons.refresh),
                          onPressed: () {
                            showConfirmDeleteDialog(
                              context,
                              title: 'Retry Transactions',
                              message: 'Are you sure you want to retry these '
                                  '${_selectedTransactionIds.length} transactions?',
                            ).then((value) async {
                              if (value == true) {
                                showLoadingDialog(context);
                                await TransactionController()
                                    .retryTransactionsGivenIds(
                                  _selectedTransactionIds.toList(),
                                );
                                setState(() {
                                  _selectionMode = false;
                                  _selectedTransactionIds.clear();
                                });
                                reloadForNewDate();
                                Navigator.of(context).pop();
                              }
                            });
                          },
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.delete),
                          onPressed: () {
                            showConfirmDeleteDialog(
                              context,
                              message: 'Are you sure you want to delete these '
                                  '${_selectedTransactionIds.length} transactions?',
                            ).then((value) async {
                              if (value == true) {
                                showLoadingDialog(context);
                                await databaseHelper.deleteWhere(
                                  'transactions',
                                  'id IN (${_selectedTransactionIds.join(',')})',
                                  [],
                                );
                                setState(() {
                                  _selectionMode = false;
                                  _selectedTransactionIds.clear();
                                });
                                reloadForNewDate();
                                Navigator.of(context).pop();
                              }
                            });
                          },
                        ),
                        IconButton(
                          onPressed: () async {
                            // add all
                            // showLoadingDialog(context);
                            // Navigator.pop(context);
                            await showConfirmDeleteDialog(context,
                                    title:
                                        'Schedule transactions for tomorrow midnight',
                                    message:
                                        'All ${_selectedTransactionIds.length} transactions will be added to automated.',
                                    btnText: 'Add')
                                .then((value) async {
                              if (value == true) {
                                showLoadingDialog(context);

                                await TransactionController().addAllToAutomated(
                                  _selectedTransactionIds.toList(),
                                );

                                setState(() {
                                  // _selectionMode = false;
                                  // _selectedTransactionIds.clear();
                                });
                                reloadForNewDate();
                                Navigator.of(context).pop();
                              } else {
                                // Navigator.of(context).pop();
                              }
                            });
                          },
                          icon: Icon(Icons.precision_manufacturing_outlined),
                        ),
                        IconButton(
                          icon: Icon(
                            _selectedTransactionIds.length ==
                                    _transactionList.length
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                          ),
                          onPressed: () {
                            setState(() {
                              if (_selectedTransactionIds.length ==
                                  _transactionList.length) {
                                _selectedTransactionIds.clear();
                              } else {
                                debugPrint(
                                  'Selecting all transactions: ${_transactionList.length} \n ',
                                );
                                _selectedTransactionIds = _transactionList
                                    .map((item) {
                                      final rawId = item['id'];
                                      final id = rawId is int
                                          ? rawId
                                          : int.tryParse(rawId.toString()) ??
                                              -1;
                                      if (id is int) return id;
                                      if (id is String)
                                        return int.tryParse(id.toString()) ??
                                            -1;
                                      return -1;
                                    })
                                    .where((id) => id != -1)
                                    .toSet();

                                setState(() {});
                              }
                            });
                          },
                        ),
                      ],
                    )
                  else
                    GestureDetector(
                      onTap: () async {
                        await _selectDate(context);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(kPagePadding / 8),
                        decoration: BoxDecoration(
                          color: kPrimaryColorLight,
                          borderRadius: BorderRadius.circular(kBorderRadius),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              CupertinoIcons.calendar,
                              color: kPrimaryColor,
                              size: 14,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            Text(
                              date,
                              style: textTheme.labelSmall,
                            ),
                            const SizedBox(width: kPagePadding / 4),
                            const Icon(
                              // CupertinoIcons.calendar_today,
                              CupertinoIcons.chevron_compact_down,
                              color: kPrimaryColor,
                              size: 14,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!_isScrollingDown)
              Padding(
                padding: const EdgeInsets.all(kPagePadding),
                child: TextField(
                  decoration: InputDecoration(
                    focusColor: kPrimaryColor,
                    fillColor: kLightColor,
                    hintText: 'Search messages, numbers, ...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kBorderRadius / 1.5),
                    ),
                    suffixIcon: IconButton(
                      icon: const Icon(
                        CupertinoIcons.xmark_square_fill,
                      ),
                      onPressed: () {
                        _searchBarController.text = '';
                      },
                    ),
                  ),
                  controller: _searchBarController,
                  onChanged: (String value) {
                    setState(() {
                      query = value;
                    });
                    reloadForNewDate();
                  },
                ),
              ),
            if (!_isScrollingDown)
              Padding(
                padding: const EdgeInsets.only(
                  left: kPagePadding,
                  right: kPagePadding,
                  top: kPagePadding / 2,
                ),
                child: Container(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.center,
                    runAlignment: WrapAlignment.center,
                    runSpacing: kPagePadding / 2,
                    children: [
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.doneConfirmed;
                          });
                          reloadForNewDate();
                        },
                        const Icon(CupertinoIcons.checkmark_seal_fill,
                            color: kPrimaryColor, size: 14),
                        _successfulConfirmedCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kPrimaryColor,
                        otherText: query == TransactionStatuses.doneConfirmed
                            ? 'Successful(Confirmed)'
                            : '',
                            borderColor: kPrimaryColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = 'advanced';
                          });
                          reloadForNewDate();
                        },
                        const Icon(CupertinoIcons.phone,
                            color: kPrimaryColor, size: 14),
                        _advancedCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kPrimaryColor,
                        otherText: query == 'advanced' ? 'Advanced' : '',
                        borderColor: kPrimaryColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.done;
                          });
                          reloadForNewDate();
                        },
                        const Icon(CupertinoIcons.checkmark,
                            color: kWarningColor, size: 14),
                        _successfulPendingCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kPrimaryColor,
                        otherText: query == TransactionStatuses.done
                            ? 'Successful(Pending)'
                            : '',
                        borderColor: kWarningColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.forwarded;
                          });
                          reloadForNewDate();
                        },
                        Icon(
                          Icons.fork_right,
                          color: kPrimaryColor,
                          size: 14,
                        ),
                        _forwardedCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kPrimaryColor,
                        otherText: query == TransactionStatuses.forwarded
                            ? 'Forwarded'
                            : '',
                        borderColor: kPrimaryColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.hasOkoa;
                          });
                          reloadForNewDate();
                        },
                        Icon(Icons.sailing_rounded,
                            color: Theme.of(context).indicatorColor, size: 14),
                        _okoaCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: Theme.of(context).indicatorColor,
                        otherText:
                            query == TransactionStatuses.hasOkoa ? 'Okoa' : '',
                        borderColor: Theme.of(context).indicatorColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.unavailableOffer;
                          });
                          reloadForNewDate();
                        },
                        Icon(CupertinoIcons.exclamationmark_triangle,
                            color: Theme.of(context).indicatorColor, size: 14),
                        _unavailableOfferCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: Theme.of(context).indicatorColor,
                        otherText: query == TransactionStatuses.unavailableOffer
                            ? 'Unavailable Offer'
                            : '',
                        borderColor: Theme.of(context).indicatorColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.secondAttempt;
                          });
                          reloadForNewDate();
                        },
                        const Icon(CupertinoIcons.arrow_2_circlepath,
                            color: kWarningColor, size: 14),
                        _secondAttemptCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kWarningColor,
                        otherText: query == TransactionStatuses.secondAttempt
                            ? 'Second Attempt'
                            : '',
                        borderColor: kWarningColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.paused;
                          });
                          reloadForNewDate();
                        },
                        const Icon(CupertinoIcons.pause_circle,
                            color: kWarningColor, size: 14),
                        _pausedCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kWarningColor,
                        otherText:
                            query == TransactionStatuses.paused ? 'Paused' : '',
                        borderColor: kWarningColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.blacklisted;
                          });
                          reloadForNewDate();
                        },
                        const Icon(Icons.person_off_outlined,
                            color: kErrorColor, size: 14),
                        _blacklistedCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kErrorColor,
                        otherText: query == TransactionStatuses.blacklisted
                            ? 'Blacklisted'
                            : '',
                        borderColor: kErrorColor,
                      ),
                      const SizedBox(width: 8),
                      toolButton(
                        () {
                          setState(() {
                            query = TransactionStatuses.error;
                          });
                          reloadForNewDate();
                        },
                        const Icon(CupertinoIcons.xmark,
                            color: kErrorColor, size: 14),
                        _failedCount.toString(),
                        context,
                        withBorder: true,
                        accentColor: kErrorColor,
                        otherText:
                            query == TransactionStatuses.error ? 'Error' : '',
                            
                        borderColor: kErrorColor,
                      ),
                    ],
                  ),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Padding(
                  padding: const EdgeInsets.only(
                    left: kPagePadding,
                    right: kPagePadding,
                    top: kPagePadding / 2,
                  ),
                  child: InkWell(
                    onTap: () async {
                      showRetrySheet(
                        context,
                        _successfulConfirmedCount,
                        _successfulPendingCount,
                        _failedCount,
                        _secondAttemptCount,
                        _blacklistedCount,
                        _unavailableOfferCount,
                        _pausedCount,
                        _advancedCount,
                        _okoaCount,
                        _transactionList.length,
                      );
                    },
                    child: const Text(
                      'Retry options',
                      style: TextStyle(
                        color: kPrimaryColor,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(
                    left: kPagePadding,
                    right: kPagePadding,
                    top: kPagePadding / 2,
                  ),
                  child: InkWell(
                    onTap: () async {
                      _showDeleteSheet(
                        context,
                        _successfulConfirmedCount,
                        _successfulPendingCount,
                        _failedCount,
                        _secondAttemptCount,
                        _blacklistedCount,
                        _unavailableOfferCount,
                        _pausedCount,
                        _advancedCount,
                        _okoaCount,
                        _transactionList.length,
                      );
                    },
                    child: const Text(
                      'Delete options',
                      style: TextStyle(
                        color: kErrorColor,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            Expanded(
              child: Padding(
                padding: kPagePaddingInsets,
                child: RawScrollbar(
                  controller: _scrollController,
                  child: LayoutBuilder(
                    builder: (context, constraints) =>
                        PagedListView<int, List<dynamic>>.separated(
                      pagingController: _pagingController,
                      scrollController: _scrollController,
                      shrinkWrap: true,
                      builderDelegate: PagedChildBuilderDelegate<List<dynamic>>(
                        itemBuilder: (context, item, index) {
                          var transaction = item[0];
                          final id = transaction['id'] as int;
                          final isSelected =
                              _selectedTransactionIds.contains(id);

                          // Client? client = Client.fromTransaction(transaction);

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
                                    if (_selectedTransactionIds.isEmpty)
                                      _selectionMode = false;
                                  } else {
                                    _selectedTransactionIds.add(id);
                                  }
                                });
                              } else {
                                // Normal tap action here
                              }
                            },
                            child: Container(
                              color: isSelected
                                  ? Colors.blue.withOpacity(0.2)
                                  : null,
                              child: Row(
                                children: [
                                  if (_selectionMode)
                                    Checkbox(
                                      value: isSelected,
                                      onChanged: (checked) {
                                        setState(() {
                                          if (checked == true) {
                                            _selectedTransactionIds.add(id);
                                          } else {
                                            _selectedTransactionIds.remove(id);
                                            if (_selectedTransactionIds.isEmpty)
                                              _selectionMode = false;
                                          }
                                        });
                                      },
                                    ),
                                  Expanded(
                                    child: transactionListItem(
                                      context,
                                      transaction['number'],
                                      transaction['amount'],
                                      transaction['status'],
                                      transaction['ussdReply'],
                                      transaction['date'],
                                      transaction['time'],
                                      transaction['id'],
                                      transaction['ussdDialed'],
                                      transaction['source'],
                                      transaction['simSubId'],
                                      transaction['canRetry'] ?? 0,
                                      selectionMode: _selectionMode,
                                      transaction["ussdReply"],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                      separatorBuilder: (_, index) => const SizedBox(
                        height: kPagePadding / 4,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            // const SizedBox(height: kPagePadding * 7),
          ],
        ),
      ),
    );
  }

  Future<dynamic> showRetrySheet(
    BuildContext context,
    int successfulCount,
    int succPendingCount,
    int errorCount,
    int secondAttemptCount,
    int blacklistedCount,
    int unavailableOfferCount,
    int pausedCount,
    int advancedCount,
    int okoaCount,
    int allCount,
  ) {
    bool retryAll = false;
    bool retryErrors = true;
    bool retryFailed = false;
    bool retrySuccessful = false;
    bool retrySuccPending = false;
    bool retryPaused = false;
    bool retryOkoa = false;
    bool retryAdvanced = false;

    DateTime startDate =
        DateTime.fromMillisecondsSinceEpoch(getTodayMidnightMillis());
    DateTime endDate = DateTime.now();

    return showModalBottomSheet(
        context: context,
        showDragHandle: true,
        builder: (BuildContext context) {
          return StatefulBuilder(
              builder: (BuildContext context, StateSetter setState) {
            return Padding(
              padding: kPagePaddingInsets,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Retry'),
                    const SizedBox(height: kPagePadding),
                    CheckboxListTile(
                      value: retryAll,
                      onChanged: (bool? value) {
                        setState(() {
                          retryAll = value!;
                          retryFailed = value;
                          retryErrors = value;
                          retrySuccessful = value;
                          retryPaused = value;
                          retryOkoa = value;
                          retryAdvanced = value;
                          retrySuccPending = value;
                        });
                      },
                      title: Text(
                          'All (${errorCount + successfulCount + secondAttemptCount + pausedCount + advancedCount + okoaCount})'),
                    ),
                    CheckboxListTile(
                      value: retryErrors,
                      onChanged: (bool? value) {
                        setState(() {
                          retryErrors = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Errors ($errorCount)'),
                    ),
                    CheckboxListTile(
                      value: retryFailed,
                      onChanged: (bool? value) {
                        setState(() {
                          retryFailed = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Failed ($secondAttemptCount)'),
                    ),
                    CheckboxListTile(
                      value: retrySuccessful,
                      onChanged: (bool? value) {
                        setState(() {
                          retrySuccessful = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Successful ($successfulCount)'),
                    ),
                    CheckboxListTile(
                      value: retrySuccPending,
                      onChanged: (bool? value) {
                        setState(() {
                          retrySuccPending = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Successful(Pending) ($succPendingCount)'),
                    ),
                    CheckboxListTile(
                      value: retryPaused,
                      onChanged: (bool? value) {
                        setState(() {
                          retryPaused = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Paused ($pausedCount)'),
                    ),
                    CheckboxListTile(
                      value: retryOkoa,
                      onChanged: (bool? value) {
                        setState(() {
                          retryOkoa = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Okoa ($okoaCount)'),
                    ),
                    CheckboxListTile(
                      value: retryAdvanced,
                      onChanged: (bool? value) {
                        setState(() {
                          retryAdvanced = value!;
                          if (!value) {
                            retryAll = false;
                          }
                        });
                      },
                      title: Text('Advanced ($advancedCount)'),
                    ),
                    const SizedBox(height: kPagePadding),
                    const Text('From:'),
                    const SizedBox(height: kPagePadding / 2),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await showDatePicker(
                              context: context,
                              initialDate: startDate,
                              firstDate: DateTime(2015, 8),
                              lastDate: DateTime(2101),
                            ).then((value) {
                              setState(() {
                                startDate = value!;
                              });
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(kPagePadding / 8),
                            decoration: BoxDecoration(
                              color: kPrimaryColorLight,
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  getNormalDate(startDate),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  CupertinoIcons.chevron_compact_down,
                                  color: kPrimaryColor,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: kPagePadding),
                        GestureDetector(
                          onTap: () async {
                            await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(startDate),
                            ).then((value) {
                              setState(() {
                                startDate = DateTime(
                                  startDate.year,
                                  startDate.month,
                                  startDate.day,
                                  value!.hour,
                                  value.minute,
                                );
                              });
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(kPagePadding / 8),
                            decoration: BoxDecoration(
                              color: kPrimaryColorLight,
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  getRoughTime(startDate),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  CupertinoIcons.chevron_compact_down,
                                  color: kPrimaryColor,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: kPagePadding),
                    const Text('To:'),
                    const SizedBox(height: kPagePadding / 2),
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () async {
                            await showDatePicker(
                              context: context,
                              initialDate: endDate,
                              firstDate: DateTime(2015, 8),
                              lastDate: DateTime(2101),
                            ).then((value) {
                              setState(() {
                                endDate = value!;
                              });
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(kPagePadding / 8),
                            decoration: BoxDecoration(
                              color: kPrimaryColorLight,
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  getNormalDate(endDate),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  CupertinoIcons.chevron_compact_down,
                                  color: kPrimaryColor,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: kPagePadding),
                        GestureDetector(
                          onTap: () async {
                            await showTimePicker(
                              context: context,
                              initialTime: TimeOfDay.fromDateTime(endDate),
                            ).then((value) {
                              setState(() {
                                endDate = DateTime(
                                  endDate.year,
                                  endDate.month,
                                  endDate.day,
                                  value!.hour,
                                  value.minute,
                                );
                              });
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.all(kPagePadding / 8),
                            decoration: BoxDecoration(
                              color: kPrimaryColorLight,
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  getRoughTime(endDate),
                                  style: Theme.of(context).textTheme.labelSmall,
                                ),
                                const SizedBox(width: 3),
                                const Icon(
                                  CupertinoIcons.chevron_compact_down,
                                  color: kPrimaryColor,
                                  size: 14,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: kPagePadding),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Cancel'),
                          ),
                        ),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              tillDoneDialogue(
                                context,
                                const Padding(
                                  padding: kPagePaddingInsets,
                                  child: Text("Redialing"),
                                ),
                                () async {
                                  await TransactionController().retrySpecific(
                                    retryErrors,
                                    retrySuccessful,
                                    retrySuccPending,
                                    retryFailed,
                                    retryPaused,
                                    retryOkoa,
                                    retryAdvanced,
                                    startDate.millisecondsSinceEpoch,
                                    endDate.millisecondsSinceEpoch,
                                  );
                                },
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Retry'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          });
        });
  }

  Future<dynamic> _showDeleteSheet(
    BuildContext context,
    int successfulCount,
    int successfulPendingCount,
    int failedCount,
    int secondAttemptCount,
    int blacklistedCount,
    int unavailableOfferCount,
    int pausedCount,
    int advancedCount,
    int okoaCount,
    int allCount,
  ) {
    bool deleteAll = false;
    bool deleteErrors = false;
    bool deleteFailed = false;
    bool deleteSuccessful = false;
    bool deleteSuccessfulPending = false;
    bool deleteUnavailable = false;
    bool deleteBlacklist = false;
    bool deletePaused = false;
    bool deleteOkoa = false;
    bool deleteAdvanced = false;

    DateTime startDate =
        DateTime.fromMillisecondsSinceEpoch(getTodayMidnightMillis());
    DateTime endDate = DateTime.now();

    return showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setState) {
            return Padding(
              padding: kPagePaddingInsets,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete Tasks',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: kPagePadding),

                    // Select all checkbox
                    // CheckboxListTile(
                    //   value: deleteAll,
                    //   onChanged: (bool? value) {
                    //     setState(() {
                    //       deleteAll = value!;
                    //       deleteFailed = value;
                    //       deleteErrors = value;
                    //       deleteSuccessful = value;
                    //       deleteUnavailable = value;
                    //       deleteBlacklist = value;
                    //       deletePaused = value;
                    //     });
                    //   },
                    //   title: Text('All ($_allCount)'),
                    // ),

                    // Error checkbox
                    CheckboxListTile(
                      value: deleteErrors,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteErrors = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Errors ($failedCount)'),
                    ),

                    // Failed checkbox
                    CheckboxListTile(
                      value: deleteFailed,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteFailed = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Failed ($secondAttemptCount)'),
                    ),

                    // Successful checkbox
                    CheckboxListTile(
                      value: deleteSuccessful,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteSuccessful = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Successful ($successfulCount)'),
                    ),

                    CheckboxListTile(
                      value: deleteSuccessfulPending,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteSuccessfulPending = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title:
                          Text('Successful Pending ($successfulPendingCount)'),
                    ),

                    // Unavailable checkbox
                    CheckboxListTile(
                      value: deleteUnavailable,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteUnavailable = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title:
                          Text('Unavailable Offers ($unavailableOfferCount)'),
                    ),

                    // Blacklist checkbox
                    CheckboxListTile(
                      value: deleteBlacklist,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteBlacklist = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Blacklisted ($blacklistedCount)'),
                    ),

                    // Paused checkbox
                    CheckboxListTile(
                      value: deletePaused,
                      onChanged: (bool? value) {
                        setState(() {
                          deletePaused = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Paused ($pausedCount)'),
                    ),

                    // Okoa checkbox
                    CheckboxListTile(
                      value: deleteOkoa,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteOkoa = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Okoa ($okoaCount)'),
                    ),

                    CheckboxListTile(
                      value: deleteAdvanced,
                      onChanged: (bool? value) {
                        setState(() {
                          deleteAdvanced = value!;
                          if (!value) deleteAll = false;
                        });
                      },
                      title: Text('Advancekd ($advancedCount)'),
                    ),

                    const SizedBox(height: kPagePadding),

                    // Date selection
                    Text('From:',
                        style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: kPagePadding / 2),
                    _buildDateTimeSelector(context, startDate, (newDate) {
                      setState(() {
                        startDate = newDate;
                      });
                    }),

                    const SizedBox(height: kPagePadding),
                    Text('To:', style: Theme.of(context).textTheme.bodyMedium),
                    const SizedBox(height: kPagePadding / 2),
                    _buildDateTimeSelector(context, endDate, (newDate) {
                      setState(() {
                        endDate = newDate;
                      });
                    }),

                    const SizedBox(height: kPagePadding),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              Navigator.of(context).pop();
                            },
                            child: const Text('Cancel'),
                          ),
                        ),
                        const SizedBox(width: kPagePadding),
                        Expanded(
                          child: ElevatedButton(
                            child: const Text('Delete'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kErrorColor,
                            ),
                            onPressed: () async {
                              int numberOfItems = 0;

// 1. Use a Set instead of a List to prevent duplicate statuses
// (e.g. if both Successful and SuccessfulPending map to 'done')
                              final Set<String> selectedStatuses = {};

                              if (deleteErrors) {
                                selectedStatuses.add(TransactionStatuses.error);
                                numberOfItems += failedCount;
                              }
                              if (deleteSuccessful) {
                                selectedStatuses.add(TransactionStatuses.done);
                                numberOfItems += successfulCount;
                              }
                              if (deleteFailed) {
                                selectedStatuses
                                    .add(TransactionStatuses.secondAttempt);
                                numberOfItems += secondAttemptCount;
                              }
                              if (deleteSuccessfulPending) {
                                selectedStatuses.add(TransactionStatuses
                                    .done); // Matches deleteSuccessful
                                numberOfItems += successfulPendingCount;
                              }
                              if (deleteUnavailable) {
                                selectedStatuses
                                    .add(TransactionStatuses.unavailableOffer);
                                numberOfItems += unavailableOfferCount;
                              }
                              if (deleteBlacklist) {
                                selectedStatuses
                                    .add(TransactionStatuses.blacklisted);
                                numberOfItems += blacklistedCount;
                              }
                              if (deletePaused) {
                                selectedStatuses
                                    .add(TransactionStatuses.paused);
                                numberOfItems += pausedCount;
                              }
                              if (deleteOkoa) {
                                selectedStatuses
                                    .add(TransactionStatuses.hasOkoa);
                                numberOfItems += okoaCount;
                              }
                              if (deleteAdvanced) {
                                selectedStatuses
                                    .add(TransactionStatuses.advancedUssd);
                                selectedStatuses
                                    .add(TransactionStatuses.advancedQueue);
                                numberOfItems += advancedCount;
                              }

// 2. CRITICAL FIX: Prevent accidental deletion of ALL items if nothing is selected
                              if (selectedStatuses.isEmpty) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                      content: Text(
                                          'Please select at least one status to delete.')),
                                );
                                return;
                              }

                              bool delete = await confirmationDialog(
                                context,
                                'Delete $numberOfItems items?',
                              );

                              if (!delete) return;

// Build parameterized WHERE clause pieces and args
                              final List<String> whereParts = [];
                              final List<dynamic> whereArgs = [];

                              whereParts.add('timeStamp >= ?');
                              whereArgs.add(startDate.millisecondsSinceEpoch);
                              whereParts.add('timeStamp <= ?');
                              whereArgs.add(endDate.millisecondsSinceEpoch);

// 3. SQL OPTIMIZATION: Use the IN clause instead of multiple ORs
                              final String placeholders =
                                  List.filled(selectedStatuses.length, '?')
                                      .join(', ');
                              whereParts.add('status IN ($placeholders)');
                              whereArgs.addAll(selectedStatuses);

                              final String whereClause =
                                  whereParts.join(' AND ');


                              showLoadingDialog(context,
                                  text: 'Deleting $numberOfItems items');

// 4. ERROR HANDLING: Ensure the loading dialog closes even if DB fails
                              try {
                                await databaseHelper.deleteWhere(
                                    'transactions', whereClause, whereArgs);
                              } catch (e) {
                                // Optionally show an error SnackBar here
                              } finally {
                                // This guarantees the loading dialog is dismissed
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Helper widget for date and time selection
  Widget _buildDateTimeSelector(
      BuildContext context, DateTime date, Function(DateTime) onDateChanged) {
    return Row(
      children: [
        GestureDetector(
          onTap: () async {
            DateTime? picked = await showDatePicker(
              context: context,
              initialDate: date,
              firstDate: DateTime(2015, 8),
              lastDate: DateTime(2101),
            );
            if (picked != null) onDateChanged(picked);
          },
          child: _dateTimeBox(getNormalDate(date)),
        ),
        const SizedBox(width: kPagePadding),
        GestureDetector(
          onTap: () async {
            TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: TimeOfDay.fromDateTime(date),
            );
            if (picked != null) {
              onDateChanged(DateTime(
                  date.year, date.month, date.day, picked.hour, picked.minute));
            }
          },
          child: _dateTimeBox(getRoughTime(date)),
        ),
      ],
    );
  }

  Widget _dateTimeBox(String text) {
    return Container(
      padding: const EdgeInsets.all(kPagePadding / 8),
      decoration: BoxDecoration(
        color: kPrimaryColorLight,
        borderRadius: BorderRadius.circular(kBorderRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 3),
          const Icon(CupertinoIcons.chevron_compact_down,
              color: kPrimaryColor, size: 14),
        ],
      ),
    );
  }
}
