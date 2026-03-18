import 'package:bsat/components/header.dart';
import 'package:bsat/models/client.dart';
import 'package:bsat/screens/clients/single_client.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../components/button_descriptive.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          header(context, "Clients"),
          // all clients general data e.g total clients, total purchases, total spent etc
          Padding(
            padding: kPagePaddingInsets,
            child: Container(
              padding: const EdgeInsets.all(kPagePadding),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(kBorderRadius),
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
                      Text(
                        'Total Clients',
                        style: TextStyle(
                            // color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                      ),
                    ],
                  ),
                  Column(
                    children: [
                      Text(
                        _clients
                            .fold<int>(
                                0, (sum, client) => sum + client.noOfPurchases)
                            .toString(),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total Purchases',
                        style: TextStyle(
                            // color: Theme.of(context).textTheme.bodySmall?.color,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          buttonDescriptive(
            context,
            title: 'Sync client data',
            subtitle: 'Import/export all clients and contacts data',
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
          Padding(
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
                            child: const Icon(CupertinoIcons.xmark_circle_fill),
                          )
                        : null,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(kBorderRadius),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Sort by:',
                      style: TextStyle(
                        // color: Theme.of(context).textTheme.bodySmall?.color,
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
                          .map<DropdownMenuItem<String>>((String value) {
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
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredClients.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.person_2,
                              size: 64,
                              // color: kGrayColor,
                            ),
                            const SizedBox(height: kPagePadding),
                            Text(
                              "No clients yet",
                              style: TextStyle(
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color
                                    ?.withOpacity(0.5),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Scrollbar(
                        // can be used to scroll the list when it grows too long

                        controller: _scrollController,
                        thumbVisibility: true,
                        interactive: true,
                        child: ListView.builder(
                          controller: _scrollController,
                          padding: kPagePaddingInsets,
                          itemCount: _filteredClients.length,
                          itemBuilder: (context, index) {
                            final client = _filteredClients[index];
                            return InkWell(
                              onTap: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) => SingleClientPage(
                                      id: client.id!,
                                    ),
                                  ),
                                );
                              },
                              child: Card(
                                margin: const EdgeInsets.only(
                                    bottom: kPagePadding / 2),
                                elevation: 0,
                                color: Theme.of(context).cardColor,
                                shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12.0),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor:
                                            kPrimaryColor.withOpacity(0.1),
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
                                                // fontSize: 16,
                                              ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              client.formattedPhone,
                                              style: TextStyle(
                                                  // color: Theme.of(context)
                                                  //     .textTheme
                                                  //     .bodySmall
                                                  //     ?.color,
                                                  // fontSize: 13,
                                                  ),
                                            ),
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
                                              // fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: kPrimaryColor,
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          if (client.lastBought != null)
                                            Text(
                                              _lastActiveLabel(client),
                                              style: TextStyle(
                                                  // fontSize: 12,
                                                  // color: kGrayColor,
                                                  ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(width: 8),
                                      Icon(
                                        CupertinoIcons.chevron_forward,
                                        size: 16,
                                        // color: kGrayColor.withOpacity(0.5),
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
        ],
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
