import 'dart:async';
import 'package:bsat/components/dialogs/confirm_delete_dialog.dart';
import 'package:bsat/components/dialogs/forward_text.dart';
import 'package:bsat/components/transaction_list_item.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/screens/online_management/search_device.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/shared_preferences_service.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:infinite_scroll_pagination/infinite_scroll_pagination.dart';
import 'package:bsat/components/dialogs/change_category_dialog.dart';
import '../../components/dialogs/confirmation_dialog.dart';
import '../../components/dialogs/loading_dialog.dart';
import '../../components/tool_button.dart';
import '../../components/dialogs/till_done_dialogue.dart';
import '../../utils/constants.dart';

enum _SelectionMenuAction {
  retry,
  delete,
  schedule,
  changeCategory,
  range,
  toggleSelectAll,
  forwardAllOnline,
  forwardAllOffline,
}

class TransactionHistoryPage extends StatefulWidget {
  final String? query;
  final bool isDashboard;

  const TransactionHistoryPage(
      {super.key, this.query, this.isDashboard = false});

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  static const int _pageSize = 12;
  String date = getNormalDate(DateTime.now());

  Set<int> _selectedTransactionIds = {};
  bool _selectionMode = false;
  bool _isRangeSelectMode = false;
  int? _lastSelectedVisibleIndex;

  // Performance Fix: Removed redundant _transactionList to save RAM
  int _successfulConfirmedCount = 0,
      _successfulPendingCount = 0,
      _failedCount = 0,
      _secondAttemptCount = 0,
      _blacklistedCount = 0,
      _forwardedCount = 0,
      _unavailableOfferCount = 0,
      _pausedCount = 0,
      _advancedCount = 0,
      _okoaCount = 0,
      _maskedCount = 0;

  final _pagingController = PagingController<int, dynamic>(firstPageKey: 0);
  final _searchBarController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  var selectedDate = DateTime.now();
  String query = "";
  Timer? _debounce; // Performance Fix: For search
  var databaseHelper = SQLiteService();
  final bool _isScrollingDown = false;

  @override
  void initState() {
    super.initState();
    query = widget.query ?? "";
    _searchBarController.text = query;
    _pagingController.addPageRequestListener((pageKey) => _fetchPage(pageKey));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _scrollController.dispose();
    _pagingController.dispose();
    _searchBarController.dispose();
    super.dispose();
  }

  // Performance Fix: Use Future.wait to run all 10 count queries in parallel
  // rather than one-after-another. This is much faster on low-end devices.
  Future<void> _getCounts() async {
    final dateStr = getNormalDate(selectedDate);
    final results = await Future.wait([
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.doneConfirmed}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.done}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.error}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.secondAttempt}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE date = '$dateStr' AND ussdReply LIKE '%blacklisted%'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.forwarded}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.unavailableOffer}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.paused}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.hasOkoa}' AND date = '$dateStr'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE (status = '${TransactionStatuses.advancedUssd}' OR status = '${TransactionStatuses.advancedQueue}') AND date = '${getNormalDate(DateTime.now())}'"),
      databaseHelper.getCount('transactions',
          appendQuery:
              "WHERE status = '${TransactionStatuses.masked}' AND date = '$dateStr'"),
    ]);

    if (!mounted) return;
    setState(() {
      _successfulConfirmedCount = results[0];
      _successfulPendingCount = results[1];
      _failedCount = results[2];
      _secondAttemptCount = results[3];
      _blacklistedCount = results[4];
      _forwardedCount = results[5];
      _unavailableOfferCount = results[6];
      _pausedCount = results[7];
      _okoaCount = results[8];
      _advancedCount = results[9];
      _maskedCount = results[10];
    });
  }

  Future<void> _fetchPage(int pageKey) async {
    try {
      List<dynamic> newItems;
      if (query.isNotEmpty) {
        newItems = await databaseHelper.querySearch('transactions', query,
            limit: _pageSize, offset: pageKey, orderBy: 'timeStamp DESC');
      } else {
        newItems = await databaseHelper.queryDay(
            'transactions', getNormalDate(selectedDate),
            limit: _pageSize, offset: pageKey, orderBy: 'timeStamp DESC');
      }

      if (pageKey == 0) _getCounts();

      final isLastPage = newItems.length < _pageSize;
      if (isLastPage) {
        _pagingController.appendLastPage(newItems);
      } else {
        final nextPageKey = pageKey + newItems.length;
        _pagingController.appendPage(newItems, nextPageKey);
      }
    } catch (error) {
      _pagingController.error = error;
    }
  }

  // Performance Fix: Use refresh() instead of manual list clearing
  void reloadForNewDate() {
    _resetSelectionState();
    _pagingController.refresh();
  }

  void _clearSelectionState() {
    _selectionMode = false;
    _isRangeSelectMode = false;
    _lastSelectedVisibleIndex = null;
    _selectedTransactionIds.clear();
  }

  void _resetSelectionState() {
    if (!mounted) return;
    setState(_clearSelectionState);
  }

  void _selectRangeByVisibleIndex(int currentIndex) {
    final anchor = _lastSelectedVisibleIndex;
    final items = _pagingController.itemList;
    if (anchor == null || items == null || items.isEmpty) return;

    final start = anchor < currentIndex ? anchor : currentIndex;
    final end = anchor > currentIndex ? anchor : currentIndex;

    for (int i = start; i <= end; i++) {
      if (i >= 0 && i < items.length) {
        _selectedTransactionIds.add(items[i]['id'] as int);
      }
    }

    _isRangeSelectMode = false;
    _lastSelectedVisibleIndex = currentIndex;
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
        context: context,
        initialDate: selectedDate,
        firstDate: DateTime(2015, 8),
        lastDate: DateTime(2101));
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        date = getNormalDate(selectedDate);
      });
      reloadForNewDate();
    }
  }

  @override
  Widget build(BuildContext context) {
    var textTheme = Theme.of(context).textTheme;
    return WillPopScope(
      onWillPop: () async {
        if (_selectionMode) {
          _resetSelectionState();
          return false;
        }
        return true;
      },
      child: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: kPagePadding * 2),
            // Header
            Container(
              padding: const EdgeInsets.only(
                  right: kPagePadding,
                  top: kPagePadding,
                  bottom: kPagePadding / 2),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(kBorderRadius),
                    bottomRight: Radius.circular(kBorderRadius)),
              ),
              child: Row(
                children: [
                  IconButton(
                      onPressed: _selectionMode
                          ? _resetSelectionState
                          : () => Navigator.of(context).pop(),
                      icon: (!widget.isDashboard || _selectionMode)
                          ? const Icon(CupertinoIcons.back, size: 14)
                          : const SizedBox.shrink()),
                  const SizedBox(width: kPagePadding / 2),
                  Text(
                      _selectionMode
                          ? (_isRangeSelectMode
                              ? 'Select range: tap another item'
                              : '${_selectedTransactionIds.length} selected')
                          : 'History',
                      style: textTheme.titleLarge),
                  const Spacer(),
                  if (_selectionMode)
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(CupertinoIcons.arrow_2_circlepath),
                          tooltip: 'Retry',
                          onPressed: _handleRetrySelected,
                        ),
                        IconButton(
                          icon: const Icon(CupertinoIcons.trash),
                          tooltip: 'Delete',
                          onPressed: _handleDeleteSelected,
                        ),
                        // select all
                        IconButton(
                          icon: const Icon(Icons.select_all),
                          tooltip: 'Select all visible',
                          onPressed: () {
                            setState(() {
                              final allVisibleSelected =
                                  _selectedTransactionIds.length ==
                                      (_pagingController.itemList?.length ?? 0);
                              if (allVisibleSelected) {
                                _clearSelectionState();
                              } else {
                                _selectedTransactionIds =
                                    (_pagingController.itemList ?? [])
                                        .map((e) => e['id'] as int)
                                        .toSet();
                                _selectionMode =
                                    _selectedTransactionIds.isNotEmpty;
                                _isRangeSelectMode = false;
                                _lastSelectedVisibleIndex =
                                    _selectedTransactionIds.isNotEmpty
                                        ? 0
                                        : null;
                              }
                            });
                          },
                        ),
                        _buildSelectionActions()
                      ],
                    )
                  else
                    _buildDateButton(textTheme),
                ],
              ),
            ),
            // Search Bar with Debounce
            Padding(
              padding: const EdgeInsets.all(kPagePadding),
              child: TextField(
                controller: _searchBarController,
                decoration: InputDecoration(
                  focusColor: kPrimaryColor,
                  fillColor: kLightColor,
                  hintText: 'Search messages, numbers, ...',
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kBorderRadius / 1.5)),
                  suffixIcon: IconButton(
                      icon: const Icon(CupertinoIcons.xmark_square_fill),
                      onPressed: () {
                        _searchBarController.clear();
                        setState(() => query = "");
                        reloadForNewDate();
                      }),
                ),
                onChanged: (value) {
                  if (_debounce?.isActive ?? false) _debounce!.cancel();
                  _debounce = Timer(const Duration(milliseconds: 500), () {
                    setState(() => query = value);
                    reloadForNewDate();
                  });
                },
              ),
            ),
            // Tool Buttons (Exact original UI)
            _buildToolButtons(),
            // Action Text Buttons
            _buildOptionLinks(),
            // The List (Optimized)
            Expanded(
              child: Padding(
                padding: kPagePaddingInsets,
                child: RawScrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  thickness: 10,
                  radius: const Radius.circular(12),
                  thumbColor: kPrimaryColor.withValues(alpha: 0.7),
                  trackVisibility: true,
                  child: PagedListView<int, dynamic>.separated(
                    pagingController: _pagingController,
                    scrollController: _scrollController,
                    separatorBuilder: (_, index) =>
                        const SizedBox(height: kPagePadding / 4),
                    builderDelegate: PagedChildBuilderDelegate<dynamic>(
                      itemBuilder: (context, transaction, index) {
                        final id = transaction['id'] as int;
                        final isSelected = _selectedTransactionIds.contains(id);
                        return RepaintBoundary(
                          // Performance Fix: Stops unnecessary UI repainting
                          child: GestureDetector(
                            onLongPress: () => setState(() {
                              _selectionMode = true;
                              _selectedTransactionIds.add(id);
                              _isRangeSelectMode = false;
                              _lastSelectedVisibleIndex = index;
                            }),
                            onTap: () {
                              if (_selectionMode) {
                                setState(() {
                                  if (_isRangeSelectMode) {
                                    _selectRangeByVisibleIndex(index);
                                  } else {
                                    isSelected
                                        ? _selectedTransactionIds.remove(id)
                                        : _selectedTransactionIds.add(id);
                                    _lastSelectedVisibleIndex = index;
                                  }
                                  if (_selectedTransactionIds.isEmpty) {
                                    _clearSelectionState();
                                  }
                                });
                              }
                            },
                            child: Container(
                              color: isSelected
                                  ? Colors.blue.withValues(alpha: 0.2)
                                  : null,
                              child: Row(
                                children: [
                                  if (_selectionMode)
                                    Checkbox(
                                        value: isSelected,
                                        onChanged: (checked) {
                                          setState(() {
                                            checked == true
                                                ? _selectedTransactionIds
                                                    .add(id)
                                                : _selectedTransactionIds
                                                    .remove(id);
                                            if (checked == true) {
                                              _lastSelectedVisibleIndex = index;
                                            }
                                            if (_selectedTransactionIds
                                                .isEmpty) {
                                              _clearSelectionState();
                                            }
                                          });
                                        }),
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
                                        transaction["ussdReply"]),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- Helper Methods to keep build() clean without losing original UI ---

  Widget _buildSelectionActions() {
    final allVisibleSelected = _selectedTransactionIds.length ==
        (_pagingController.itemList?.length ?? 0);

    return PopupMenuButton<_SelectionMenuAction>(
      icon: const Icon(Icons.menu),
      onSelected: (action) async {
        switch (action) {
          case _SelectionMenuAction.retry:
            await _handleRetrySelected();
            break;
          case _SelectionMenuAction.delete:
            await _handleDeleteSelected();
            break;
          case _SelectionMenuAction.schedule:
            await _handleScheduleSelected();
            break;
          case _SelectionMenuAction.changeCategory:
            await _handleChangeCategorySelected();
            break;
          case _SelectionMenuAction.forwardAllOnline:
            await _handleForwardAllOnlineSelected();
            break;
          case _SelectionMenuAction.forwardAllOffline:
            await _handleForwardAllOfflineSelected();
            break;
          case _SelectionMenuAction.range:
            setState(() {
              _isRangeSelectMode = true;
            });
            break;
          case _SelectionMenuAction.toggleSelectAll:
            setState(() {
              if (allVisibleSelected) {
                _clearSelectionState();
              } else {
                _selectedTransactionIds = (_pagingController.itemList ?? [])
                    .map((e) => e['id'] as int)
                    .toSet();
                _selectionMode = _selectedTransactionIds.isNotEmpty;
                _isRangeSelectMode = false;
                _lastSelectedVisibleIndex =
                    _selectedTransactionIds.isNotEmpty ? 0 : null;
              }
            });
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: _SelectionMenuAction.range,
          enabled: _selectedTransactionIds.isNotEmpty,
          child: const Text('Range'),
        ),
        const PopupMenuItem(
          value: _SelectionMenuAction.schedule,
          child: Text('Schedule selected'),
        ),
        const PopupMenuItem(
          value: _SelectionMenuAction.changeCategory,
          child: Text('Change category'),
        ),
        const PopupMenuItem(
          value: _SelectionMenuAction.forwardAllOnline,
          child: Text('Forward all online'),
        ),
        const PopupMenuItem(
          value: _SelectionMenuAction.forwardAllOffline,
          child: Text('Forward all offline'),
        ),
        PopupMenuItem(
          value: _SelectionMenuAction.toggleSelectAll,
          child: Text(allVisibleSelected
              ? 'Clear selected visible'
              : 'Select all visible'),
        ),
      ],
    );
  }

  Future<List<Map<String, dynamic>>> _getSelectedTransactions() async {
    final selectedIds = _selectedTransactionIds.toList()..sort();
    if (selectedIds.isEmpty) return [];

    final placeholders = List.filled(selectedIds.length, '?').join(', ');
    return databaseHelper.queryCustom(
      'transactions',
      'id IN ($placeholders)',
      selectedIds,
      orderBy: 'id ASC',
    );
  }

  int? _toInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse(value.toString());
  }

  // Future<int?> _resolveOfflineForwardNumber(int amount) async {
  //   final matches = await databaseHelper.queryCustom(
  //     'forwarded',
  //     '(amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)',
  //     [
  //       '[$amount,%',
  //       '%,$amount,%',
  //       '%,$amount]',
  //       '[$amount]',
  //     ],
  //     limit: 1,
  //   );
  //
  //   if (matches.isEmpty) return null;
  //   return _toInt(matches.first['numberToReceive']);
  // }

  Future<void> _handleForwardAllOfflineSelected() async {
    if (_selectedTransactionIds.isEmpty) return;

    final confirm = await confirmationDialog(
      context,
      'Forward ${_selectedTransactionIds.length} selected transaction(s) offline?',
    );
    if (confirm != true) return;

    showLoadingDialog(context, text: 'Forwarding offline...');

    int forwarded = 0;
    int skipped = 0;

    String? number = await showForwardTextDialog(context, 0);

    try {
      final transactions = await _getSelectedTransactions();

      for (final transaction in transactions) {
        final message = (transaction['initialMessage'] ?? '').toString().trim();
        if (message.isEmpty) {
          skipped++;
          continue;
        }

        final amount = _toInt(transaction['amount']) ?? 0;
        final recipientNumber = number;
        if (recipientNumber == null) {
          skipped++;
          continue;
        }

        final trimmedMessage = message.substring(
          0,
          message.length > 160 ? 160 : message.length,
        );

        await sendEvenInBackground('254$recipientNumber', trimmedMessage);

        await TransactionController().dontProcess(
          message,
          (transaction['transactionId'] ?? '').toString(),
          _toInt(transaction['number']) ?? 0,
          (transaction['ussdDialed'] ?? '').toString(),
          amount,
          _toInt(transaction['simSubId']) ?? 0,
          status: TransactionStatuses.forwarded,
          source: (transaction['source'] ?? 'bingwa').toString(),
          canRetry: (transaction['canRetry'] ?? 0) == 1,
          id: _toInt(transaction['id']),
          reply: 'Forwarded to $recipientNumber',
        );

        forwarded++;
      }
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    if (!mounted) return;
    _resetSelectionState();
    reloadForNewDate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Forwarded $forwarded transaction(s). Skipped $skipped.')),
    );
  }

  Future<void> _handleForwardAllOnlineSelected() async {
    if (_selectedTransactionIds.isEmpty) return;

    final device = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute(builder: (context) => const SearchDevicePage()),
    );
    if (device == null) return;

    final recipientDeviceName = (device['device_name'] ?? '').toString().trim();
    if (recipientDeviceName.isEmpty) return;

    final confirmed = await confirmationDialog(
      context,
      'Forward ${_selectedTransactionIds.length} selected transaction(s) to $recipientDeviceName?',
    );
    if (confirmed != true) return;

    final senderDeviceName =
        await SharedPreferencesService().getDeviceName() ?? 'Unknown Device';

    showLoadingDialog(context, text: 'Forwarding online...');

    int forwarded = 0;
    int failed = 0;

    try {
      final transactions = await _getSelectedTransactions();

      for (final transaction in transactions) {
        final message = (transaction['initialMessage'] ?? '').toString().trim();
        if (message.isEmpty) {
          failed++;
          continue;
        }

        try {
          int? txId = await TransactionController().dontProcess(
            message,
            (transaction['transactionId'] ?? '').toString(),
            _toInt(transaction['number']) ?? 0,
            (transaction['ussdDialed'] ?? '').toString(),
            _toInt(transaction['amount']) ?? 0,
            _toInt(transaction['simSubId']) ?? 0,
            status: TransactionStatuses.done,
            source: (transaction['source'] ?? 'bingwa').toString(),
            canRetry: (transaction['canRetry'] ?? 0) == 1,
            id: _toInt(transaction['id']),
            reply: 'Forwarded to $recipientDeviceName',
          );

          final result = await BackendService().post(
            '/api/fcm/send-secure',
            body: {
              'title': 'BSAT Online Forwarding',
              'body': message,
              'senderDeviceName': senderDeviceName,
              'recipientDeviceName': recipientDeviceName,
              'data': {
                'type': 'forwarded_sms',
                'body': message,
                'title': 'Forwarded Message',
                'transactionId': txId,
                'senderDeviceName': senderDeviceName,
              },
            },
          );

          if (result['success'] != true) {
            failed++;
            continue;
          }

          forwarded++;
        } catch (_) {
          failed++;
        }
      }
    } finally {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }

    if (!mounted) return;
    _resetSelectionState();
    reloadForNewDate();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content:
              Text('Forwarded $forwarded transaction(s). Failed $failed.')),
    );
  }

  Widget _buildDateButton(TextTheme textTheme) {
    return GestureDetector(
      onTap: () => _selectDate(context),
      child: Container(
        padding: const EdgeInsets.all(kPagePadding / 8),
        decoration: BoxDecoration(
            color: kPrimaryColorLight,
            borderRadius: BorderRadius.circular(kBorderRadius)),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.calendar, color: kPrimaryColor, size: 14),
            const SizedBox(width: kPagePadding / 4),
            Text(date, style: textTheme.labelSmall),
            const SizedBox(width: kPagePadding / 4),
            const Icon(CupertinoIcons.chevron_compact_down,
                color: kPrimaryColor, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildToolButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
      child: Wrap(
        alignment: WrapAlignment.center,
        runSpacing: kPagePadding / 2,
        children: [
          _tool(
              TransactionStatuses.doneConfirmed,
              const Icon(CupertinoIcons.checkmark_seal_fill,
                  color: kPrimaryColor, size: 14),
              _successfulConfirmedCount,
              kPrimaryColor,
              'Successful(Confirmed)'),
          const SizedBox(width: 8),
          _tool(
              'advanced',
              const Icon(CupertinoIcons.phone, color: kPrimaryColor, size: 14),
              _advancedCount,
              kPrimaryColor,
              'Advanced'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.done,
              const Icon(CupertinoIcons.checkmark,
                  color: kWarningColor, size: 14),
              _successfulPendingCount,
              kPrimaryColor,
              'Successful(Pending)',
              bColor: kWarningColor),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.forwarded,
              const Icon(Icons.fork_right, color: kPrimaryColor, size: 14),
              _forwardedCount,
              kPrimaryColor,
              'Forwarded'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.hasOkoa,
              Icon(Icons.sailing_rounded,
                  color: Theme.of(context).indicatorColor, size: 14),
              _okoaCount,
              Theme.of(context).indicatorColor,
              'Okoa'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.unavailableOffer,
              Icon(CupertinoIcons.exclamationmark_triangle,
                  color: Theme.of(context).indicatorColor, size: 14),
              _unavailableOfferCount,
              Theme.of(context).indicatorColor,
              'Unavailable Offer'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.secondAttempt,
              const Icon(CupertinoIcons.arrow_2_circlepath,
                  color: kWarningColor, size: 14),
              _secondAttemptCount,
              kWarningColor,
              'Second Attempt'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.paused,
              const Icon(CupertinoIcons.pause_circle,
                  color: kWarningColor, size: 14),
              _pausedCount,
              kWarningColor,
              'Paused'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.blacklisted,
              const Icon(Icons.person_off_outlined,
                  color: kErrorColor, size: 14),
              _blacklistedCount,
              kErrorColor,
              'Blacklisted'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.error,
              const Icon(CupertinoIcons.xmark, color: kErrorColor, size: 14),
              _failedCount,
              kErrorColor,
              'Error'),
          const SizedBox(width: 8),
          _tool(
              TransactionStatuses.masked,
              const Icon(Icons.masks, color: kErrorColor, size: 14),
              _maskedCount,
              kErrorColor,
              'Masked'),
        ],
      ),
    );
  }

  Widget _tool(String q, Icon icon, int count, Color accent, String label,
      {Color? bColor}) {
    return toolButton(() {
      setState(() => query = q);
      reloadForNewDate();
    }, icon, count.toString(), context,
        withBorder: true,
        accentColor: accent,
        otherText:
            (query == q) || (query == '' && count > 0) || (query == 'all')
                ? label
                : '',
        borderColor: bColor ?? accent);
  }

  Widget _buildOptionLinks() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Padding(
          padding: const EdgeInsets.all(kPagePadding / 2),
          child: TextButton(
            onPressed: () => showRetrySheet(
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
                0),
            child: const Text(
              'Retry options',
              style: TextStyle(color: kPrimaryColor),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(kPagePadding / 2),
          child: TextButton(
            onPressed: () => _showDeleteSheet(
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
                0),
            child: const Text(
              'Delete options',
              style: TextStyle(color: kErrorColor),
            ),
          ),
        ),
      ],
    );
  }

  // --- Actions ---

  Future<void> _handleRetrySelected() async {
    bool? val = await showConfirmDeleteDialog(context,
        title: 'Retry Transactions',
        message: 'Retry these ${_selectedTransactionIds.length} transactions?');
    if (val == true) {
      showLoadingDialog(context);
      await TransactionController()
          .retryTransactionsGivenIds(_selectedTransactionIds.toList());
      _resetSelectionState();
      reloadForNewDate();
      Navigator.pop(context);
    }
  }

  Future<void> _handleDeleteSelected() async {
    bool? val = await showConfirmDeleteDialog(context,
        message:
            'Delete these ${_selectedTransactionIds.length} transactions?');
    if (val == true) {
      showLoadingDialog(context);
      await databaseHelper.deleteWhere(
          'transactions', 'id IN (${_selectedTransactionIds.join(',')})', []);
      _resetSelectionState();
      reloadForNewDate();
      Navigator.pop(context);
    }
  }

  Future<void> _handleScheduleSelected() async {
    bool? val = await showConfirmDeleteDialog(context,
        title: 'Schedule',
        message: 'Add ${_selectedTransactionIds.length} to automated?',
        btnText: 'Add');
    if (val == true) {
      showLoadingDialog(context);
      await TransactionController()
          .addAllToAutomated(_selectedTransactionIds.toList());
      reloadForNewDate();
      Navigator.pop(context);
    }
  }

  Future<void> _handleChangeCategorySelected() async {
    final selectedStatus = await showChangeCategoryDialog(context);
    if (selectedStatus == null || selectedStatus.isEmpty) return;

    final selectedIds = _selectedTransactionIds.toList();
    if (selectedIds.isEmpty) return;

    await tillDoneDialogue(
      context,
      const Padding(
        padding: kPagePaddingInsets,
        child: Text('Updating category'),
      ),
      () async {
        final placeholders = List.filled(selectedIds.length, '?').join(', ');
        await databaseHelper.updateStuff(
          {'status': selectedStatus},
          'id IN ($placeholders)',
          selectedIds,
          'transactions',
        );
      },
    );

    if (!mounted) return;
    _resetSelectionState();
    reloadForNewDate();
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
                          child: _dateTimeBox(getNormalDate(startDate)),
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
                          child: _dateTimeBox(getRoughTime(startDate)),
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
                          child: _dateTimeBox(getNormalDate(endDate)),
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
                          child: _dateTimeBox(getRoughTime(endDate)),
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
                                print('Error deleting transactions: $e');
                                // Optionally show an error SnackBar here
                              } finally {
                                // This guarantees the loading dialog is dismissed
                                if (context.mounted) {
                                  Navigator.of(context).pop();

                                  // Close bottom sheet and update UI
                                  Navigator.of(context).pop();
                                  reloadForNewDate();
                                }
                              }
                            },
                            child: const Text('Delete'),
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
  // NOTE: Keep your showRetrySheet, _showDeleteSheet, and _buildDateTimeSelector methods exactly as they were here...
  // (I am omitting them for brevity, but they should remain unchanged in your final file)
}
