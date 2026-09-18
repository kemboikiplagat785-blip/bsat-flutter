import 'package:bsat/components/header.dart';
import 'package:bsat/models/client.dart';
import 'package:bsat/screens/clients/single_client.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/button_descriptive.dart';
import '../../components/dialogs/add_client_dialog.dart';
import 'sync_data.dart';

class ClientsPage extends StatefulWidget {
  const ClientsPage({super.key});

  @override
  State<ClientsPage> createState() => _ClientsPageState();
}

class _ClientsPageState extends State<ClientsPage> {
  final _sqliteService = SQLiteService();
  List<Client> _clients = [];
  List<Client> _filteredClients = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  String _sortBy = 'Last Active';
  final List<String> _sortOptions = [
    'Last Active',
    'Name',
    'Phone',
    'Purchases'
  ];
  final Set<int> _selectedClientIds = {};
  int? _lastSelectedIndex;
  bool _isRangeSelectMode = false;

  @override
  void initState() {
    super.initState();
    _getClients();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _getClients() async {
    final data = await _sqliteService.queryAll('clients');
    if (mounted) {
      setState(() {
        _clients = data.map((e) => Client.fromMap(e)).toList();
        _filteredClients = List.from(_clients);
        _sortClients();
        _isLoading = false;
      });
    }
  }

  void _filterClients(String query) {
    setState(() {
      if (query.isEmpty) {
        _filteredClients = List.from(_clients);
      } else {
        // Normalize query for phone search if it's digit-only
        String phoneQuery = query;
        if (RegExp(r'^\d+$').hasMatch(query)) {
          if (query.startsWith('0')) {
            phoneQuery = query.substring(1);
          } else if (query.startsWith('254')) {
            phoneQuery = query.substring(3);
          } else if (query.startsWith('+254')) {
            phoneQuery = query.substring(4);
          }
        }
        final q = query.toLowerCase();

        _filteredClients = _clients.where((client) {
          final name = client.fullName.toLowerCase();
          final phone = client.phoneNumber.replaceAll(RegExp(r'\D'), '');

          return name.contains(q) || phone.contains(phoneQuery);
        }).toList();
      }
      _sortClients();
    });
  }

  void _sortClients() {
    setState(() {
      switch (_sortBy) {
        case 'Name':
          _filteredClients.sort((a, b) => a.fullName.compareTo(b.fullName));
          break;
        case 'Phone':
          _filteredClients
              .sort((a, b) => a.phoneNumber.compareTo(b.phoneNumber));
          break;
        case 'Purchases':
          _filteredClients
              .sort((a, b) => b.noOfPurchases.compareTo(a.noOfPurchases));
          break;
        case 'Last Active':
        default:
          _filteredClients.sort((a, b) {
            final aDate = a.lastBought ?? a.createdAt;
            final bDate = b.lastBought ?? b.createdAt;
            return bDate.compareTo(aDate);
          });
          break;
      }
    });
  }

  Future<void> _deleteSelectedClients() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Clients'),
        content: Text('Delete ${_selectedClientIds.length} client(s)?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (int id in _selectedClientIds) {
        await _sqliteService.deleteStuff(
          id,
          'clients',
        );
      }
      setState(() {
        _selectedClientIds.clear();
      });
      await _getClients();
    }
  }

  void _sendMessageToSelected() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
            'Message feature - selected ${_selectedClientIds.length} clients'),
      ),
    );
  }

  void _selectRange(int currentIndex) {
    if (_lastSelectedIndex == null) return;

    final start =
        _lastSelectedIndex! < currentIndex ? _lastSelectedIndex! : currentIndex;
    final end =
        _lastSelectedIndex! > currentIndex ? _lastSelectedIndex! : currentIndex;

    setState(() {
      for (int i = start; i <= end; i++) {
        if (i < _filteredClients.length) {
          _selectedClientIds.add(_filteredClients[i].id!);
        }
      }
      _isRangeSelectMode = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: () async {
            await showAddClientDialog(context);
            _getClients();
          },
          backgroundColor: kPrimaryColor,
          foregroundColor: Colors.white,
          child: const Icon(CupertinoIcons.add),
        ),
        body: Column(
          children: [
            // Keeping the selection context bar fixed at the top for better UX
            if (_selectedClientIds.isNotEmpty)
              Container(
                color: Theme.of(context).cardColor,
                padding: const EdgeInsets.symmetric(
                    horizontal: kPagePadding, vertical: kPagePadding / 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _isRangeSelectMode
                          ? 'Select range: tap another item'
                          : '${_selectedClientIds.length} selected',
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
                                // FIX: Do not set _lastSelectedIndex to null here, it clears the anchor!
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
                          onPressed: _isRangeSelectMode
                              ? null
                              : _sendMessageToSelected,
                          icon: Icon(
                            CupertinoIcons.mail,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: _isRangeSelectMode
                              ? null
                              : _deleteSelectedClients,
                          icon: Icon(
                            CupertinoIcons.trash,
                            color: kErrorColor,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedClientIds.clear();
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

            Expanded(
              // Wrapped with CustomScrollView so the WHOLE page acts as one scrolling body
              child: ScrollbarTheme(
                data: ScrollbarThemeData(
                  thumbVisibility: const WidgetStatePropertyAll(true),
                  thickness: const WidgetStatePropertyAll(10),
                  radius: const Radius.circular(12),
                  trackVisibility: const WidgetStatePropertyAll(true),
                  thumbColor: WidgetStatePropertyAll(
                    kPrimaryColor.withValues(alpha: 0.7),
                  ),
                ),
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: true,
                  interactive: true,
                  thickness: 10,
                  radius: const Radius.circular(12),
                  trackVisibility: true,
                  child: CustomScrollView(
                    controller: _scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: header(context, "Clients"),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: kPagePaddingInsets,
                          child: Container(
                            padding: const EdgeInsets.all(kPagePadding),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius:
                                  BorderRadius.circular(kBorderRadius),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                Column(
                                  children: [
                                    Text(
                                      _clients.length.toString(),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text('Total Clients'),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text(
                                      _clients
                                          .fold<int>(
                                              0,
                                              (sum, client) =>
                                                  sum + client.noOfPurchases)
                                          .toString(),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    const Text('Total Purchases'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: buttonDescriptive(
                          context,
                          title: 'Sync client data',
                          subtitle:
                              'Import/export all clients and contacts data',
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => const SyncDataPage(),
                              ),
                            );
                            _getClients();
                          },
                          icon: Icon(
                            CupertinoIcons.arrow_2_circlepath,
                            color: kPrimaryColor,
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                              kPagePadding, 0, kPagePadding, kPagePadding),
                          child: Column(
                            children: [
                              const SizedBox(height: kPagePadding),
                              TextField(
                                controller: _searchController,
                                onChanged: _filterClients,
                                decoration: InputDecoration(
                                  hintText: 'Search by name or phone',
                                  prefixIcon: const Icon(CupertinoIcons.search),
                                  suffixIcon: _searchController.text.isNotEmpty
                                      ? GestureDetector(
                                          onTap: () {
                                            _searchController.clear();
                                            _filterClients('');
                                          },
                                          child: const Icon(
                                              CupertinoIcons.xmark_circle_fill),
                                        )
                                      : null,
                                  border: OutlineInputBorder(
                                    borderRadius:
                                        BorderRadius.circular(kBorderRadius),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Sort by:',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                  DropdownButton<String>(
                                    value: _sortBy,
                                    underline: Container(),
                                    icon: const Icon(CupertinoIcons.sort_down),
                                    onChanged: (String? newValue) {
                                      if (newValue != null) {
                                        setState(() {
                                          _sortBy = newValue;
                                          _sortClients();
                                        });
                                      }
                                    },
                                    items: _sortOptions
                                        .map<DropdownMenuItem<String>>(
                                            (String value) {
                                      return DropdownMenuItem<String>(
                                        value: value,
                                        child: Text(value),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (_isLoading)
                        const SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_filteredClients.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  CupertinoIcons.person_2,
                                  size: 64,
                                ),
                                const SizedBox(height: kPagePadding),
                                Text(
                                  "No clients yet",
                                  style: TextStyle(
                                    color: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.color
                                        ?.withValues(alpha: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: kPagePaddingInsets,
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final client = _filteredClients[index];
                                final isSelected =
                                    _selectedClientIds.contains(client.id);

                                return InkWell(
                                  onTap: () {
                                    if (_isRangeSelectMode) {
                                      // FIX: Calculate the range BEFORE overwriting _lastSelectedIndex
                                      _selectRange(index);
                                      _lastSelectedIndex = index;
                                    } else if (_selectedClientIds.isEmpty) {
                                      Navigator.of(context)
                                          .push(
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  SingleClientPage(
                                                id: client.id!,
                                              ),
                                            ),
                                          )
                                          .then((_) => _getClients());
                                    } else {
                                      setState(() {
                                        if (isSelected) {
                                          _selectedClientIds.remove(client.id);
                                        } else {
                                          _selectedClientIds.add(client.id!);
                                          _lastSelectedIndex = index;
                                        }
                                      });
                                    }
                                  },
                                  onLongPress: () {
                                    setState(() {
                                      if (isSelected) {
                                        _selectedClientIds.remove(client.id);
                                      } else {
                                        _selectedClientIds.add(client.id!);
                                        _lastSelectedIndex = index;
                                      }
                                    });
                                  },
                                  child: Card(
                                    margin: const EdgeInsets.only(
                                        bottom: kPagePadding / 2),
                                    elevation: 0,
                                    color: isSelected
                                        ? kPrimaryColor.withValues(alpha: 0.1)
                                        : Theme.of(context).cardColor,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                          BorderRadius.circular(kBorderRadius),
                                      side: isSelected
                                          ? BorderSide(
                                              color: kPrimaryColor, width: 2)
                                          : BorderSide.none,
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12.0),
                                      child: Row(
                                        children: [
                                          CircleAvatar(
                                            backgroundColor: kPrimaryColor
                                                .withValues(alpha: 0.1),
                                            child: Text(
                                              client.firstName.isNotEmpty
                                                  ? client.firstName[0]
                                                      .toUpperCase()
                                                  : "#",
                                              style: TextStyle(
                                                color: kPrimaryColor,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: kPagePadding),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  client.fullName.isNotEmpty
                                                      ? client.fullName
                                                      : client.phoneNumber,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(client.formattedPhone),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                "${client.noOfPurchases} Purchases",
                                                style: TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                  color: kPrimaryColor,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              if (client.lastBought != null)
                                                Text(_lastActiveLabel(client)),
                                            ],
                                          ),
                                          const SizedBox(width: 8),
                                          const Icon(
                                            CupertinoIcons.chevron_forward,
                                            size: 16,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              childCount: _filteredClients.length,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _lastActiveLabel(Client client) {
    final days = client.daysSinceLastPurchase ?? 0;
    final date = client.lastBought ?? client.createdAt;
    if (days == 0) {
      return '${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
    }
    return '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');
}
