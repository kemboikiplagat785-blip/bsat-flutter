import 'package:bsat/components/header.dart';
import 'package:bsat/models/client.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/logger.dart';
import 'package:flutter/material.dart';
// import 'package:flutter/scheduler.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/components/tool_button.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

class SingleClientPage extends StatefulWidget {
  final int id;
  const SingleClientPage({required this.id, super.key});

  @override
  State<SingleClientPage> createState() => _SingleClientPageState();
}

class _SingleClientPageState extends State<SingleClientPage> {
  final _sqliteService = SQLiteService();
  final _log = BsatLogger(tag: 'SingleClientPage');
  Client? _client;
  List<Map<String, dynamic>> _transactions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _log.info('initState called for client ${widget.id}', {'id': widget.id});
    getStuff();
  }

  void getStuff() async {
    try {
      if (!mounted) return;
      _log.debug('getStuff started');

      final clientData = await _sqliteService.queryOne('clients', widget.id);
      _log.debug('Client data fetched', {'data': clientData});

      if (clientData.isNotEmpty) {
        _log.debug('Client found, parsing...');
        _client = Client.fromMap(clientData);
        _log.debug('Client parsed: ${_client?.fullName}');

        String cleanPhone =
            _client!.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
        if (cleanPhone.startsWith('254')) {
          cleanPhone = cleanPhone.substring(3);
        } else if (cleanPhone.startsWith('0')) {
          cleanPhone = cleanPhone.substring(1);
        }
        _log.debug('Cleaned phone number: $cleanPhone');

        _transactions = await _sqliteService.queryCustom(
          'transactions',
          'number = ? OR number = ?',
          [cleanPhone, _client!.phoneNumber],
          orderBy: 'id DESC',
        );
        _log.debug('Transactions fetched: ${_transactions.length}');

        // _transactions
        //     .sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
      } else {
        _log.warn('Client data is empty for id: ${widget.id}');
      }
    } catch (e, stack) {
      _log.error('Error in getStuff',
          {'error': e.toString(), 'stack': stack.toString()});
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _log.debug('Set state called, loading finished');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _client == null
              ? const Center(child: Text("Client not found"))
              : SingleChildScrollView(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      header(
                          context,
                          _client!.firstName.isNotEmpty
                              ? _client!.firstName
                              : _client!.phoneNumber),
                      Padding(
                        padding: kPagePaddingInsets,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              padding: kPagePaddingInsets,
                              decoration: BoxDecoration(
                                // color: Theme.of(context).cardColor,
                                borderRadius:
                                    BorderRadius.circular(kBorderRadius),
                                border: Border(
                                  right: BorderSide(
                                    color: kIndigoColor,
                                    width: 4.0,
                                  ),
                                  bottom: BorderSide(
                                    color: kIndigoColor,
                                    width: 4.0,
                                  ),
                                ),
                                image: const DecorationImage(
                                  image: AssetImage(
                                      'assets/images/mesh_distorted.png'),
                                  alignment: Alignment.centerLeft,
                                  fit: BoxFit.cover,
                                  opacity: 0.9,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _client!.fullName,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      if (_client!.isActive)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 4),
                                          decoration: BoxDecoration(
                                            color:
                                                kPrimaryColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                                kBorderRadius),
                                          ),
                                          child: Text(
                                            "Active",
                                            style: TextStyle(
                                              color: kPrimaryColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: kPagePadding),
                                  _buildInfoRow(context, "Phone",
                                      _client!.formattedPhone),
                                  const SizedBox(height: kPagePadding / 2),
                                  _buildInfoRow(context, "Purchases",
                                      "${_client!.noOfPurchases}"),
                                  const SizedBox(height: kPagePadding / 2),
                                  _buildInfoRow(
                                      context,
                                      "Last Bought",
                                      _client!.lastBought != null
                                          ? "${_client!.lastBought!.day}/${_client!.lastBought!.month}/${_client!.lastBought!.year}"
                                          : "Never"),
                                  const SizedBox(height: kPagePadding / 2),
                                  _buildInfoRow(context, "Added On",
                                      "${_client!.createdAt.day}/${_client!.createdAt.month}/${_client!.createdAt.year}"),
                                  const SizedBox(height: kPagePadding * 1.5),
                                  Wrap(
                                    spacing: 10,
                                    runSpacing: 10,
                                    children: [
                                      toolButton(
                                        () async {
                                          final Uri launchUri = Uri(
                                            scheme: 'tel',
                                            path: _client!.phoneNumber,
                                          );
                                          if (await canLaunchUrl(launchUri)) {
                                            await launchUrl(launchUri);
                                          }
                                        },
                                        Icon(
                                          CupertinoIcons.phone,
                                          color: kPrimaryColor,
                                          size: 14,
                                        ),
                                        "Call",
                                        context,
                                        textSize: 13,
                                      ),
                                      toolButton(
                                        () async {
                                          final Uri launchUri = Uri(
                                            scheme: 'sms',
                                            path: _client!.phoneNumber,
                                          );
                                          if (await canLaunchUrl(launchUri)) {
                                            await launchUrl(launchUri);
                                          }
                                        },
                                        Icon(
                                          CupertinoIcons.chat_bubble,
                                          color: kLightBlueColor,
                                          size: 14,
                                        ),
                                        "SMS",
                                        context,
                                        textSize: 13,
                                      ),
                                      toolButton(
                                        () async {
                                          await Clipboard.setData(
                                            ClipboardData(
                                                text: _client!.formattedPhone),
                                          );
                                          ScaffoldMessenger.of(context)
                                              .showSnackBar(
                                            SnackBar(
                                                content: Text(
                                                    '${_client!.formattedPhone} copied to clipboard')),
                                          );
                                        },
                                        Icon(
                                          Icons.copy,
                                          color:
                                              Theme.of(context).indicatorColor,
                                          size: 14,
                                        ),
                                        "Copy Number",
                                        context,
                                        textSize: 13,
                                      ),
                                      // Edit and delete could act here if controllers/dialogs existed
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: kPagePadding),
                            Text(
                              "Transactions (${_transactions.length})",
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.color
                                    ?.withOpacity(0.7),
                              ),
                            ),
                            const SizedBox(height: kPagePadding / 2),
                            if (_transactions.isEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(30),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                ),
                                child: Center(
                                  child: Text(
                                    "No transactions found",
                                    style: TextStyle(
                                        color: kGrayColor.withOpacity(0.5)),
                                  ),
                                ),
                              )
                            else
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _transactions.length,
                                itemBuilder: (context, index) {
                                  final transaction = _transactions[index];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).cardColor,
                                      borderRadius:
                                          BorderRadius.circular(kBorderRadius),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              "${transaction['ussdDialed'] ?? 'Unknown Offer'}",
                                              style: TextStyle(
                                                  fontWeight: FontWeight.bold),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              "${transaction['date']} ${interpunct} ${transaction['time']}",
                                              style: TextStyle(
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        Text(
                                          "Ksh ${transaction['amount']}",
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: kPrimaryColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
              // color: Theme.of(context).textTheme.bodySmall?.color,
              ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
