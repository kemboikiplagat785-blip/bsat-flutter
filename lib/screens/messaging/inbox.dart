import 'dart:async';

import 'package:another_telephony/telephony.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../components/dialogs/till_done_dialogue.dart';
import '../../utils/constants.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  final List<SmsMessage> _originalSmsList = [];
  final List<SmsMessage> _filteredSmsList = [];
  List<SmsMessage> _smsList = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMoreToReveal = false;
  final ScrollController _pageScrollController = ScrollController();

  final Set<int> _selectedIndices = {};
  int? _lastSelectedIndex;
  bool _isRangeSelectMode = false;

  String _searchQuery = '';
  String? _selectedSender;
  final Set<String> _selectedAmounts = {};
  final Set<String> _uniqueSenders = {};
  final Set<String> _uniqueAmounts = {};

  int _maxVisibleMessages = 500;
  int _visibleMessageCount = 0;
  int _filteredMessageCount = 0;
  bool _isMessageListTruncated = false;
  static const int _pageSize = 50;

  final TextEditingController _maxVisibleMessagesController =
  TextEditingController(text: '500');
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _pageScrollController.addListener(_handleScroll);
    _fetchSms();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _maxVisibleMessagesController.dispose();
    _pageScrollController.removeListener(_handleScroll);
    _pageScrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchSms() async {
    final limit = _maxVisibleMessages;
    try {
      if (mounted) {
        setState(() {
          _isLoading = true;
          _isLoadingMore = false;
        });
      }
      final messages = await getAllSms(limit: limit);
      if (!mounted) return;
      setState(() {
        _originalSmsList
          ..clear()
          ..addAll(messages);
        _extractUniqueSendersAndAmounts(messages);
        _applyFilters(resetPagination: true);
        _isLoading = false;
      });
      _scheduleAutoRevealMore();
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingMore = false;
        });
      }
    }
  }

  void _extractUniqueSendersAndAmounts(List<SmsMessage> messages) {
    _uniqueSenders.clear();
    _uniqueAmounts.clear();

    for (final msg in messages) {
      _uniqueSenders.add(msg.address ?? 'Unknown');
      final amount = _extractAmount(msg.body ?? '');
      if (amount.isNotEmpty) {
        _uniqueAmounts.add(amount);
      }
    }
  }

  String _extractAmount(String body) {
    final regex = RegExp(r'KSH[\s]?[\d,]+(?:\.\d{2})?');
    final match = regex.firstMatch(body.toUpperCase());
    return match?.group(0) ?? '';
  }

  double _amountSortValue(String amount) {
    final normalized = amount
        .toUpperCase()
        .replaceAll('KSH', '')
        .replaceAll(',', '')
        .trim();

    return double.tryParse(normalized) ?? double.infinity;
  }

  void _applyFilters({bool resetPagination = false}) {
    _filteredSmsList
      ..clear()
      ..addAll(_originalSmsList.where((msg) {
      if (_searchQuery.isNotEmpty) {
        final body = (msg.body ?? '').toLowerCase();
        final address = (msg.address ?? '').toLowerCase();
        final query = _searchQuery.toLowerCase();
        if (!body.contains(query) && !address.contains(query)) {
          return false;
        }
      }

      if (_selectedSender != null && _selectedSender!.isNotEmpty) {
        if ((msg.address ?? 'Unknown') != _selectedSender) {
          return false;
        }
      }

      if (_selectedAmounts.isNotEmpty) {
        final amount = _extractAmount(msg.body ?? '');
        if (amount.isEmpty || !_selectedAmounts.contains(amount)) {
          return false;
        }
      }

      return true;
    }));

    _filteredMessageCount = _filteredSmsList.length;

    if (resetPagination) {
      _visibleMessageCount = _filteredMessageCount < _pageSize
          ? _filteredMessageCount
          : _pageSize;
      _selectedIndices.clear();
      _lastSelectedIndex = null;
      _isRangeSelectMode = false;
    } else if (_visibleMessageCount > _filteredMessageCount) {
      _visibleMessageCount = _filteredMessageCount;
    }

    _smsList = _filteredSmsList.take(_visibleMessageCount).toList();
    _isMessageListTruncated = _filteredMessageCount > _visibleMessageCount;
    _hasMoreToReveal = _visibleMessageCount < _filteredMessageCount;

  }

  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) {
      _searchDebounce!.cancel();
    }
    _searchDebounce = Timer(const Duration(milliseconds: 400), () {
      if (!mounted) return;
      setState(() {
        _searchQuery = query;
        _applyFilters();
      });
    });
  }

  void _onMaxVisibleMessagesChanged(String value) {
    final parsed = int.tryParse(value.trim());
    if (parsed == null || parsed < 1) return;

    setState(() {
      _maxVisibleMessages = parsed;
    });

    unawaited(_fetchSms());
  }

  void _handleScroll() {
    if (!_pageScrollController.hasClients || _isLoading || _isLoadingMore) {
      return;
    }

    if (!_hasMoreToReveal) return;

    if (_pageScrollController.position.extentAfter < 240) {
      _loadMoreVisibleMessages();
    }
  }

  Future<void> _loadMoreVisibleMessages() async {
    if (_isLoading || _isLoadingMore || !_hasMoreToReveal) return;

    setState(() {
      _isLoadingMore = true;
    });

    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;

    setState(() {
      final nextCount = _visibleMessageCount + _pageSize;
      _visibleMessageCount = nextCount > _filteredMessageCount
          ? _filteredMessageCount
          : nextCount;
      _smsList = _filteredSmsList.take(_visibleMessageCount).toList();
      _isMessageListTruncated = _filteredMessageCount > _visibleMessageCount;
      _hasMoreToReveal = _visibleMessageCount < _filteredMessageCount;
      _isLoadingMore = false;
    });

    _scheduleAutoRevealMore();
  }

  void _scheduleAutoRevealMore() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageScrollController.hasClients) return;
      final position = _pageScrollController.position;
      if (_hasMoreToReveal && position.extentAfter < 240) {
        unawaited(_loadMoreVisibleMessages());
      }
    });
  }

  void _selectRange(int currentIndex) {
    if (_lastSelectedIndex == null) return;

    final start = _lastSelectedIndex! < currentIndex
        ? _lastSelectedIndex!
        : currentIndex;
    final end = _lastSelectedIndex! > currentIndex
        ? _lastSelectedIndex!
        : currentIndex;

    setState(() {
      for (int i = start; i <= end; i++) {
        if (i < _smsList.length) {
          _selectedIndices.add(i);
        }
      }
      _isRangeSelectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: RawScrollbar(
        controller: _pageScrollController,
        thumbColor: kPrimaryColor,
        thickness: 10,
        thumbVisibility: true,
        interactive: true,
        radius: const Radius.circular(12),
        trackVisibility: true,
        child: CustomScrollView(
          controller: _pageScrollController,
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context, textTheme)),
            if (_selectedIndices.isNotEmpty)
              SliverToBoxAdapter(
                child: Container(
                  color: Theme.of(context).cardColor,
                  padding: const EdgeInsets.symmetric(
                    horizontal: kPagePadding,
                    vertical: kPagePadding / 2,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _isRangeSelectMode
                            ? 'Select range: tap another item'
                            : '${_selectedIndices.length} selected',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Row(
                        children: [
                          if (!_isRangeSelectMode) ...[
                            TextButton(
                              onPressed: () {
                                setState(() {
                                  _isRangeSelectMode = true;
                                });
                              },
                              child: const Text(
                                'Range',
                                style: TextStyle(color: Colors.white),
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          IconButton(
                            tooltip: 'Retry selected',
                            onPressed:
                                _isRangeSelectMode ? null : _retrySelected,
                            icon: const Icon(Icons.refresh),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            tooltip: 'Copy numbers',
                            onPressed: _isRangeSelectMode
                                ? null
                                : _copySelectedNumbers,
                            icon: const Icon(Icons.copy),
                          ),
                          const SizedBox(width: 8),
                          TextButton(
                            onPressed: () {
                              setState(() {
                                _selectedIndices.clear();
                                _isRangeSelectMode = false;
                                _lastSelectedIndex = null;
                              });
                            },
                            child: const Text(
                              'Clear',
                              style: TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            if (_isLoading)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                ),
              )
            else if (_smsList.isEmpty)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: Text('No messages found')),
                ),
              )
            else ...[
              SliverPadding(
                padding: const EdgeInsets.only(top: kPagePadding),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = _smsList[index];
                      final isSelected = _selectedIndices.contains(index);

                      return _SmsTile(
                        item: item,
                        index: index,
                        isSelected: isSelected,
                        onTap: () {
                          if (_isRangeSelectMode) {
                            _selectRange(index);
                            _lastSelectedIndex = index;
                          } else if (_selectedIndices.isEmpty) {
                            _handleMessageTap(item);
                          } else {
                            setState(() {
                              if (isSelected) {
                                _selectedIndices.remove(index);
                              } else {
                                _selectedIndices.add(index);
                                _lastSelectedIndex = index;
                              }
                            });
                          }
                        },
                        onLongPress: () {
                          setState(() {
                            if (isSelected) {
                              _selectedIndices.remove(index);
                            } else {
                              _selectedIndices.add(index);
                              _lastSelectedIndex = index;
                            }
                          });
                        },
                      );
                    },
                    childCount: _smsList.length,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(
                    top: 12,
                    bottom: 32,
                  ),
                  child: Center(
                    child: _isLoadingMore
                        ? const SizedBox(
                            height: 28,
                            width: 28,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : _hasMoreToReveal
                            ? Text(
                                'Scroll to load more messages',
                                style: Theme.of(context).textTheme.bodySmall,
                              )
                            : Text(
                                'End of messages',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, TextTheme textTheme) {
    final sortedAmounts = _uniqueAmounts.toList()
      ..sort((a, b) => _amountSortValue(a).compareTo(_amountSortValue(b)));

    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(kBorderRadius),
          bottomRight: Radius.circular(kBorderRadius),
        ),
        color: Theme.of(context).cardColor,
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: kPagePaddingInsets,
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(CupertinoIcons.back, size: 18),
                  ),
                  const SizedBox(width: kPagePadding / 2),
                  Text('Inbox', style: textTheme.titleLarge),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                kPagePadding,
                0,
                kPagePadding,
                kPagePadding,
              ),
              child: Column(
                children: [
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Search messages...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                    ),
                    onChanged: _onSearchChanged,
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  TextField(
                    controller: _maxVisibleMessagesController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      hintText: 'Visible messages limit',
                      prefixIcon: const Icon(Icons.filter_list),
                      suffixText: 'max',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kBorderRadius),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                    ),
                    onChanged: _onMaxVisibleMessagesChanged,
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  if (_isMessageListTruncated)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Showing first $_maxVisibleMessages of $_filteredMessageCount messages',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  const SizedBox(height: kPagePadding / 2),
                  _buildFilterSection(
                    title: 'Filter by sender:',
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedSender == null ||
                            _selectedSender!.isEmpty,
                        onSelected: (selected) {
                          setState(() {
                            _selectedSender = null;
                            _applyFilters();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ..._uniqueSenders.map((sender) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(sender),
                            selected: _selectedSender == sender,
                            onSelected: (selected) {
                              setState(() {
                                _selectedSender = selected ? sender : null;
                                _applyFilters();
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                  const SizedBox(height: kPagePadding / 2),
                  _buildFilterSection(
                    title: 'Filter by amount:',
                    children: [
                      FilterChip(
                        label: const Text('All'),
                        selected: _selectedAmounts.isEmpty,
                        onSelected: (selected) {
                          setState(() {
                            _selectedAmounts.clear();
                            _applyFilters();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      ...sortedAmounts.map((amount) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Text(amount),
                            selected: _selectedAmounts.contains(amount),
                            onSelected: (selected) {
                              setState(() {
                                if (selected) {
                                  _selectedAmounts.add(amount);
                                } else {
                                  _selectedAmounts.remove(amount);
                                }
                                _applyFilters();
                              });
                            },
                          ),
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection({
    required String title,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: children),
        ),
      ],
    );
  }

  void _handleMessageTap(SmsMessage item) {
    final number = extract9DigitNumber(item.body ?? '');
    Clipboard.setData(ClipboardData(text: '0$number'));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('0$number copied to clipboard')),
    );
  }

  void _retrySelected() {
    for (final i in _selectedIndices) {
      if (i < _smsList.length) {
        onMessageReceive(_smsList[i]);
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Retried ${_selectedIndices.length} messages')),
    );
    setState(() => _selectedIndices.clear());
  }

  Future<void> _copySelectedNumbers() async {
    final numbers = _selectedIndices.map((i) {
      final n = extract9DigitNumber(_smsList[i].body ?? '');
      return '0$n';
    }).join(', ');

    await Clipboard.setData(ClipboardData(text: numbers));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied numbers')),
    );
    setState(() => _selectedIndices.clear());
  }
}

class _SmsTile extends StatelessWidget {
  final SmsMessage item;
  final int index;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _SmsTile({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final extractedNum = extract9DigitNumber(item.body ?? '');
    final dateTime = DateTime.fromMillisecondsSinceEpoch(item.date ?? 0);

    return GestureDetector(
      onLongPress: onLongPress,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 2),
        color: isSelected
            ? Theme.of(context).highlightColor
            : Theme.of(context).cardColor,
        padding: const EdgeInsets.all(kPagePadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      if (isSelected)
                        const Icon(Icons.check_box,
                            size: 18, color: kPrimaryColor),
                      if (isSelected) const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          item.address ?? 'Unknown',
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  '${getNormalTime(dateTime)} $interpunct ${getNormalDate(dateTime)}',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.body ?? ''),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (item.address == 'MPESA')
                      _actionButton(
                        icon: Icons.refresh,
                        color: kPrimaryColor,
                        onPressed: () {
                          tillDoneDialogue(
                            context,
                            const Text('Redialing'),
                            () async {
                              onMessageReceive(item);
                            },
                          );

                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Retrying message from MPESA')));

                          // vibrate

                        },
                      ),
                    const SizedBox(width: 8),
                    _actionButton(
                      icon: Icons.block,
                      color: kErrorColor,
                      onPressed: () async {
                        await TransactionController()
                            .changeBlackListStatus(extractedNum);
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('0$extractedNum blacklisted'),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    _actionButton(
                      icon: Icons.call,
                      color: Colors.blue,
                      onPressed: () => launchUrl(
                        Uri(scheme: 'tel', path: '0$extractedNum'),
                      ),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(
                      ClipboardData(text: '0$extractedNum'),
                    );
                  },
                  child: const Text(
                    'Copy number',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required Color color,
    required VoidCallback onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
