import 'package:bsat/components/dialogs/change_category_dialog.dart';
import 'package:bsat/components/dialogs/forward_text.dart';
import 'package:bsat/components/dialogs/show_confirm_dialog.dart';
import 'package:bsat/components/header.dart';
import 'package:bsat/models/client.dart';
import 'package:bsat/screens/online_management/search_device.dart';
import 'package:bsat/services/sms_sevice.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../components/dialogs/confirm_delete_dialog.dart';
import '../../components/dialogs/loading_dialog.dart';
import '../../components/dialogs/success_dialog.dart';
import '../../components/dialogs/till_done_dialogue.dart';
import '../../components/tool_button.dart';
import '../../controllers/transaction_controller.dart';
import '../../services/backend_service.dart';
import '../../services/contacts_service.dart';
import '../../services/shared_preferences_service.dart';
import '../../utils/constants.dart';
import '../../utils/forwarding_job_id.dart';
import '../clients/single_client.dart';
import '../tasks/edit_task.dart';

class SingleTransactionPage extends StatefulWidget {
  final dynamic id;

  const SingleTransactionPage({required this.id, super.key});

  @override
  State<SingleTransactionPage> createState() => _SingleTransactionPageState();
}

class _SingleTransactionPageState extends State<SingleTransactionPage> {
  final _sqliteService = SQLiteService();
  late final int _currentTransactionId;
  Map<String, dynamic> _details = {};
  int? _previousTransactionId;
  int? _nextTransactionId;

  final _contactService = ContactsService();
  bool showFullMpesaMessage = false;
  bool showFullReply = false;
  bool _isBlacklisted = false;
  Client? _client;

  List toForward = [];

  @override
  void initState() {
    super.initState();
    _currentTransactionId =
        int.tryParse(widget.id.toString()) ?? widget.id as int;
    getStuff();
  }

  Future<void> getStuff() async {
    if (!mounted) return;
    final details =
        await _sqliteService.queryOne('transactions', _currentTransactionId);
    if (!mounted) return;

    final previous = await _sqliteService.queryCustom(
      'transactions',
      'id < ?',
      [_currentTransactionId],
      orderBy: 'id DESC',
      limit: 1,
    );
    final next = await _sqliteService.queryCustom(
      'transactions',
      'id > ?',
      [_currentTransactionId],
      orderBy: 'id ASC',
      limit: 1,
    );

    _isBlacklisted = await _sqliteService.getCount(
          'blacklist',
          args: [details['number']],
          appendQuery: 'WHERE number = ?',
        ) >
        0;

    toForward = await _sqliteService.queryCustom(
      "forwarded",
      "(amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)",
      [
        '[${details['amount']},%',
        '%,${details['amount']},%',
        '%,${details['amount']}]',
        '[${details['amount']}]',
      ],
    );

    Client? client;
    try {
      final numberStr = details['number'].toString();
      final clients = await _sqliteService.queryCustom(
        'clients',
        'phoneNumber LIKE ? OR phoneNumber LIKE ? OR phoneNumber LIKE ?',
        ['%$numberStr%', '%$numberStr', '0$numberStr'],
        limit: 1,
      );
      if (clients.isNotEmpty) {
        client = Client.fromMap(clients.first);
      }
    } catch (e) {
      debugPrint('Error fetching client: $e');
    }

    if (!mounted) return;
    setState(() {
      _details = details;
      _previousTransactionId = previous.isNotEmpty
          ? int.tryParse(previous.first['id'].toString())
          : null;
      _nextTransactionId =
          next.isNotEmpty ? int.tryParse(next.first['id'].toString()) : null;
      _client = client;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Scaffold(
        body: Stack(
          children: [
            SingleChildScrollView(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header(context, '0${_details["number"]}'),
                  if (_client != null)
                    Padding(
                      padding: kPagePaddingInsets,
                      child: GestureDetector(
                        onTap: () async {
                          final result = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  SingleClientPage(id: _client!.id ?? -1),
                            ),
                          );
                          if (result == true) {
                            getStuff();
                          }
                        },
                        child: Container(
                          padding: kPagePaddingInsets,
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(kBorderRadius),
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
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        kIndigoColor.withValues(alpha: 0.1),
                                    child: Text(
                                      _client!.firstName.isNotEmpty
                                          ? _client!.firstName[0].toUpperCase()
                                          : "#",
                                      style: TextStyle(
                                        color: kIndigoColor,
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
                                          _client!.firstName.isNotEmpty
                                              ? _client!.fullName
                                              : "Unknown Client",
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Text(
                                              _client!.formattedPhone,
                                              style: TextStyle(
                                                color: kPrimaryColor,
                                                fontSize: 13,
                                              ),
                                            ),
                                            GestureDetector(
                                              onTap: () {
                                                Clipboard.setData(
                                                  ClipboardData(
                                                    text:
                                                        _client!.formattedPhone,
                                                  ),
                                                );
                                                ScaffoldMessenger.of(context)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '${_client!.formattedPhone} copied to clipboard',
                                                    ),
                                                  ),
                                                );
                                              },
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                    kPagePadding / 3),
                                                child: Icon(
                                                  Icons.copy_rounded,
                                                  size: 13,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    children: [
                                      if (_client!.noOfPurchases == 1 &&
                                          (_client!.daysSinceLastPurchase ??
                                                  999) <=
                                              1)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 4,
                                          ),
                                          margin: const EdgeInsets.only(
                                              bottom: kPagePadding / 3),
                                          decoration: BoxDecoration(
                                            color: kIndigoColor.withValues(
                                                alpha: 0.1),
                                            borderRadius: BorderRadius.circular(
                                                kBorderRadius),
                                          ),
                                          child: Text(
                                            "New Client",
                                            style: TextStyle(
                                              color: kPrimaryColor,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      Text(
                                        "${_client!.noOfPurchases} Purchases",
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: kPrimaryColor,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const SizedBox(height: kPagePadding),
                              Row(
                                spacing: kPagePadding / 2,
                                children: [
                                  InkWell(
                                    onTap: () async {
                                      await tillDoneDialogue(
                                        context,
                                        Text("Adding contact"),
                                        () async {
                                          await _contactService.addNewContact(
                                            _details['source'],
                                            '0${_details["number"]}',
                                          );
                                        },
                                      );
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '0${_details['number']} added to contacts',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.person_add_outlined,
                                          color: kIndigoColor,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          "Add to phonebook",
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () async {
                                      final nowBlacklisted =
                                          await TransactionController()
                                              .changeBlackListStatus(
                                                  _details['number']);
                                      setState(() {
                                        _isBlacklisted = nowBlacklisted;
                                      });
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '0${_details['number']} ${_isBlacklisted ? "added to" : "removed from"} blacklist',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.person_remove_outlined,
                                          color: kIndigoColor,
                                          size: 14,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          _isBlacklisted
                                              ? "Remove from blacklist"
                                              : "Add to blacklist",
                                          style: TextStyle(
                                            color: kErrorColor,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              if (_client!.noOfPurchases == 1 &&
                                  (_client!.daysSinceLastPurchase ?? 999) <= 1)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    "1 new purchase in last day",
                                    style: TextStyle(
                                      color:
                                          kIndigoColor.withValues(alpha: 0.7),
                                      fontSize: 11,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  Padding(
                    padding: kPagePaddingInsets,
                    child: Container(
                      padding: kPagePaddingInsets,
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(kBorderRadius),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // --- USSD Section ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    '${_details["ussdDialed"]}',
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: '${_details["ussdDialed"]}',
                                        ),
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            '${_details["ussdDialed"]} copied to clipboard',
                                          ),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                          kPagePadding / 3),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                'KSH ${_details["amount"]}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: kPrimaryColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 2),

                          // --- Date & Status Section ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                '${_details["time"]} $interpunct ${_details["date"]}',
                                style: TextStyle(fontSize: 11),
                              ),
                              const SizedBox(width: kPagePadding / 2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _details["status"] ==
                                          TransactionStatuses.done
                                      ? kPrimaryColor.withValues(alpha: 0.1)
                                      : _details["status"] ==
                                              TransactionStatuses.doneConfirmed
                                          ? kPrimaryColor.withValues(alpha: 0.1)
                                          : _details["status"] ==
                                                  TransactionStatuses
                                                      .advancedUssd
                                              ? kPrimaryColor.withValues(
                                                  alpha: 0.1)
                                              : _details["status"] ==
                                                      TransactionStatuses.error
                                                  ? kErrorColor.withValues(
                                                      alpha: 0.1)
                                                  : _details["status"] ==
                                                          TransactionStatuses
                                                              .blacklisted
                                                      ? kErrorColor.withValues(
                                                          alpha: 0.1)
                                                      : _details["status"] ==
                                                                  TransactionStatuses
                                                                      .paused ||
                                                              _details[
                                                                      "status"] ==
                                                                  TransactionStatuses
                                                                      .secondAttempt
                                                          ? kWarningColor
                                                              .withValues(
                                                                  alpha: 0.1)
                                                          : Colors.white
                                                              .withValues(
                                                                  alpha: 0.1),
                                  borderRadius:
                                      BorderRadius.circular(kBorderRadius),
                                ),
                                child: Text(
                                  _details["status"] == TransactionStatuses.done
                                      ? "Successful(pending)"
                                      : _details["status"] ==
                                              TransactionStatuses.doneConfirmed
                                          ? "Successful (confirmed)"
                                          : _details["status"] ==
                                                  TransactionStatuses
                                                      .advancedUssd
                                              ? "Advanced"
                                              : _details["status"] ==
                                                      TransactionStatuses.error
                                                  ? "Error"
                                                  : _details["status"] ==
                                                          TransactionStatuses
                                                              .blacklisted
                                                      ? "Blacklisted"
                                                      : _details["status"] ==
                                                              TransactionStatuses
                                                                  .paused
                                                          ? "Paused"
                                                          : _details["status"] ==
                                                                  TransactionStatuses
                                                                      .forwarded
                                                              ? "forwarded"
                                                              : _details["status"] ==
                                                                      TransactionStatuses
                                                                          .unavailableOffer
                                                                  ? "Unavailable"
                                                                  : _details["status"] ==
                                                                          TransactionStatuses
                                                                              .secondAttempt
                                                                      ? "Second Attempt"
                                                                      : "[]",
                                  style: TextStyle(
                                    color: _details["status"] ==
                                            TransactionStatuses.done
                                        ? kWarningColor
                                        : _details["status"] ==
                                                TransactionStatuses
                                                    .doneConfirmed
                                            ? kPrimaryColor
                                            : _details["status"] ==
                                                    TransactionStatuses
                                                        .advancedUssd
                                                ? kPrimaryColor
                                                : _details["status"] ==
                                                        TransactionStatuses
                                                            .error
                                                    ? kErrorColor
                                                    : _details["status"] ==
                                                            TransactionStatuses
                                                                .blacklisted
                                                        ? kErrorColor
                                                        : _details["status"] ==
                                                                    TransactionStatuses
                                                                        .paused ||
                                                                _details[
                                                                        "status"] ==
                                                                    TransactionStatuses
                                                                        .secondAttempt
                                                            ? kWarningColor
                                                            : Colors.white,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding / 2),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              toolButton(
                                () async {
                                  debugPrint(
                                      'Details before retrying: $_details');
                                  tillDoneDialogue(
                                    context,
                                    Padding(
                                      padding: kPagePaddingInsets,
                                      child: Text("Redialing"),
                                    ),
                                    () async {
                                      await TransactionController()
                                          .redoTransaction(
                                              _details["id"],
                                              _details["ussdDialed"],
                                              _details["simSubId"],
                                              _details["canRetry"],
                                              _details["ussdReply"]);

                                      getStuff();
                                    },
                                  );
                                },
                                Icon(
                                  CupertinoIcons.phone_arrow_up_right,
                                  color: kPrimaryColor,
                                  size: 14,
                                ),
                                "Retry",
                                context,
                                textSize: 13,
                              ),
                              toolButton(
                                () {
                                  Navigator.of(context).push(
                                    PageRouteBuilder(
                                      pageBuilder: (
                                        context,
                                        animation,
                                        secondaryAnimation,
                                      ) =>
                                          EditTaskPage(
                                        taskId: -2,
                                        number: _details['number'],
                                        dialSim: _details['simSubId'],
                                        amount: _details['amount'],
                                        offer: _details['ussdDialed'],
                                      ),
                                      transitionsBuilder: (context, animation,
                                          secondaryAnimation, child) {
                                        return CupertinoPageTransition(
                                          primaryRouteAnimation: animation,
                                          secondaryRouteAnimation:
                                              secondaryAnimation,
                                          linearTransition: true,
                                          child: child,
                                        );
                                      },
                                    ),
                                  );
                                },
                                Icon(
                                  Icons.precision_manufacturing_outlined,
                                  color: kErrorColor,
                                  size: 14,
                                ),
                                "Retry later (Schedule)",
                                context,
                                textSize: 13,
                              ),
                              toolButton(
                                () async {
                                  String? status =
                                      await showChangeCategoryDialog(context);

                                  if (status != null && status.isNotEmpty) {
                                    await _sqliteService.updateStuff(
                                      {
                                        'status': status,
                                      },
                                      'id = ?',
                                      [_details['id']],
                                      'transactions',
                                    );

                                    if (!mounted) return;

                                    showSuccessDialog(context,
                                        text: 'Category changed to $status');

                                    getStuff();
                                  }
                                },
                                Icon(
                                  Icons.satellite_alt_rounded,
                                  color: Theme.of(context)
                                      .tabBarTheme
                                      .indicatorColor,
                                  size: 14,
                                ),
                                "Change Category",
                                context,
                                textSize: 13,
                              ),
                            ],
                          ),

                          const SizedBox(height: kPagePadding),

                          // --- Reply Section ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'Reply',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: '${_details["ussdReply"]}',
                                        ),
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'USSD reply copied to clipboard'),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                          kPagePadding / 3),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    showFullReply = !showFullReply;
                                  });
                                },
                                icon: Icon(showFullReply
                                    ? Icons.expand_less
                                    : Icons.expand_more),
                              ),
                            ],
                          ),
                          Text(
                            '${_details["ussdReply"]}',
                            maxLines: showFullReply ? null : 1,
                          ),
                          const SizedBox(height: kPagePadding),

                          // --- MPESA Text Section ---
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  Text(
                                    'MPESA Text',
                                    style:
                                        TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  GestureDetector(
                                    onTap: () {
                                      Clipboard.setData(
                                        ClipboardData(
                                          text: '${_details["initialMessage"]}',
                                        ),
                                      );
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'MPESA text copied to clipboard'),
                                        ),
                                      );
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(
                                          kPagePadding / 3),
                                      child: Icon(
                                        Icons.copy_rounded,
                                        size: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    showFullMpesaMessage =
                                        !showFullMpesaMessage;
                                  });
                                },
                                icon: Icon(showFullMpesaMessage
                                    ? Icons.expand_less
                                    : Icons.expand_more),
                              ),
                            ],
                          ),
                          Text(
                            '${_details["initialMessage"]}',
                            maxLines: showFullMpesaMessage ? null : 1,
                          ),
                          const SizedBox(height: kPagePadding / 2),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              toolButton(
                                () async {
                                  int numb = toForward.isNotEmpty
                                      ? toForward[0]['numberToReceive']
                                      : 0;
                                  final currentContext = context;
                                  final navigator =
                                      Navigator.of(currentContext);
                                  String? number = (await showForwardTextDialog(
                                    currentContext,
                                    numb,
                                  ));

                                  if (number != null) {
                                    if (number.length < 10) return;
                                    if (number.length == 12) {
                                      number =
                                          number.substring(2, number.length);
                                    }

                                    sendEvenInBackground(
                                      '254${int.parse(number)}',
                                      _details['initialMessage'],
                                    );
                                    if (!mounted || !currentContext.mounted) {
                                      return;
                                    }
                                    navigator.pop(number);
                                  }

                                  await TransactionController().dontProcess(
                                      _details['initialMessage'],
                                      (_details['transactionId']),
                                      _details['number'],
                                      _details['ussdDialed'],
                                      _details['amount'],
                                      _details['simSubId'],
                                      status: TransactionStatuses.forwarded,
                                      source: _details['source'],
                                      canRetry: _details['canRetry'] == 1,
                                      reply: 'Forwarded to $numb');

                                  final dialogContext = currentContext;
                                  if (!mounted || !dialogContext.mounted) {
                                    return;
                                  }

                                  final shouldDelete =
                                      await showConfirmDeleteDialog(
                                    dialogContext,
                                    title: 'Delete Transaction?',
                                    message:
                                        'Do you want to delete this transaction? This cannot be undone.',
                                    btnText: 'Delete',
                                  );

                                  if (shouldDelete ?? false) {
                                    if (!mounted || !dialogContext.mounted) {
                                      return;
                                    }
                                    showLoadingDialog(dialogContext);
                                    await _sqliteService.deleteStuff(
                                      _details["id"],
                                      "transactions",
                                    );
                                    if (!mounted || !dialogContext.mounted) {
                                      return;
                                    }
                                    Navigator.pop(dialogContext);
                                    Navigator.pop(dialogContext);
                                  }
                                },
                                Icon(
                                  Icons.send_outlined,
                                  color: Theme.of(context).colorScheme.primary,
                                  size: 14,
                                ),
                                "Forward (Offline)",
                                context,
                                textSize: 13,
                              ),
                              toolButton(
                                () async {
                                  String? senderDeviceName =
                                      await SharedPreferencesService()
                                          .getDeviceName();
                                  final currentContext = context;
                                  final navigator =
                                      Navigator.of(currentContext);
                                  final device = await navigator.push(
                                      MaterialPageRoute(
                                          builder: (context) =>
                                              SearchDevicePage()));

                                  if (!mounted || !currentContext.mounted) {
                                    return;
                                  }

                                  if (device != null) {
                                    final confirmed = await showConfirmDialog(
                                      currentContext,
                                      title: 'Confirm Forwarding',
                                      message:
                                          'Do you want to forward this transaction to ${device['device_name']} ?',
                                    );

                                    if (confirmed ?? false) {
                                      showLoadingDialog(currentContext);
                                    } else {
                                      return;
                                    }

                                    String recipientDeviceName =
                                        device['device_name'];
                                    final forwardingJobId =
                                        ForwardingJobId.generate(
                                      mpesaCode:
                                          (_details['transactionId'] ?? '')
                                              .toString(),
                                    );

                                    int? txId = await TransactionController()
                                        .dontProcess(
                                      _details['initialMessage'],
                                      (_details['transactionId']),
                                      _details['number'],
                                      _details['ussdDialed'],
                                      _details['amount'],
                                      _details['simSubId'],
                                      status:
                                          TransactionStatuses.forwardedPending,
                                      source: _details['source'],
                                      forwardingJobId: forwardingJobId,
                                      canRetry: _details['canRetry'] == 1,
                                      reply:
                                          'Forwarding to ${device['device_name']}',
                                    );

                                    final result = await BackendService().post(
                                      '/api/fcm/send-secure',
                                      body: {
                                        'title': "BSAT Online Forwarding",
                                        'body': _details['initialMessage'],
                                        'senderDeviceName': senderDeviceName,
                                        'recipientDeviceName':
                                            recipientDeviceName,
                                        'data': {
                                          'type': 'forwarded_sms',
                                          'body': _details['initialMessage'],
                                          'transactionId': txId,
                                          'forwardingJobId': forwardingJobId,
                                          'forwardingStatus':
                                              ForwardingJobStatuses.pending,
                                          'title': "Forwarded Message",
                                          'senderDeviceName': senderDeviceName,
                                        }
                                      },
                                    );

                                    if (result['success'] != true) {
                                      await _sqliteService.updateStuff(
                                        {
                                          'status': TransactionStatuses.error,
                                          'ussdReply':
                                              'Forwarding failed: Phone offline or server not reachable. Will retry later.',
                                        },
                                        'id = ?',
                                        [txId],
                                        'transactions',
                                      );

                                      if (!context.mounted) return;

                                      await showSuccessDialog(
                                        context,
                                        text:
                                            'Forwarding failed. The transaction was kept for retry.',
                                      );

                                      if (!context.mounted) return;
                                      Navigator.pop(context);
                                      return;
                                    }

                                    if (!context.mounted) return;

                                    await showSuccessDialog(
                                      context,
                                      text:
                                          'Forwarded to ${device['device_name']}. Waiting for confirmation.',
                                    );

                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                  }
                                },
                                Icon(
                                  Icons.send_outlined,
                                  color: Theme.of(context).indicatorColor,
                                  size: 14,
                                ),
                                "Forward (Online)",
                                context,
                                textSize: 13,
                              ),
                              toolButton(
                                () async {
                                  await showSuccessDialog(context,
                                      text: "Forwarding to 334");
                                  await tillDoneDialogue(
                                      context, Text("Reversing message"),
                                      () async {
                                    String trimmedMessage =
                                        _details["initialMessage"]
                                                    .toString()
                                                    .length >
                                                160
                                            ? _details["initialMessage"]
                                                .toString()
                                                .substring(0, 160)
                                            : _details["initialMessage"]
                                                .toString();

                                    sendEvenInBackground('334', trimmedMessage);
                                  });
                                  return;
                                },
                                Icon(
                                  CupertinoIcons.exclamationmark_octagon,
                                  color: kErrorColor,
                                  size: 14,
                                ),
                                "Forward to 334",
                                context,
                                textSize: 13,
                              ),
                              toolButton(
                                () async {
                                  if ((await showConfirmDeleteDialog(
                                        context,
                                        title: 'Warning',
                                        message:
                                            'Are you sure you want to reverse this transaction?',
                                      ) ??
                                      false)) {
                                    if (!context.mounted) return;

                                    await tillDoneDialogue(
                                        context, Text("Reversing message"),
                                        () async {
                                      String trimmedMessage =
                                          _details["initialMessage"]
                                                      .toString()
                                                      .length >
                                                  160
                                              ? _details["initialMessage"]
                                                  .toString()
                                                  .substring(0, 160)
                                              : _details["initialMessage"]
                                                  .toString();

                                      sendEvenInBackground(
                                          '456', trimmedMessage);
                                    }).then((value) async {
                                      if (!context.mounted) return;

                                      if ((await showConfirmDeleteDialog(
                                            context,
                                            title: 'Done',
                                            message:
                                                'Delete this transaction too?',
                                            btnText: 'Delete',
                                          )) ??
                                          false) {
                                        if (!context.mounted) return;

                                        showLoadingDialog(context);
                                        await _sqliteService.deleteStuff(
                                          _details["id"],
                                          "transactions",
                                        );

                                        if (!context.mounted) return;

                                        if (Navigator.of(context).canPop()) {
                                          Navigator.pop(context);
                                          Navigator.pop(context);
                                        }
                                        showSuccessDialog(
                                          context,
                                          text: 'Transaction deleted',
                                        );
                                      }
                                      {}
                                    });
                                    return;
                                  }
                                },
                                Icon(
                                  CupertinoIcons.exclamationmark_octagon,
                                  color: kErrorColor,
                                  size: 14,
                                ),
                                "Reverse message",
                                context,
                                textSize: 13,
                              ),
                            ],
                          ),
                          const SizedBox(height: kPagePadding),

                          const Divider(height: 1),
                          const SizedBox(height: kPagePadding),

                          // --- Global Action Section ---
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              toolButton(
                                () async {
                                  showLoadingDialog(context);

                                  await _sqliteService.deleteStuff(
                                    _details["id"],
                                    "transactions",
                                  );

                                  if (!context.mounted) return;

                                  Navigator.pop(context);
                                  Navigator.pop(context);
                                },
                                Icon(
                                  CupertinoIcons.trash,
                                  color: kErrorColor,
                                  size: 14,
                                ),
                                "Delete Transaction",
                                context,
                                textSize: 13,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: _buildEdgeNavButton(
                    context: context,
                    label: '',
                    icon: CupertinoIcons.chevron_left,
                    enabled: _previousTransactionId != null,
                    onPressed: () => _openAdjacentTransaction(
                      _previousTransactionId,
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: _buildEdgeNavButton(
                    context: context,
                    label: '',
                    icon: CupertinoIcons.chevron_right,
                    enabled: _nextTransactionId != null,
                    onPressed: () => _openAdjacentTransaction(
                      _nextTransactionId,
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

  Future<void> _openAdjacentTransaction(int? id) async {
    if (id == null) return;
    await Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => SingleTransactionPage(id: id),
      ),
    );
  }

  Widget _buildEdgeNavButton({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool enabled,
    required VoidCallback onPressed,
  }) {
    final color = enabled ? kPrimaryColor : Colors.white38;

    return InkWell(
      onTap: enabled ? onPressed : null,
      borderRadius: BorderRadius.circular(kBorderRadius),
      child: Container(
        // height: 100,100
        // width: 106,
        padding: const EdgeInsets.all(
          kPagePadding / 3,
          // vertical: kPagePadding,
        ),
        decoration: BoxDecoration(
          // color: Theme.of(context).cardColor.withValues(alpha: 0.92),
          // borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: enabled
                ? kPrimaryColor.withValues(alpha: 0.45)
                : Colors.white24,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            // const SizedBox(height: 4),
            // Text(
            //   label,
            //   textAlign: TextAlign.center,
            //   style: TextStyle(
            //     color: color,
            //     fontSize: 12,
            //     fontWeight: FontWeight.bold,
            //   ),
            // ),
          ],
        ),
      ),
    );
  }
}
