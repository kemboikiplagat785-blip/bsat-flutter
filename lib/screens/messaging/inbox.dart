import 'dart:async';
import 'package:another_telephony/telephony.dart';
import 'package:bsat/controllers/transaction_controller.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart';

import '../../components/dialogs/till_done_dialogue.dart';
import '../../utils/constants.dart';

class InboxPage extends StatefulWidget {
  const InboxPage({super.key});

  @override
  State<InboxPage> createState() => _InboxPageState();
}

class _InboxPageState extends State<InboxPage> {
  List<SmsMessage> _smsList = [];
  bool _isLoading = true;
  final Set<int> _selectedIndices = {};
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _fetchSms();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  /// Fetches SMS with a limit based on mode
  Future<void> _fetchSms() async {
    int limit = kDebugMode ? 20 : 400;
    try {
      final messages = await getAllSms(limit: limit);
      if (mounted) {
        setState(() {
          _smsList = messages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Search logic with Debouncing to prevent UI freeze while typing
  void _onSearchChanged(String query) {
    if (_searchDebounce?.isActive ?? false) _searchDebounce!.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 500), () async {
      final results = await searchSms(query);
      if (mounted) {
        setState(() {
          _smsList = results;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      // We use a Column + Expanded instead of SingleChildScrollView
      // This allows the ListView to only render visible items (Lazy Loading)
      body: Column(
        children: [
          _buildHeader(context, textTheme),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _smsList.isEmpty
                    ? const Center(child: Text("No messages found"))
                    : RawScrollbar(
                        thumbColor: kPrimaryColor,
                        thickness: 8,
                        thumbVisibility: true,
                        child: ListView.builder(
                          // Important: No shrinkWrap, no NeverScrollableScrollPhysics
                          padding: const EdgeInsets.symmetric(
                              vertical: kPagePadding),
                          itemCount: _smsList.length,
                          itemBuilder: (context, index) {
                            final item = _smsList[index];
                            return _SmsTile(
                              item: item,
                              index: index,
                              isSelected: _selectedIndices.contains(index),
                              onToggle: () {
                                setState(() {
                                  if (_selectedIndices.contains(index)) {
                                    _selectedIndices.remove(index);
                                  } else {
                                    _selectedIndices.add(index);
                                  }
                                });
                              },
                              onTap: () => _handleMessageTap(item, index),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// Extracted Header Widget for better readability
  Widget _buildHeader(BuildContext context, TextTheme textTheme) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(kBorderRadius),
          bottomRight: Radius.circular(kBorderRadius),
        ),
        color: Theme.of(context).cardColor,
      ),
      child: SafeArea(
        // Ensures content stays below the status bar
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: kPagePaddingInsets,
              child: _selectedIndices.isEmpty
                  ? Row(
                      children: [
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(CupertinoIcons.back, size: 18),
                        ),
                        const SizedBox(width: kPagePadding / 2),
                        Text('Inbox', style: textTheme.titleLarge),
                      ],
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            IconButton(
                              onPressed: () =>
                                  setState(() => _selectedIndices.clear()),
                              icon: const Icon(Icons.close),
                            ),
                            Text('${_selectedIndices.length} selected'),
                          ],
                        ),
                        Row(
                          children: [
                            IconButton(
                              tooltip: 'Retry selected',
                              onPressed: _retrySelected,
                              icon: const Icon(Icons.refresh),
                            ),
                            IconButton(
                              tooltip: 'Copy numbers',
                              onPressed: _copySelectedNumbers,
                              icon: const Icon(Icons.copy),
                            ),
                          ],
                        )
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  kPagePadding, 0, kPagePadding, kPagePadding),
              child: TextField(
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
            )
          ],
        ),
      ),
    );
  }

  void _handleMessageTap(SmsMessage item, int index) {
    if (_selectedIndices.isNotEmpty) {
      setState(() {
        if (_selectedIndices.contains(index)) {
          _selectedIndices.remove(index);
        } else {
          _selectedIndices.add(index);
        }
      });
    } else {
      int number = extract9DigitNumber(item.body ?? "");
      Clipboard.setData(ClipboardData(text: '0$number'));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('0$number copied to clipboard')),
      );
    }
  }

  void _retrySelected() {
    for (final i in _selectedIndices) {
      if (i < _smsList.length) onMessageReceive(_smsList[i]);
    }
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Retried ${_selectedIndices.length} messages')));
    setState(() => _selectedIndices.clear());
  }

  void _copySelectedNumbers() async {
    final numbers = _selectedIndices.map((i) {
      int n = extract9DigitNumber(_smsList[i].body ?? "");
      return '0$n';
    }).join(', ');

    await Clipboard.setData(ClipboardData(text: numbers));
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Copied numbers')));
    setState(() => _selectedIndices.clear());
  }
}

/// Extracted Tile Widget to reduce rebuild complexity
class _SmsTile extends StatelessWidget {
  final SmsMessage item;
  final int index;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onTap;

  const _SmsTile({
    required this.item,
    required this.index,
    required this.isSelected,
    required this.onToggle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Extract number once per build to save resources
    final int extractedNum = extract9DigitNumber(item.body ?? "");

    return GestureDetector(
      onLongPress: onToggle,
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
                      Text(item.address ?? "Unknown",
                          style: textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                Text(
                  '${getNormalTime(DateTime.fromMillisecondsSinceEpoch(item.date ?? 0))} $interpunct ${getNormalDate(DateTime.fromMillisecondsSinceEpoch(item.date ?? 0))}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(item.body ?? ""),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    if (item.address == "MPESA")
                      _actionButton(
                        icon: Icons.refresh,
                        color: kPrimaryColor,
                        onPressed: () {
                          tillDoneDialogue(context, const Text("Redialing"),
                              () async {
                            onMessageReceive(item);
                          });
                        },
                      ),
                    const SizedBox(width: 8),
                    _actionButton(
                      icon: Icons.block,
                      color: kErrorColor,
                      onPressed: () async {
                        await TransactionController()
                            .changeBlackListStatus(extractedNum);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('0$extractedNum blacklisted')));
                      },
                    ),
                    const SizedBox(width: 8),
                    _actionButton(
                      icon: Icons.call,
                      color: Colors.blue,
                      onPressed: () =>
                          launchUrl(Uri(scheme: 'tel', path: "0$extractedNum")),
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: "0$extractedNum"));
                  },
                  child: const Text('Copy number',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _actionButton(
      {required IconData icon,
      required Color color,
      required VoidCallback onPressed}) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color, size: 18),
      ),
    );
  }
}
