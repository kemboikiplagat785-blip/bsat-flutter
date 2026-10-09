import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:another_telephony/telephony.dart';
import 'package:bsat/models/transaction.dart';
import 'package:bsat/services/auth_service.dart';
import 'package:bsat/services/backend_service.dart';
import 'package:bsat/services/contacts_service.dart';
import 'package:bsat/services/payments.dart';
import 'package:bsat/services/sqlite_service.dart';
import 'package:bsat/utils/constants.dart';
import 'package:bsat/utils/date_ops.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_background_service/flutter_background_service.dart';

import '../models/client.dart';
import '../models/code_signature.dart';
import '../models/transaction_message.dart';
import '../models/ussd_code.dart';
import '../services/client_service.dart';
import '../services/shared_preferences_service.dart';
import '../utils/forwarding_job_id.dart';
import '../utils/top_up.dart';

// import '../services/skills.dart';
import '../services/skills.dart';
import '../services/sms_sevice.dart';
import '../services/phone_service.dart';
import '../services/main_engine_ussd_bridge.dart';

enum ForwardingAttemptState {
  noConfiguration,
  configuredButUnavailable,
  configuredButPaused,
  forwardedSuccessfully,
}

class ForwardingAttemptResult {
  final ForwardingAttemptState state;
  final int? transactionId;

  const ForwardingAttemptResult(this.state, {this.transactionId});
}

/// Orchestrates the full M-PESA → offer → USSD → transaction lifecycle.
/// Entry point is [makeTransaction], which parses inbound SMS, applies
/// business rules (blacklist, forwarding, subscription/tokens, offer state),
/// dials the mapped USSD (advanced or normal), records outcomes to SQLite,
/// and emits replies/side effects (auto-save contacts, send confirmations).
class TransactionController {
  static Timer? _forwardingConfirmationTimer;
  static final Set<String> _activeTopUpTransactionCodes = <String>{};
  static final Set<int> _activePausedOfferResumes = <int>{};
  static final Set<int> _activePausedForwardingResumes = <int>{};
  static final Set<String> _activeForwardedSmsJobs = <String>{};
  static const String _pausedOfferResumeClaimPrefix =
      '__BSAT_PAUSED_OFFER_RESUME__:';
  static const String _pausedOfferLocalExecutionClaim =
      '__BSAT_PAUSED_OFFER_LOCAL_EXECUTION__';
  static const String _pausedForwardingReply =
      'Paired device forwarding is configured but currently on pause. '
      'Will retry after initiation play';
  static const Duration _pausedOfferResumeClaimLease = Duration(seconds: 60);
  final PhoneService _phoneService = PhoneService();
  final SQLiteService _sqliteService = SQLiteService();
  final _paymentOps = PaymentOps();

  final _sharedPreferencesService = SharedPreferencesService();

  TransactionController() {
    _forwardingConfirmationTimer ??= Timer.periodic(
      const Duration(seconds: 15),
      (_) => _retryPendingForwardingConfirmations(),
    );
  }

  Future<void> _retryPendingForwardingConfirmations() async {
    final due = await _sqliteService
        .dueForwardingConfirmations(DateTime.now().millisecondsSinceEpoch);

    for (final row in due) {
      final forwardingJobId = (row['forwardingJobId'] ?? '').toString();
      final recipientDeviceName = (row['recipientDeviceName'] ?? '').toString();
      final transactionId = row['transactionId']?.toString();
      final attempt = int.tryParse(row['attempt']?.toString() ?? '') ?? 1;

      if (forwardingJobId.isEmpty || recipientDeviceName.isEmpty) {
        continue;
      }

      await _deliverForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: recipientDeviceName,
        transactionId: transactionId,
        attempt: attempt,
        resultStatus: row['resultStatus']?.toString() ??
            TransactionStatuses.doneConfirmed,
        requiredTopUp: int.tryParse(row['requiredTopUp']?.toString() ?? ''),
        targetAmount: int.tryParse(row['targetAmount']?.toString() ?? ''),
      );
    }
  }

  /// Process a single payment SMS into a transaction.
  /// Steps (in order):
  /// 1) Housekeeping: optional auto-delete old transactions, trim SMS body.
  /// 2) Parse primitives: id, number, amount, name; blacklist check.
  /// 3) Forwarding: reroute if forwarding rules match (returns early).
  /// 4) Offer safety: pause if offers flagged as changed; reject invalid numbers/Airtel.
  /// 5) Resolve offer: pick USSD + SIM + retry/advanced flags; check subscription/token/auto-renew.
  /// 6) Compound amounts: attempt to combine smaller offers if exact match missing.
  /// 7) Guardrails: pause inactive offers; enqueue advanced calls if app inactive.
  /// 8) Execute USSD: advanced or standard dial; derive transaction status.
  /// 9) Persist result to SQLite, emit replies, and auto-save contact when enabled.
  ///
  Future<void> _sendForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
    String resultStatus = TransactionStatuses.doneConfirmed,
    int? requiredTopUp,
    int? targetAmount,
  }) async {
    await _sqliteService.queueForwardingConfirmation(
      forwardingJobId: forwardingJobId,
      recipientDeviceName: recipientDeviceName,
      transactionId: transactionId,
      resultStatus: resultStatus,
      requiredTopUp: requiredTopUp,
      targetAmount: targetAmount,
    );
    await _deliverForwardingConfirmation(
      forwardingJobId: forwardingJobId,
      recipientDeviceName: recipientDeviceName,
      transactionId: transactionId,
      attempt: 1,
      resultStatus: resultStatus,
      requiredTopUp: requiredTopUp,
      targetAmount: targetAmount,
    );
  }

  Future<void> _deliverForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
    required int attempt,
    required String resultStatus,
    int? requiredTopUp,
    int? targetAmount,
  }) async {
    final senderDeviceName =
        await SharedPreferencesService().getDeviceName() ?? '';

    if (senderDeviceName.isEmpty || recipientDeviceName.isEmpty) {
      debugPrint(
        'FORWARDED_SMS CONFIRMATION: '
        'Missing sender/recipient device name. '
        'sender=$senderDeviceName, recipient=$recipientDeviceName',
      );
      await _sqliteService.scheduleForwardingConfirmationRetry(
        forwardingJobId,
        attempt: attempt,
        nextAttemptAt: DateTime.now()
            .add(const Duration(minutes: 5))
            .millisecondsSinceEpoch,
      );
      return;
    }

    try {
      final result = await BackendService().post(
        '/api/fcm/send-secure',
        body: {
          'title': 'BSAT Online Forwarding',
          'body': 'Forwarded transaction confirmed',
          'senderDeviceName': senderDeviceName,
          'recipientDeviceName': recipientDeviceName,
          'data': {
            'type': 'forwarded_sms_ack',
            'ackKind': 'confirmed',
            'status': TransactionStatuses.doneConfirmed,
            'resultStatus': resultStatus,
            if (requiredTopUp != null) 'requiredTopUp': requiredTopUp,
            if (targetAmount != null) 'targetAmount': targetAmount,
            'forwardingJobId': forwardingJobId,
            'transactionId': transactionId ?? '',
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': recipientDeviceName,
          },
        },
      );

      debugPrint(
        'FORWARDED_SMS CONFIRMATION SENT: '
        'jobId=$forwardingJobId, '
        'from=$senderDeviceName, '
        'to=$recipientDeviceName, '
        'result=$result',
      );
    } catch (e) {
      debugPrint(
        'FORWARDED_SMS CONFIRMATION FAILED: $e',
      );
    }

    const retrySeconds = [5, 15, 30, 60, 120, 300];
    final delaySeconds =
        retrySeconds[(attempt - 1).clamp(0, retrySeconds.length - 1).toInt()];
    await _sqliteService.scheduleForwardingConfirmationRetry(
      forwardingJobId,
      attempt: attempt,
      nextAttemptAt: DateTime.now()
          .add(Duration(seconds: delaySeconds))
          .millisecondsSinceEpoch,
    );
  }

// ADD THIS NEW PUBLIC METHOD HERE
  Future<void> sendForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
    String resultStatus = TransactionStatuses.doneConfirmed,
    int? requiredTopUp,
    int? targetAmount,
  }) async {
    await _sendForwardingConfirmation(
      forwardingJobId: forwardingJobId,
      recipientDeviceName: recipientDeviceName,
      transactionId: transactionId,
      resultStatus: resultStatus,
      requiredTopUp: requiredTopUp,
      targetAmount: targetAmount,
    );
  }

  Future<void> ensureForwardingConfirmation({
    required String forwardingJobId,
    required String recipientDeviceName,
    String? transactionId,
  }) async {
    final inserted = await _sqliteService.queueForwardingConfirmationIfAbsent(
      forwardingJobId: forwardingJobId,
      recipientDeviceName: recipientDeviceName,
      transactionId: transactionId,
    );
    if (!inserted) return;
    await _deliverForwardingConfirmation(
      forwardingJobId: forwardingJobId,
      recipientDeviceName: recipientDeviceName,
      transactionId: transactionId,
      attempt: 1,
      resultStatus: TransactionStatuses.doneConfirmed,
    );
  }

  Future<void> _sendForwardedAlternativeResult({
    required String forwardingJobId,
    required String recipientDeviceName,
    required String transactionId,
    required String status,
    required String ussdReply,
  }) async {
    final senderDeviceName =
        await SharedPreferencesService().getDeviceName() ?? '';
    if (senderDeviceName.isEmpty || recipientDeviceName.isEmpty) {
      debugPrint(
        'ALT RESULT: cannot send jobId=$forwardingJobId; '
        'sender or recipient device name is missing',
      );
      return;
    }

    debugPrint(
      'ALT RESULT: sending status=$status jobId=$forwardingJobId '
      'transactionId=$transactionId to $recipientDeviceName',
    );
    try {
      final result = await BackendService().post(
        '/api/fcm/send-secure',
        body: {
          'title': 'BSAT Online Forwarding',
          'body': 'Alternative USSD result',
          'senderDeviceName': senderDeviceName,
          'recipientDeviceName': recipientDeviceName,
          'data': {
            'type': 'forwarded_alt_result',
            'transactionId': transactionId,
            'forwardingJobId': forwardingJobId,
            'status': status,
            'ussdReply': ussdReply,
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': recipientDeviceName,
          },
        },
      );
      debugPrint(
        'ALT RESULT: sent jobId=$forwardingJobId '
        'transactionId=$transactionId result=$result',
      );
    } catch (e) {
      debugPrint('ALT RESULT: failed jobId=$forwardingJobId: $e');
    }
  }

  Future<void> _queueForwardedAlternativeResult({
    required String forwardingJobId,
    required String state,
    required String status,
    required String transactionId,
    required String ussdReply,
    bool replaceDeliveredResult = false,
  }) async {
    final job = await _sqliteService.getAlternativeJob(forwardingJobId);
    if (job == null) return;
    if (job['resultDeliveryState'] == 'delivered' &&
        !replaceDeliveredResult) {
      return;
    }

    await _sqliteService.updateAlternativeJob(
      forwardingJobId,
      {
        'state': state,
        'localTransactionId': int.tryParse(transactionId),
        'resultStatus': status,
        'ussdReply': ussdReply,
        'resultDeliveryState': 'pending',
        'resultNextAttemptAt': 0,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
    );
    await _retryPendingForwardedAlternativeResults(
      forwardingJobId: forwardingJobId,
    );
  }

  Future<void> _retryPendingForwardedAlternativeResults({
    String? forwardingJobId,
  }) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rows = await _sqliteService.queryCustom(
      'alternativeJobs',
      '${forwardingJobId == null ? '' : 'forwardingJobId = ? AND '}'
          'resultDeliveryState = ? AND resultNextAttemptAt <= ?',
      [
        if (forwardingJobId != null) forwardingJobId,
        'pending',
        now,
      ],
    );

    for (final job in rows) {
      final jobId = job['forwardingJobId']?.toString() ?? '';
      if (jobId.isEmpty) continue;
      final attempt =
          (int.tryParse(job['resultAttempt']?.toString() ?? '') ?? 0) + 1;
      final claimed = await _sqliteService.claimAlternativeResultDelivery(
        forwardingJobId: jobId,
        now: now,
        nextAttemptAt: now + const Duration(seconds: 20).inMilliseconds,
        attempt: attempt,
      );
      if (claimed != 1) continue;

      await _sendForwardedAlternativeResult(
        forwardingJobId: jobId,
        recipientDeviceName: job['senderDeviceName']?.toString() ?? '',
        transactionId: job['transactionId']?.toString() ?? '',
        status: job['resultStatus']?.toString() ?? '',
        ussdReply: job['ussdReply']?.toString() ?? '',
      );
    }
  }

  Future<bool> _completeForwardedAlternativeJobFromConfirmation({
    required String forwardingJobId,
    required String transactionId,
    required String ussdReply,
  }) async {
    final job = await _sqliteService.getAlternativeJob(forwardingJobId);
    if (job == null) return false;

    final resolvedAmbiguity = job['state'] == 'ambiguous' ||
        job['resultStatus'] == TransactionStatuses.alternativeAmbiguous;
    final replacesPendingResult =
        job['resultStatus'] == TransactionStatuses.successfulPending;
    final firstResultAwaitingAck =
        replacesPendingResult && job['resultDeliveryState'] != 'delivered';
    final updated = await _sqliteService.updateAlternativeJob(
      forwardingJobId,
      {
        'state': 'completed',
        'localTransactionId': int.tryParse(transactionId),
        if (!firstResultAwaitingAck)
          'resultStatus': TransactionStatuses.doneConfirmed,
        if (!firstResultAwaitingAck) 'ussdReply': ussdReply,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      expectedState: resolvedAmbiguity ? 'ambiguous' : null,
    );
    if (updated != 1) return false;
    if (firstResultAwaitingAck) {
      debugPrint(
        'ALT_QUEUE: final confirmation recorded for $forwardingJobId; '
        'waiting for first-success result receipt before sending final result',
      );
      return true;
    }
    await _queueForwardedAlternativeResult(
      forwardingJobId: forwardingJobId,
      state: 'completed',
      status: TransactionStatuses.doneConfirmed,
      transactionId: transactionId,
      ussdReply: ussdReply,
      replaceDeliveredResult: resolvedAmbiguity || replacesPendingResult,
    );
    debugPrint(
      'ALT DELIVERY RESULT: job=$forwardingJobId, transaction=$transactionId',
    );
    return true;
  }

  Future<void> completeForwardedAlternativeResultAcknowledgement(
    String forwardingJobId,
  ) async {
    final job = await _sqliteService.getAlternativeJob(forwardingJobId);
    if (job == null ||
        job['state'] != 'completed' ||
        job['resultStatus'] != TransactionStatuses.successfulPending) {
      return;
    }
    final localTransactionId =
        int.tryParse(job['localTransactionId']?.toString() ?? '');
    if (localTransactionId == null) return;
    final transactionRows = await _sqliteService.queryCustom(
      'transactions',
      'id = ? AND forwardingJobId = ? AND status = ?',
      [
        localTransactionId,
        forwardingJobId,
        TransactionStatuses.doneConfirmed,
      ],
      columns: ['ussdReply'],
      limit: 1,
    );
    if (transactionRows.isEmpty) return;
    await _queueForwardedAlternativeResult(
      forwardingJobId: forwardingJobId,
      state: 'completed',
      status: TransactionStatuses.doneConfirmed,
      transactionId: localTransactionId.toString(),
      ussdReply: transactionRows.first['ussdReply']?.toString() ?? '',
      replaceDeliveredResult: true,
    );
  }

  Future<void> _reportForwardedAlternativeFirstSuccess({
    required String forwardingJobId,
    required String transactionId,
    required String ussdReply,
  }) async {
    final job = await _sqliteService.getAlternativeJob(forwardingJobId);
    if (job == null) {
      return;
    }
    if (job['state'] == 'completed') {
      if (job['resultStatus'] == TransactionStatuses.successfulPending) {
        await _retryPendingForwardedAlternativeResults(
          forwardingJobId: forwardingJobId,
        );
      }
      return;
    }
    if (job['resultStatus'] == TransactionStatuses.doneConfirmed) return;
    debugPrint(
      'ALT_QUEUE: $forwardingJobId first-success detected; '
      'transaction=$transactionId',
    );
    await _queueForwardedAlternativeResult(
      forwardingJobId: forwardingJobId,
      state: 'awaiting_confirmation',
      status: TransactionStatuses.successfulPending,
      transactionId: transactionId,
      ussdReply: ussdReply,
    );
  }

  Future<void> _recoverSuccessfulPendingAlternativeResults() async {
    final rows = await _sqliteService.queryCustom(
      'transactions',
      'status = ? AND source = ? AND forwardingJobId IS NOT NULL '
          'AND forwardingJobId != ?',
      [
        TransactionStatuses.successfulPending,
        'manual',
        '',
      ],
      columns: ['id', 'forwardingJobId', 'ussdReply'],
    );
    for (final row in rows) {
      final forwardingJobId = row['forwardingJobId']?.toString() ?? '';
      final job = await _sqliteService.getAlternativeJob(forwardingJobId);
      if (job == null ||
          job['resultStatus'] == TransactionStatuses.doneConfirmed) {
        continue;
      }
      if (job['resultStatus'] != TransactionStatuses.successfulPending) {
        await _reportForwardedAlternativeFirstSuccess(
          forwardingJobId: forwardingJobId,
          transactionId: row['id']?.toString() ?? '',
          ussdReply: row['ussdReply']?.toString() ?? '',
        );
      }
    }
  }

  Future<bool> _completeAmbiguousAlternativeFromConfirmation({
    required String recipientNumber,
    required int? confirmationAmount,
    required int smsTimestamp,
    required String confirmationBody,
  }) async {
    if (!RegExp(r'^0\d{9}$').hasMatch(recipientNumber) ||
        confirmationAmount == null) {
      return false;
    }

    final jobs = await _sqliteService.getAlternativeJobsByState('ambiguous');
    final candidates = <Map<String, dynamic>>[];
    for (final job in jobs) {
      if (job['resultStatus'] != TransactionStatuses.alternativeAmbiguous) {
        continue;
      }
      final executionStartedAt =
          int.tryParse(job['executionStartedAt']?.toString() ?? '');
      if (executionStartedAt == null ||
          (executionStartedAt - smsTimestamp).abs() > 20 * 60 * 1000) {
        continue;
      }
      final expectedAmount = getAmount(job['smsMessage']?.toString() ?? '');
      if (expectedAmount != confirmationAmount) continue;

      final expectedNumber =
          extract9DigitNumber(job['smsMessage']?.toString() ?? '');
      if (expectedNumber <= 0) continue;
      var normalizedExpected = normalizeIncomingCallNumber(
        expectedNumber.toString().padLeft(9, '0'),
      );
      if (normalizedExpected.length == 9) {
        normalizedExpected = '0$normalizedExpected';
      }
      if (normalizedExpected != recipientNumber) continue;
      candidates.add(job);
    }

    if (candidates.length != 1) {
      debugPrint(
        'AMBIGUOUS ALT CONFIRMATION: exact recipient/amount/time match '
        'count=${candidates.length}; leaving unresolved',
      );
      return false;
    }

    final job = candidates.single;
    final forwardingJobId = job['forwardingJobId']?.toString() ?? '';
    if (forwardingJobId.isEmpty) return false;
    final completed = await _completeForwardedAlternativeJobFromConfirmation(
      forwardingJobId: forwardingJobId,
      transactionId: job['transactionId']?.toString() ?? '',
      ussdReply: confirmationBody,
    );
    if (completed) {
      debugPrint(
        'AMBIGUOUS ALT CONFIRMATION matched safely: '
        'job=$forwardingJobId, recipient=$recipientNumber, '
        'amount=$confirmationAmount',
      );
    }
    return completed;
  }

// YOUR EXISTING METHOD STAYS EXACTLY THE SAME
  Future<int?> makeTransactionGivenSmsBody(
    String smsBody, {
    String? address,
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
    int? parentTransactionId,
  }) async {
    final jobId = forwardingJobId?.trim() ?? '';
    if (jobId.isNotEmpty) {
      if (!_activeForwardedSmsJobs.add(jobId)) {
        final existing = await _sqliteService.queryCustom(
          'transactions',
          'forwardingJobId = ?',
          [jobId],
          columns: ['id'],
          limit: 1,
        );
        return int.tryParse(existing.firstOrNull?['id']?.toString() ?? '');
      }
      try {
        final existing = await _sqliteService.queryCustom(
          'transactions',
          'forwardingJobId = ?',
          [jobId],
          limit: 1,
        );
        if (existing.isNotEmpty) {
          final transaction = existing.first;
          if (transaction['status'] == TransactionStatuses.doneConfirmed) {
            final sender =
                transaction['forwardingSenderDeviceName']?.toString() ?? '';
            if (sender.isNotEmpty) {
              await sendForwardingConfirmation(
                forwardingJobId: jobId,
                recipientDeviceName: sender,
                transactionId: transaction['id']?.toString(),
              );
            }
          }
          return int.tryParse(transaction['id']?.toString() ?? '');
        }
        return await _makeTransactionFromSmsBody(
          smsBody,
          address: address,
          forwardingJobId: forwardingJobId,
          forwardingSenderDeviceName: forwardingSenderDeviceName,
          parentTransactionId: parentTransactionId,
        );
      } finally {
        _activeForwardedSmsJobs.remove(jobId);
      }
    }
    return _makeTransactionFromSmsBody(
      smsBody,
      address: address,
      forwardingJobId: forwardingJobId,
      forwardingSenderDeviceName: forwardingSenderDeviceName,
      parentTransactionId: parentTransactionId,
    );
  }

  Future<int?> _makeTransactionFromSmsBody(
    String smsBody, {
    String? address,
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
    int? parentTransactionId,
  }) async {
    TransactionMessage fakeMessage = TransactionMessage(
      body: smsBody,
      date: DateTime.now().millisecondsSinceEpoch,
      address: address,
    );

    return await makeTransaction(
      fakeMessage,
      forwardingJobId: forwardingJobId,
      forwardingSenderDeviceName: forwardingSenderDeviceName,
      parentTransactionId: parentTransactionId,
    );
  }

  Future<int?> makeTransaction(
    TransactionMessage smsMessage, {
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
    int? parentTransactionId,
  }) async {
    // if (DateTime.now().millisecondsSinceEpoch > 1772303182000) return;

    bool autoSaveContacts =
        await _sharedPreferencesService.getAutoSaveContacts() ?? false;

    var contactService = ContactsService();

    int lastValidTimestampForDeletion =
        (await _sharedPreferencesService.getAutoDeleteAfterNumberOfDays() ??
                0) *
            86400000;

    if (lastValidTimestampForDeletion > 0) {
      int threshold =
          DateTime.now().millisecondsSinceEpoch - lastValidTimestampForDeletion;
      await _sqliteService
          .deleteWhere('transactions', 'timeStamp < ?', [threshold]);
    }

    bool isUsingToken = false;

    String mpesaCode = getMpesaCode(smsMessage.body ?? "");
    int number = extract9DigitNumber(smsMessage.body ?? "");
    int amount = getAmount(smsMessage.body);
    String name = getName(smsMessage.body ?? "");

    Client client = Client.fromMpesaMessage(smsMessage.body ?? "");

    // print(number);

    String trimmedBody = smsMessage.body!.length > 160
        ? smsMessage.body!.substring(0, 160)
        : smsMessage.body!;

    if (number == 0 || client.formattedPhone.length < 9) {
      var client1 = await getMaskedPhoneNumber(smsMessage);
      // print(
      // "Client from masked number: ${client?.fullName}, ${client?.formattedPhone}");
      // print(client?.formattedPhone == null);
      if (client1?.formattedPhone != null) {
        number = int.parse(client1?.formattedPhone ?? "0");
        smsMessage = TransactionMessage(
          body: unmaskNumberInMessage(
              client1?.formattedPhone ?? "0", smsMessage.body ?? ""),
          subscriptionId: smsMessage.subscriptionId,
          date: smsMessage.date,
        );

        client = client1!;
      } else {
        if ((await _sharedPreferencesService.getForwardMaskedMessages() ??
                false) &&
            smsMessage.body != null) {
          final forwardingResult = await forwardIfNeeded(
            amount,
            trimmedBody,
            smsMessage.body ?? "",
            mpesaCode,
            number,
            name,
            autoSaveContacts,
            status: TransactionStatuses.forwarded,
          );
          if (forwardingResult.state ==
                  ForwardingAttemptState.configuredButUnavailable ||
              forwardingResult.state ==
                  ForwardingAttemptState.configuredButPaused) {
            return _persistUnavailableForwardingTransaction(
              initialMessage: smsMessage.body ?? '',
              transactionCode: mpesaCode,
              number: number,
              amount: amount,
              source: name,
              destinationPaused: forwardingResult.state ==
                  ForwardingAttemptState.configuredButPaused,
            );
          }
          return forwardingResult.transactionId;
        } else {
          if (smsMessage.address == "MPESA" &&
              smsMessage.body!.contains("***")) {
            sendEvenInBackground('334', smsMessage.body ?? "",
                sendFirstPartOnly: true);
          }

          return await dontProcess(
            smsMessage.body ?? "",
            mpesaCode,
            number,
            '',
            amount,
            -1,
            status: TransactionStatuses.masked,
            reply: 'Could not extract a valid phone number from the message.',
            canRetry: false,
            source: name,
          );
        }
      }
    }

    await ClientService().insertClient(client);

    UssdCode ussdCodeItem = await getUssdCodeForAmount(amount);

    bool blacklistExists = await numberIsBlacklisted(number);

    if (blacklistExists) {
      processReply(
        number,
        TransactionStatuses.blacklisted,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      if (autoSaveContacts) {
        await contactService.addNewContact(
          name,
          '0$number',
        );
      }

      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        '',
        amount,
        -1,
        status: TransactionStatuses.blacklisted,
        reply: 'Number is blacklisted',
        canRetry: false,
        source: name,
      );
    }

    // Match only by customer, exact required amount, and persisted awaiting
    // state. If two rows qualify, leave this payment to the normal pipeline.
    final topUpCandidates = parentTransactionId == null
        ? await _sqliteService.queryCustom(
            'transactions',
            'number = ? AND requiredTopUp = ? AND awaitingTopUp = 1 AND '
                'status IN (?, ?)',
            [
              number,
              amount,
              TransactionStatuses.unavailableOffer,
              TransactionStatuses.forwardedPending,
            ],
          )
        : <Map<String, dynamic>>[];
    final matchingTopUpCandidates = topUpCandidates.where((candidate) {
      final candidateNumber =
          int.tryParse(candidate['number']?.toString() ?? '');
      final candidateRequiredTopUp =
          int.tryParse(candidate['requiredTopUp']?.toString() ?? '');
      return candidateNumber != null &&
          candidateRequiredTopUp != null &&
          matchesTopUpPayment(
            expectedCustomerNumber: candidateNumber,
            paymentCustomerNumber: number,
            requiredTopUp: candidateRequiredTopUp,
            paymentAmount: amount,
          );
    }).toList();
    if (parentTransactionId == null) {
      final claimedTopUpRows = await _sqliteService.queryCustom(
        'transactions',
        'number = ? AND topUpTransactionId = ?',
        [number, mpesaCode],
        columns: ['id'],
        limit: 1,
      );
      if (claimedTopUpRows.isNotEmpty) {
        final claimedParentId =
            int.tryParse(claimedTopUpRows.first['id']?.toString() ?? '');
        if (claimedParentId != null) {
          final claimedChild = await _sqliteService.queryCustom(
            'transactions',
            'parentTransactionId = ?',
            [claimedParentId],
            columns: ['id'],
            limit: 1,
          );
          if (claimedChild.isNotEmpty) {
            return int.tryParse(claimedChild.first['id']?.toString() ?? '');
          }
          if (_activeTopUpTransactionCodes.contains(mpesaCode)) return null;
          final parentRows = await _sqliteService.queryCustom(
            'transactions',
            'id = ?',
            [claimedParentId],
            columns: ['targetAmount'],
            limit: 1,
          );
          final claimedTarget = parentRows.isEmpty
              ? null
              : int.tryParse(
                  parentRows.first['targetAmount']?.toString() ?? '');
          if (claimedTarget != null) {
            _activeTopUpTransactionCodes.add(mpesaCode);
            try {
              return await makeTransactionGivenSmsBody(
                alterMpesaMessage(smsMessage.body ?? '', claimedTarget),
                address: smsMessage.address,
                parentTransactionId: claimedParentId,
              );
            } finally {
              _activeTopUpTransactionCodes.remove(mpesaCode);
            }
          }
          return null;
        }
      }
    }
    if (matchingTopUpCandidates.length == 1) {
      final original = matchingTopUpCandidates.single;
      final originalId = int.tryParse(original['id'].toString());
      final targetAmount =
          int.tryParse(original['targetAmount']?.toString() ?? '');
      if (originalId != null &&
          targetAmount != null &&
          targetAmount ==
              combinedTransactionAmount(
                int.tryParse(original['amount']?.toString() ?? '') ?? 0,
                amount,
              )) {
        final claimed = await _sqliteService.updateStuff(
          {'awaitingTopUp': 0, 'topUpTransactionId': mpesaCode},
          'id = ? AND awaitingTopUp = 1',
          [originalId],
          'transactions',
        );
        if (claimed == 1) {
          if (_activeTopUpTransactionCodes.contains(mpesaCode)) return null;
          _activeTopUpTransactionCodes.add(mpesaCode);
          final existingCombined = await _sqliteService.queryCustom(
            'transactions',
            'parentTransactionId = ?',
            [originalId],
            columns: ['id'],
            limit: 1,
          );
          if (existingCombined.isNotEmpty) {
            _activeTopUpTransactionCodes.remove(mpesaCode);
            return int.tryParse(existingCombined.first['id'].toString());
          }

          final combinedSms = alterMpesaMessage(
            smsMessage.body ?? '',
            combinedTransactionAmount(
              int.tryParse(original['amount']?.toString() ?? '') ?? 0,
              amount,
            ),
          );
          try {
            int? combinedId = await makeTransactionGivenSmsBody(
              combinedSms,
              address: smsMessage.address,
              parentTransactionId: originalId,
            );
            if (combinedId == null) {
              final forwardedRows = await _sqliteService.queryCustom(
                'transactions',
                'parentTransactionId = ?',
                [originalId],
                columns: ['id'],
                orderBy: 'id DESC',
                limit: 1,
              );
              if (forwardedRows.isNotEmpty) {
                combinedId =
                    int.tryParse(forwardedRows.first['id']?.toString() ?? '');
              }
            }
            if (combinedId == null) {
              await _sqliteService.updateStuff(
                {'awaitingTopUp': 1, 'topUpTransactionId': null},
                'id = ? AND forwardingJobId IS NULL',
                [originalId],
                'transactions',
              );
              return null;
            }

            final combinedRows = await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [combinedId],
              columns: [
                'forwardingJobId',
                'forwardingSenderDeviceName',
                'forwardingRecipientDeviceName',
                'status',
              ],
              limit: 1,
            );
            if (combinedRows.isNotEmpty &&
                (combinedRows.first['forwardingJobId']?.toString().isNotEmpty ??
                    false)) {
              await _sqliteService.updateStuff(
                {
                  'forwardingJobId': combinedRows.first['forwardingJobId'],
                  'forwardingSenderDeviceName':
                      combinedRows.first['forwardingSenderDeviceName'],
                  'forwardingRecipientDeviceName':
                      combinedRows.first['forwardingRecipientDeviceName'],
                },
                'id = ?',
                [originalId],
                'transactions',
              );
            }
            return combinedId;
          } catch (_) {
            await _sqliteService.updateStuff(
              {'awaitingTopUp': 1, 'topUpTransactionId': null},
              'id = ? AND forwardingJobId IS NULL',
              [originalId],
              'transactions',
            );
            rethrow;
          } finally {
            _activeTopUpTransactionCodes.remove(mpesaCode);
          }
        }
      }
    }

    List<dynamic>? historicalCompound;
    if (number >= 100000000 &&
        !(smsMessage.body ?? '')
            .contains(RegExp('airtel money', caseSensitive: false))) {
      historicalCompound = await unavailableAmountCanCompound(amount, number);
      if (historicalCompound[3] &&
          historicalCompound.length > 7 &&
          historicalCompound[7] == true) {
        final finalAmount = int.tryParse(historicalCompound[6].toString());
        if (finalAmount != null) {
          final previousAmount = finalAmount - amount;
          debugPrint(
            'COMPOUND FORWARDING: currentAmount=$amount '
            'previousAmount=$previousAmount finalAmount=$finalAmount',
          );

          final compoundMessage = alterMpesaMessage(
            smsMessage.body ?? '',
            finalAmount,
          );
          final configuredDevices =
              (await _sqliteService.queryAll('forwardingDevices')).where(
            (device) {
              final amounts = (device['amounts_to_forward']?.toString() ?? '')
                  .replaceAll(RegExp(r'[\[\]"]'), '')
                  .split(',')
                  .map((value) => value.trim());
              return amounts.contains('$finalAmount');
            },
          );
          final deviceNames = configuredDevices
              .map((device) => device['device_name']?.toString() ?? '')
              .where((deviceName) => deviceName.isNotEmpty)
              .join(',');

          final compoundForwardingResult = await forwardIfNeeded(
            finalAmount,
            compoundMessage.length > 160
                ? compoundMessage.substring(0, 160)
                : compoundMessage,
            compoundMessage,
            mpesaCode,
            number,
            name,
            autoSaveContacts,
            parentTransactionId: parentTransactionId,
          );
          debugPrint(
            'COMPOUND FORWARDING ROUTE: amount=$finalAmount '
            'configured=${compoundForwardingResult.state != ForwardingAttemptState.noConfiguration} '
            'device=${deviceNames.isEmpty ? 'none' : deviceNames}',
          );

          if (compoundForwardingResult.state ==
              ForwardingAttemptState.forwardedSuccessfully) {
            debugPrint(
              'COMPOUND FORWARDING: second SMS edited from $amount to '
              '$finalAmount and forwarded directly',
            );
            return compoundForwardingResult.transactionId;
          }
          if (compoundForwardingResult.state ==
                  ForwardingAttemptState.configuredButUnavailable ||
              compoundForwardingResult.state ==
                  ForwardingAttemptState.configuredButPaused) {
            return _persistUnavailableForwardingTransaction(
              initialMessage: compoundMessage,
              transactionCode: mpesaCode,
              number: number,
              amount: finalAmount,
              source: name,
              parentTransactionId: parentTransactionId,
              destinationPaused: compoundForwardingResult.state ==
                  ForwardingAttemptState.configuredButPaused,
            );
          }
        }
      }

      final matchingOffer = await _findMatchingUssdCode(
        amount,
        smsMessage.subscriptionId ?? 0,
      );
      final offerId = int.tryParse(matchingOffer?['id']?.toString() ?? '');
      final offerEnabled = matchingOffer == null ||
          matchingOffer['enabled'] == null ||
          matchingOffer['enabled'] == 1;
      if (offerId != null && !offerEnabled) {
        processReply(
          number,
          TransactionStatuses.paused,
          name.split(' ')[0],
          name.trim().split(RegExp(r'\s+')).length > 1
              ? name.trim().split(RegExp(r'\s+'))[1]
              : '',
          amount,
        );

        final pausedCode = await selectBongaUssdCode(offerId);
        return await dontProcess(
          smsMessage.body ?? '',
          mpesaCode,
          number,
          pausedCode.replaceAll(RegExp(r'n'), '0$number'),
          amount,
          int.tryParse(matchingOffer['dialSim']?.toString() ?? '') ?? -1,
          status: TransactionStatuses.paused,
          reply: 'Offer paused. Please check/retry.',
          canRetry: false,
          source: name,
          forwardingJobId: forwardingJobId,
          forwardingSenderDeviceName: forwardingSenderDeviceName,
          targetOfferId: offerId,
          parentTransactionId: parentTransactionId,
        );
      }
    }

    // if()

    final forwardingResult = await forwardIfNeeded(
      amount,
      trimmedBody,
      smsMessage.body ?? "",
      mpesaCode,
      number,
      name,
      autoSaveContacts,
      parentTransactionId: parentTransactionId,
    );

    if (forwardingResult.state ==
        ForwardingAttemptState.forwardedSuccessfully) {
      return forwardingResult.transactionId;
    }
    if (forwardingResult.state ==
            ForwardingAttemptState.configuredButUnavailable ||
        forwardingResult.state == ForwardingAttemptState.configuredButPaused) {
      return _persistUnavailableForwardingTransaction(
        initialMessage: smsMessage.body ?? '',
        transactionCode: mpesaCode,
        number: number,
        amount: amount,
        source: name,
        parentTransactionId: parentTransactionId,
        destinationPaused: forwardingResult.state ==
            ForwardingAttemptState.configuredButPaused,
      );
    }

    bool offersMightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    if (offersMightHaveChanged) {
      processReply(
        number,
        TransactionStatuses.paused,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      return await dontProcess(
        smsMessage.body ?? "",
        getMpesaCode(smsMessage.body ?? ""),
        extract9DigitNumber(smsMessage.body ?? ""),
        '',
        getAmount(smsMessage.body),
        -1,
        status: TransactionStatuses.paused,
        reply: 'Offers might have changed. Please check/retry.',
        canRetry: false,
        source: getName(smsMessage.body ?? ""),
        parentTransactionId: parentTransactionId,
      );
    }

    if ((number / 100000000 < 1) ||
        smsMessage.body!.contains(
          RegExp('airtel money', caseSensitive: false),
        )) {
      if (forwardingJobId == null) {
        processReply(
          number,
          TransactionStatuses.unavailableOffer,
          name.split(' ')[0],
          name.trim().split(RegExp(r'\s+')).length > 1
              ? name.trim().split(RegExp(r'\s+'))[1]
              : '',
          amount,
        );
      }

      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        '',
        amount,
        -1,
        status: TransactionStatuses.unavailableOffer,
        reply: 'Invalid number',
        canRetry: false,
        source: name,
        forwardingJobId: forwardingJobId,
        forwardingSenderDeviceName: forwardingSenderDeviceName,
      );
    }

    List<dynamic> ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive =
        await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      smsMessage.subscriptionId ?? 0,
    );

    final canCompound = historicalCompound ??
        await unavailableAmountCanCompound(
          amount,
          number,
        );

    if (canCompound[3]) {
      ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive = canCompound;
      amount = canCompound[6];
    }

    if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0]
        .toString()
        .isEmpty) {
      if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive.length > 6) {
        final compoundedSmsBody = alterMpesaMessage(
          smsMessage.body ?? "",
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6],
        );
        final compoundedForwarding = await forwardIfNeeded(
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6],
          trimmedBody,
          compoundedSmsBody,
          mpesaCode,
          number,
          name,
          autoSaveContacts,
          parentTransactionId: parentTransactionId,
        );
        if (compoundedForwarding.state ==
            ForwardingAttemptState.forwardedSuccessfully) {
          return compoundedForwarding.transactionId;
        }
        if (compoundedForwarding.state ==
                ForwardingAttemptState.configuredButUnavailable ||
            compoundedForwarding.state ==
                ForwardingAttemptState.configuredButPaused) {
          return _persistUnavailableForwardingTransaction(
            initialMessage: compoundedSmsBody,
            transactionCode: mpesaCode,
            number: number,
            amount: ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6],
            source: name,
            parentTransactionId: parentTransactionId,
            destinationPaused: compoundedForwarding.state ==
                ForwardingAttemptState.configuredButPaused,
          );
        }
      }

      if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0]
          .toString()
          .isEmpty) {
        final configuredTarget = await findConfiguredUnavailableTarget(amount);
        final targetOfferId = configuredTarget?.id;
        final targetAmount = configuredTarget?.amount;
        final requiredTopUp = calculateRequiredTopUp(amount, targetAmount);
        final shouldAwaitTopUp = requiredTopUp != null &&
            (forwardingJobId != null ||
                await hasConfiguredReplyFor(
                  TransactionStatuses.unavailableOffer,
                  amount,
                ));

        int forwardingLimit =
            await _sharedPreferencesService.getForwardUnavailableLimit() ?? 0;

        // The legacy all-avenues fan-out can return before the unavailable
        // transaction is persisted. When this payment qualifies for top-up,
        // leave it to the persisted Unavailable Offer path below; any
        // subsequent combined transaction uses normal amount-based forwarding.
        if (!shouldAwaitTopUp &&
            forwardingLimit > 0 &&
            amount < forwardingLimit) {
          bool forwarded = await forwardToAllAvenues(
            smsMessage.body ?? "",
            parentTransactionId: parentTransactionId,
          );
          if (forwarded) return null;
        }

        if (autoSaveContacts) {
          await contactService.addNewContact(
            name,
            '0$number',
          );
        }

        final unavailableTransactionId = await dontProcess(
          smsMessage.body ?? "",
          mpesaCode,
          number,
          '',
          amount,
          -1,
          status: TransactionStatuses.unavailableOffer,
          reply: shouldAwaitTopUp
              ? 'No offer found for this amount. Awaiting KSh '
                  '$requiredTopUp to reach KSh $targetAmount.'
              : 'No offer found for this amount. Attempted forwarding to all paired devices, but no devices available to forward to.',
          canRetry: false,
          source: name,
          forwardingJobId: forwardingJobId,
          forwardingSenderDeviceName: forwardingSenderDeviceName,
          parentTransactionId: parentTransactionId,
          awaitingTopUp: shouldAwaitTopUp,
          requiredTopUp: shouldAwaitTopUp ? requiredTopUp : null,
          targetAmount: shouldAwaitTopUp ? targetAmount : null,
          targetOfferId: targetOfferId,
        );
        if (forwardingJobId == null) {
          await processReply(
            number,
            TransactionStatuses.unavailableOffer,
            name.split(' ')[0],
            name.trim().split(RegExp(r'\s+')).length > 1
                ? name.trim().split(RegExp(r'\s+'))[1]
                : '',
            amount,
          );
        }
        return unavailableTransactionId;
      }

      amount = ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[6];
    }

    if (!ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[5]) {
      processReply(
        number,
        TransactionStatuses.paused,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );

      if (autoSaveContacts) {
        await contactService.addNewContact(
          name,
          '0$number',
        );
      }

      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        amount,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        status: TransactionStatuses.paused,
        reply: 'Offer paused. Please check/retry.',
        canRetry: false,
        source: name,
        parentTransactionId: parentTransactionId,
        targetOfferId: int.tryParse(
          (await _findMatchingUssdCode(
                amount,
                smsMessage.subscriptionId ?? 0,
              ))?['id']
                  ?.toString() ??
              '',
        ),
      );
    }

    bool hasPaid = await _paymentOps.hasActiveSubscription();

    if (!hasPaid) {
      bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;
      int tokenBalance =
          await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      if (tokenBalance > 0) {
        isUsingToken = true;
      } else if (canRenew) {
        // get last entry from payments table
        List<String> reply = await _paymentOps.autoRenewSubscription();

        if (reply[1] != TransactionStatuses.done) {
          return await dontProcess(
            smsMessage.body ?? "",
            mpesaCode,
            number,
            '',
            amount,
            -1,
            status: TransactionStatuses.error,
            reply: 'Auto-renewal failed: ${reply[0]}',
            canRetry: true,
            source: name,
            parentTransactionId: parentTransactionId,
          );
        }
      } else {
        if (autoSaveContacts) {
          await contactService.addNewContact(
            name,
            '0$number',
          );
        }

        return await dontProcess(
          smsMessage.body ?? "",
          mpesaCode,
          number,
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
          amount,
          ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
          source: name,
          canRetry: true,
          parentTransactionId: parentTransactionId,
        );
      }
    }

    List requestResponse = [];

    if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]) {
      debugPrint('advanced starting');

      Map<String, dynamic> signatureMap = (await _sqliteService.queryCustom(
            'codeSignature',
            'ussdCodeId = ?',
            [ussdCodeItem.id ?? -1],
          ))
              .firstOrNull ??
          {};
      CodeSignature? signature;

      if (signatureMap.isNotEmpty) {
        signature = CodeSignature.fromMap(
          signatureMap,
        );
      }

      requestResponse = await PhoneService().makeAdvancedRequest(
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        codeSignature: signatureMap.isEmpty ? null : signature,
      );

      requestResponse[1] = await transactionStatus(requestResponse);

      if (requestResponse[1] == TransactionStatuses.error) {
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[2] = true;
      }
    } else {
      requestResponse = await PhoneService().makeMyRequest(
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
      );
      requestResponse[1] = await transactionStatus(requestResponse);
    }

    debugPrint("Rechecking status after USSD execution: ${requestResponse[1]}");

    if (requestResponse[1] == TransactionStatuses.hasOkoa) {
      processReply(
        number,
        TransactionStatuses.hasOkoa,
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );
      return await dontProcess(
        smsMessage.body ?? "",
        mpesaCode,
        number,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        amount,
        ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        status: TransactionStatuses.hasOkoa,
        reply: requestResponse[0],
        canRetry: false,
        source: name,
        parentTransactionId: parentTransactionId,
      );
    }

    if (isUsingToken) {
      await _paymentOps.deductSingleToken();
    }

    await recordClientPurchase(number.toString(), name);

    final firstFailedTimeStamp =
        requestResponse[1] == TransactionStatuses.secondAttempt
            ? DateTime.now().millisecondsSinceEpoch
            : null;
    final transactionID = await _sqliteService.insertStuff(
      {
        'initialMessage': smsMessage.body,
        'transactionId': mpesaCode,
        'forwardingJobId': forwardingJobId,
        'forwardingSenderDeviceName': forwardingSenderDeviceName,
        'parentTransactionId': parentTransactionId,
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0],
        'ussdReply': requestResponse[0],
        'amount': amount,
        'smsDate': getNormalDate(
          DateTime.fromMillisecondsSinceEpoch(smsMessage.date ?? 0),
        ),
        'smsTime': getNormalTime(
          DateTime.fromMillisecondsSinceEpoch(smsMessage.date ?? 0),
        ),
        'status': requestResponse[1] == "" ? "No reply" : requestResponse[1],
        if (firstFailedTimeStamp != null)
          'firstFailedTimeStamp': firstFailedTimeStamp,
        'simSubId': ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1],
        'source': name,
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry':
            ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[2] ? 1 : 0,
      },
      'transactions',
    );
    debugPrint(
      'FORWARDED SMS STORED: '
      'localTransactionId=$transactionID, '
      'forwardingJobId=${forwardingJobId ?? ''}',
    );
    debugPrint('[ALT FIX] transaction=$transactionID');
    debugPrint(
      '[ALT FIX] status=${requestResponse[1] == "" ? "No reply" : requestResponse[1]}',
    );
    if (firstFailedTimeStamp != null) {
      debugPrint('[ALT FIX] firstFailedTimeStamp=$firstFailedTimeStamp');
    }

    if (autoSaveContacts) {
      await contactService.addNewContact(
        name,
        '0$number',
      );
    }

    // if (TransactionStatuses.secondAttempt == requestResponse[1]) {
    //   // USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5isActive = await unavailableAmountCanCompound(amount, number);
    //   return;
    // }

    if (requestResponse[1] != TransactionStatuses.unavailableOffer ||
        forwardingJobId == null) {
      await processReply(
        number,
        requestResponse[1],
        name.split(' ')[0],
        name.trim().split(RegExp(r'\s+')).length > 1
            ? name.trim().split(RegExp(r'\s+'))[1]
            : '',
        amount,
      );
    }

// ONLINE FORWARDING: notify Phone A only after Phone B confirms the transaction.
    if (requestResponse[1] == TransactionStatuses.doneConfirmed &&
        forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      await _sendForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: forwardingSenderDeviceName,
        transactionId: mpesaCode,
      );
    }

    // Unavailable Offer is terminal for this forwarded attempt too. Report it
    // to the origin device so its job does not remain pending indefinitely.
    if (requestResponse[1] == TransactionStatuses.unavailableOffer &&
        forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      await _sendForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: forwardingSenderDeviceName,
        transactionId: mpesaCode,
        resultStatus: TransactionStatuses.unavailableOffer,
      );
    }

    retryAll(true);
    return transactionID;
  }

  Future<ForwardingAttemptResult> forwardIfNeeded(
    int amount,
    String trimmedBody,
    String smsMessageBody,
    String mpesaCode,
    int number,
    String sourceName,
    bool autoSaveContacts, {
    String? status,
    int? txId,
    String? forwardingRecipientDeviceName,
    int? parentTransactionId,
    bool pairedDeviceOnly = false,
  }) async {
    var pairedConfigurationExists = false;
    List toForward = await _sqliteService.queryCustom(
      "forwarded",
      "(amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)",
      [
        '[$amount,%',
        '%,$amount,%',
        '%,$amount]',
        '[$amount]',
      ],
    );

    String name = sourceName.isEmpty ? getName(smsMessageBody) : sourceName;

    String message = (smsMessageBody).substring(
      0,
      (smsMessageBody).length > 160 ? 160 : (smsMessageBody).length,
    );

    if (!pairedDeviceOnly && toForward.isNotEmpty) {
      if (toForward[0]["paused"] != 1) {
        // debugPrint(
        //     "Forwarding is paused for device ${toForward[0]["numberToReceive"]}. Skipping forwarding.");

        String reply = await sendEvenInBackground(
          '254${toForward[0]["numberToReceive"]}',
          message,
          checkIfSimilar: false,
        );

        processReply(
          number,
          TransactionStatuses.forwarded,
          name.split(' ')[0],
          name.trim().split(RegExp(r'\s+')).length > 1
              ? name.trim().split(RegExp(r'\s+'))[1]
              : '',
          amount,
        );

        if (autoSaveContacts) {
          ClientService().insertClient(
            Client.fromMpesaMessage(message),
          );
          await ContactsService().addNewContact(
            name,
            '0$number',
          );
        }

        final transactionId = await dontProcess(
          smsMessageBody,
          mpesaCode,
          number,
          '',
          amount,
          -1,
          status: status ?? TransactionStatuses.forwarded,
          reply: 'Forwarding to ${toForward[0]["numberToReceive"]}: $reply',
          canRetry: false,
          source: name,
          id: txId,
          parentTransactionId: parentTransactionId,
        );
        return ForwardingAttemptResult(
          ForwardingAttemptState.forwardedSuccessfully,
          transactionId: transactionId,
        );
      }
    }
    try {
      if (amount > 0) {
        List<Map<String, dynamic>> forwardingDevices =
            await _sqliteService.queryAll('forwardingDevices');

        if (forwardingDevices.isNotEmpty) {
          final senderDeviceName =
              await SharedPreferencesService().getDeviceName() ??
                  "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

          // ------------------------------------------------------------
          // STEP 1: Build the list of devices that are allowed to
          // forward this amount AND are currently online.
          // ------------------------------------------------------------
          final List<Map<String, dynamic>> configuredDevices = [];
          final List<Map<String, dynamic>> eligibleDevices = [];

          for (final device in forwardingDevices) {
            final recipientDeviceName = device['device_name']?.toString() ??
                "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

            String amountsString =
                device['amounts_to_forward']?.toString() ?? "";

            amountsString = amountsString.replaceAll(RegExp(r'[\[\]"]'), '');

            final List<String> amounts = amountsString.isEmpty
                ? []
                : amountsString.split(',').map((e) => e.trim()).toList();

            if (!amounts.contains(amount.toString())) {
              continue;
            }

            configuredDevices.add(device);
            pairedConfigurationExists = true;
            final isPaused = (device['paused'] ?? 0) == 1;
            final isOnline =
                await AuthService().pingDevice(recipientDeviceName);
            debugPrint(
              'ONLINE FORWARDING ROUTE: amount=$amount '
              'device=$recipientDeviceName paused=$isPaused online=$isOnline',
            );

            if (isPaused || !isOnline) {
              if (!isPaused) {
                debugPrint(
                  'ONLINE FORWARDING: '
                  '$recipientDeviceName is offline for amount $amount',
                );
              }
              continue;
            }

            eligibleDevices.add(device);
          }
          debugPrint(
            'ONLINE FORWARDING ROUTES: amount=$amount '
            'configured=${configuredDevices.isNotEmpty} '
            'devices=${configuredDevices.map((device) => device['device_name']).join(',')}',
          );

          // ------------------------------------------------------------
          // STEP 2: Load the existing transaction, if this is a retry.
          // ------------------------------------------------------------
          Map<String, dynamic>? existingTransaction;

          if (txId != null) {
            final existingRows = await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [txId],
            );

            if (existingRows.isNotEmpty) {
              existingTransaction = existingRows.first;
            }
          }

          final savedRecipientDeviceName = forwardingRecipientDeviceName ??
              existingTransaction?['forwardingRecipientDeviceName']?.toString();

          final savedForwardingJobId =
              existingTransaction?['forwardingJobId']?.toString();

          // ------------------------------------------------------------
          // STEP 3: Select the recipient.
          //
          // RETRY:
          //   Always reuse the saved recipient.
          //
          // NEW TRANSACTION:
          //   Use round-robin for this specific amount.
          // ------------------------------------------------------------
          Map<String, dynamic>? selectedDevice;
          String? recipientDeviceName;
          int? selectedIndex;
          bool isRetryWithSavedRecipient = savedRecipientDeviceName != null &&
              savedRecipientDeviceName.isNotEmpty;

          if (isRetryWithSavedRecipient) {
            // ----------------------------------------------------------
            // RETRY PATH
            //
            // Do NOT rotate. Do NOT choose another phone.
            // ----------------------------------------------------------
            recipientDeviceName = savedRecipientDeviceName;

            for (final device in forwardingDevices) {
              final deviceName = device['device_name']?.toString();

              if (deviceName == recipientDeviceName) {
                selectedDevice = device;
                break;
              }
            }

            debugPrint(
              'ONLINE FORWARDING RETRY: '
              'Reusing recipient=$recipientDeviceName '
              'for transactionId=$txId',
            );

            if ((selectedDevice?['paused'] ?? 0) == 1) {
              debugPrint(
                'ONLINE FORWARDING FINAL: amount=$amount '
                'state=configuredButPaused',
              );
              return const ForwardingAttemptResult(
                ForwardingAttemptState.configuredButPaused,
              );
            }

            // Important:
            // If the original recipient is currently offline, do not
            // silently redirect this transaction to another phone.
            final recipientOnline =
                await AuthService().pingDevice(recipientDeviceName);

            if (!recipientOnline) {
              debugPrint(
                'ONLINE FORWARDING RETRY: '
                'Original recipient $recipientDeviceName is offline. '
                'Will NOT rotate to another device.',
              );

              if (txId != null) {
                await _sqliteService.updateStuff(
                  {
                    'status': TransactionStatuses.error,
                    'ussdReply': 'Forwarding failed: original forwarding device '
                        '$recipientDeviceName is offline. Will retry later.',
                  },
                  'id = ?',
                  [txId],
                  'transactions',
                );
              }

              debugPrint(
                'ONLINE FORWARDING FINAL: amount=$amount '
                'state=configuredButUnavailable',
              );
              return const ForwardingAttemptResult(
                ForwardingAttemptState.configuredButUnavailable,
              );
            }
          } else {
            // ----------------------------------------------------------
            // NEW TRANSACTION PATH
            //
            // Round-robin index is stored separately for each amount.
            // ----------------------------------------------------------
            if (eligibleDevices.isEmpty) {
              debugPrint(
                'ONLINE FORWARDING: '
                'No online forwarding device available for amount $amount',
              );
              final allConfiguredDevicesPaused = configuredDevices.isNotEmpty &&
                  configuredDevices
                      .every((device) => (device['paused'] ?? 0) == 1);
              final state = configuredDevices.isEmpty
                  ? ForwardingAttemptState.noConfiguration
                  : allConfiguredDevicesPaused
                      ? ForwardingAttemptState.configuredButPaused
                      : ForwardingAttemptState.configuredButUnavailable;
              debugPrint(
                'ONLINE FORWARDING FINAL: amount=$amount state=$state',
              );
              return ForwardingAttemptResult(state);
            }

            final storedIndex = await SharedPreferencesService()
                    .getOnlineForwardingIndex(amount) ??
                0;

            selectedIndex = storedIndex % eligibleDevices.length;

            selectedDevice = eligibleDevices[selectedIndex];

            recipientDeviceName = selectedDevice['device_name']?.toString() ??
                "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

            debugPrint(
              'ONLINE FORWARDING ROUND-ROBIN: '
              'amount=$amount '
              'eligible=${eligibleDevices.length} '
              'storedIndex=$storedIndex '
              'selectedIndex=$selectedIndex '
              'recipient=$recipientDeviceName',
            );
          }

          // ------------------------------------------------------------
          // STEP 4: Reuse or create the forwarding job ID.
          // ------------------------------------------------------------
          String? forwardingJobId = savedForwardingJobId;

          if (forwardingJobId != null && forwardingJobId.isNotEmpty) {
            debugPrint(
              'ONLINE FORWARDING RETRY: '
              'Reusing existing forwardingJobId=$forwardingJobId '
              'for transactionId=$txId',
            );
          }

          if (forwardingJobId == null || forwardingJobId.isEmpty) {
            forwardingJobId = ForwardingJobId.generate(mpesaCode: mpesaCode);
          }
          debugPrint(
            'FORWARDED SMS JOB CREATED: '
            'transactionId=$mpesaCode, forwardingJobId=$forwardingJobId',
          );

          // ------------------------------------------------------------
          // STEP 5: Create/update the local transaction.
          // Save the selected recipient permanently so retries know
          // exactly which phone originally received the transaction.
          // ------------------------------------------------------------
          int? transactionId = txId;

          if (transactionId == null) {
            final unavailableTarget =
                await findConfiguredUnavailableTarget(amount);
            transactionId = await dontProcess(
              smsMessageBody,
              mpesaCode,
              number,
              '',
              amount,
              -1,
              status: TransactionStatuses.forwardedPending,
              reply: 'Forwarding to device',
              canRetry: true,
              source: name,
              forwardingJobId: forwardingJobId,
              forwardingSenderDeviceName: senderDeviceName,
              forwardingRecipientDeviceName: recipientDeviceName,
              parentTransactionId: parentTransactionId,
              targetOfferId: unavailableTarget?.id,
            );
          } else {
            final Map<String, dynamic> updateData = {
              'forwardingJobId': forwardingJobId,
              'status': TransactionStatuses.forwardedPending,
              'canRetry': 1,
              'ussdReply': 'Forwarding to device',
            };

            // Never overwrite an existing recipient during retry.
            if (savedRecipientDeviceName == null ||
                savedRecipientDeviceName.isEmpty) {
              updateData['forwardingRecipientDeviceName'] = recipientDeviceName;
            }

            if (existingTransaction?['forwardingSenderDeviceName']
                    ?.toString()
                    .isEmpty ??
                true) {
              updateData['forwardingSenderDeviceName'] = senderDeviceName;
            }

            await _sqliteService.updateStuff(
              updateData,
              'id = ?',
              [transactionId],
              'transactions',
            );

            debugPrint(
              'ONLINE FORWARDING RETRY: '
              'transactionId=$transactionId, '
              'forwardingJobId=$forwardingJobId, '
              'recipient=$recipientDeviceName',
            );
          }

          debugPrint(
            'FORWARDING DEBUG AFTER CREATE: '
            'transactionId=$transactionId, '
            'forwardingJobId=$forwardingJobId, '
            'recipient=$recipientDeviceName',
          );

          if (transactionId != null) {
            final debugRows = await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [transactionId],
              columns: ['id', 'forwardingJobId'],
            );

            debugPrint(
              'FORWARDED SMS STORED: '
              'localTransactionId=$transactionId, row=$debugRows',
            );
          }

          // ------------------------------------------------------------
          // STEP 6: Send the forwarding message.
          // ------------------------------------------------------------
          debugPrint(
            'FORWARDED SMS SEND: '
            'transactionId=$transactionId, '
            'forwardingJobId=$forwardingJobId, '
            'sender=$senderDeviceName, '
            'recipient=$recipientDeviceName',
          );
          final result = await BackendService().post(
            '/api/fcm/send-secure',
            body: {
              'title': "BSAT Online Forwarding",
              'body': smsMessageBody,
              'senderDeviceName': senderDeviceName,
              'recipientDeviceName': recipientDeviceName,
              'data': {
                'type': 'forwarded_sms',
                'body': smsMessageBody,
                'title': "Forwarded Message",
                'messageId': mpesaCode,
                'transactionId': transactionId,
                'forwardingJobId': forwardingJobId,
                'forwardingStatus': ForwardingJobStatuses.pending,
                'senderDeviceName': senderDeviceName,
              }
            },
          );

          final String messageId = result['messageId'] ?? "";

          debugPrint("MessageID: $messageId");

          // ------------------------------------------------------------
          // STEP 7: Backend send failed.
          //
          // Do NOT advance the round-robin index.
          // ------------------------------------------------------------
          if (result['success'] != true) {
            await _sqliteService.updateStuff(
              {
                'status': TransactionStatuses.error,
                'ussdReply':
                    'Forwarding failed: Phone offline or server not reachable. Will retry later.',
              },
              'id = ?',
              [transactionId],
              'transactions',
            );

            return const ForwardingAttemptResult(
              ForwardingAttemptState.configuredButUnavailable,
            );
          }

          // ------------------------------------------------------------
          // STEP 8: Backend send succeeded.
          //
          // Only NEW transactions advance the per-amount index.
          // Retries NEVER rotate.
          // ------------------------------------------------------------
          if (!isRetryWithSavedRecipient &&
              selectedIndex != null &&
              eligibleDevices.isNotEmpty) {
            final nextIndex = (selectedIndex + 1) % eligibleDevices.length;

            await SharedPreferencesService()
                .setOnlineForwardingIndex(amount, nextIndex);

            debugPrint(
              'ONLINE FORWARDING ROUND-ROBIN: '
              'amount=$amount '
              'selected=$recipientDeviceName '
              'nextIndex=$nextIndex',
            );
          }

          await _sqliteService.updateStuff(
            {
              'status': TransactionStatuses.forwardedPending,
              'forwardingRecipientDeviceName': recipientDeviceName,
              'ussdReply': 'Forwarded to $recipientDeviceName'
                  '${selectedDevice != null && selectedDevice['device_id'] != null ? ' (ID: ${selectedDevice['device_id']})' : ''}',
            },
            'id = ?',
            [transactionId],
            'transactions',
          );

          // Preserve the existing online-forwarding flow.
          await processReply(
            number,
            TransactionStatuses.forwardedOnline,
            name.split(' ')[0],
            name.trim().split(RegExp(r'\s+')).length > 1
                ? name.trim().split(RegExp(r'\s+'))[1]
                : '',
            amount,
          );

          debugPrint(
            'ONLINE FORWARDING FINAL: amount=$amount '
            'state=forwardedSuccessfully',
          );
          return ForwardingAttemptResult(
            ForwardingAttemptState.forwardedSuccessfully,
            transactionId: transactionId,
          );
        }
      }
    } catch (e) {
      debugPrint("Error checking forwarding devices: $e");
    }

    final state = pairedConfigurationExists
        ? ForwardingAttemptState.configuredButUnavailable
        : ForwardingAttemptState.noConfiguration;
    debugPrint(
      'ONLINE FORWARDING FINAL: amount=$amount '
      'configured=$pairedConfigurationExists state=$state',
    );
    return ForwardingAttemptResult(state);
  }

  Future<int?> _persistUnavailableForwardingTransaction({
    int? transactionId,
    required String initialMessage,
    required String transactionCode,
    required int number,
    required int amount,
    required String source,
    int? parentTransactionId,
    bool destinationPaused = false,
  }) async {
    final status = destinationPaused
        ? TransactionStatuses.paused
        : TransactionStatuses.error;
    final reply = destinationPaused
        ? _pausedForwardingReply
        : 'Paired-device forwarding is configured but currently unavailable. '
            'Will retry forwarding later.';
    if (transactionId != null) {
      await _sqliteService.updateStuff(
        {
          'status': status,
          'canRetry': destinationPaused ? 0 : 1,
          'ussdReply': reply,
        },
        'id = ? AND status NOT IN (?, ?)',
        [
          transactionId,
          TransactionStatuses.forwardedPending,
          TransactionStatuses.forwardedConfirmed,
        ],
        'transactions',
      );
      return transactionId;
    }
    return dontProcess(
      initialMessage,
      transactionCode,
      number,
      '',
      amount,
      -1,
      status: status,
      reply: reply,
      canRetry: !destinationPaused,
      source: source,
      parentTransactionId: parentTransactionId,
    );
  }

  Future<void> resumePausedForwardingTransactions(String deviceName) async {
    final devices = await _sqliteService.queryCustom(
      'forwardingDevices',
      'device_name = ? AND paused = 0',
      [deviceName],
      limit: 1,
    );
    if (devices.isEmpty) return;

    final amountList = (devices.first['amounts_to_forward']?.toString() ?? '')
        .replaceAll(RegExp(r'[\[\]"]'), '')
        .split(',')
        .map((value) => int.tryParse(value.trim()))
        .whereType<int>()
        .toSet();
    if (amountList.isEmpty) return;

    final transactions = await _sqliteService.queryCustom(
      'transactions',
      'status = ? AND (ussdReply = ? OR ussdReply LIKE ?)',
      [
        TransactionStatuses.paused,
        _pausedForwardingReply,
        '$_pausedOfferResumeClaimPrefix%',
      ],
      orderBy: 'timeStamp ASC',
    );

    for (final transaction in transactions) {
      final amount = int.tryParse(transaction['amount']?.toString() ?? '');
      final transactionId = int.tryParse(transaction['id']?.toString() ?? '');
      if (amount == null ||
          transactionId == null ||
          !amountList.contains(amount)) {
        continue;
      }
      await _resumePausedForwardingTransaction(transactionId);
    }
  }

  Future<void> _resumePausedForwardingTransaction(int transactionId) async {
    if (!_activePausedForwardingResumes.add(transactionId)) return;
    try {
      await _resumeClaimedPausedForwardingTransaction(transactionId);
    } finally {
      _activePausedForwardingResumes.remove(transactionId);
    }
  }

  Future<void> _resumeClaimedPausedForwardingTransaction(
    int transactionId,
  ) async {
    final rows = await _sqliteService.queryCustom(
      'transactions',
      'id = ? AND status = ?',
      [transactionId, TransactionStatuses.paused],
      limit: 1,
    );
    if (rows.isEmpty) return;

    final transaction = rows.first;
    final currentReply = transaction['ussdReply']?.toString() ?? '';
    if (currentReply != _pausedForwardingReply) {
      if (!currentReply.startsWith(_pausedOfferResumeClaimPrefix)) return;
      final claimedAt = int.tryParse(
        currentReply.substring(_pausedOfferResumeClaimPrefix.length),
      );
      final claimAge = DateTime.now().millisecondsSinceEpoch - (claimedAt ?? 0);
      if (claimAge < _pausedOfferResumeClaimLease.inMilliseconds) return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final claimReply = '$_pausedOfferResumeClaimPrefix$now';
    final claimed = await _sqliteService.updateStuff(
      {'ussdReply': claimReply},
      'id = ? AND status = ? AND ussdReply = ?',
      [transactionId, TransactionStatuses.paused, currentReply],
      'transactions',
    );
    if (claimed != 1) return;

    final initialMessage = transaction['initialMessage']?.toString() ?? '';
    final amount = int.tryParse(transaction['amount']?.toString() ?? '') ?? 0;
    final result = await forwardIfNeeded(
      amount,
      initialMessage.length > 160
          ? initialMessage.substring(0, 160)
          : initialMessage,
      initialMessage,
      transaction['transactionId']?.toString() ?? '',
      int.tryParse(transaction['number']?.toString() ?? '') ?? 0,
      transaction['source']?.toString() ?? '',
      true,
      txId: transactionId,
      parentTransactionId:
          int.tryParse(transaction['parentTransactionId']?.toString() ?? ''),
      pairedDeviceOnly: true,
    );

    if (result.state == ForwardingAttemptState.forwardedSuccessfully) return;

    await _persistUnavailableForwardingTransaction(
      transactionId: transactionId,
      initialMessage: initialMessage,
      transactionCode: transaction['transactionId']?.toString() ?? '',
      number: int.tryParse(transaction['number']?.toString() ?? '') ?? 0,
      amount: amount,
      source: transaction['source']?.toString() ?? '',
      parentTransactionId:
          int.tryParse(transaction['parentTransactionId']?.toString() ?? ''),
      destinationPaused:
          result.state == ForwardingAttemptState.configuredButPaused,
    );
  }

  Future<bool> forwardToAllAvenues(
    String message, {
    int? parentTransactionId,
  }) async {
    Map<String, dynamic> similarTransaction = await _sqliteService.queryCustom(
      'transactions',
      'initialMessage = ? AND status = ?',
      [message, TransactionStatuses.forwarded],
    ).then((value) => value.isNotEmpty ? value.first : {});

    if (similarTransaction.isNotEmpty) {
      debugPrint(
          "Message has already been forwarded before. Skipping forwarding to all avenues to avoid duplicates.");
      return false;
    }
    List<Map<String, dynamic>> devices =
        await _sqliteService.queryAll('forwardingDevices');

    String name = getName(message);
    int amount = getAmount(message);
    int number = extract9DigitNumber(message);

    for (var device in devices) {
      if ((device['paused'] ?? 0) != 1) {
        String recipientDeviceName = device['device_name'] ?? "Unknown Device";
        String senderDeviceName =
            await SharedPreferencesService().getDeviceName() ??
                "Unknown Device ${DateTime.now().millisecondsSinceEpoch}";

        if (await AuthService().pingDevice(recipientDeviceName)) {
        } else {
          continue;
        }

        final forwardingJobId =
            ForwardingJobId.generate(mpesaCode: getMpesaCode(message));
        debugPrint(
          'FORWARDED SMS JOB CREATED: '
          'transactionId=${getMpesaCode(message)}, '
          'forwardingJobId=$forwardingJobId',
        );
        final transactionId = await dontProcess(
          message,
          getMpesaCode(message),
          number,
          '',
          amount,
          -1,
          status: TransactionStatuses.forwarded,
          reply:
              'Forwarded unavailable amount(Ksh $amount) to all paired devices',
          canRetry: false,
          source: name,
          forwardingJobId: forwardingJobId,
          forwardingSenderDeviceName: senderDeviceName,
          forwardingRecipientDeviceName: recipientDeviceName,
          parentTransactionId: parentTransactionId,
        );
        final storedRows = transactionId == null
            ? <Map<String, dynamic>>[]
            : await _sqliteService.queryCustom(
                'transactions',
                'id = ?',
                [transactionId],
                columns: ['id', 'forwardingJobId'],
              );

        debugPrint(
          'FORWARDED SMS STORED: '
          'localTransactionId=$transactionId, '
          'forwardingJobId=$forwardingJobId, row=$storedRows',
        );
        debugPrint(
          'FORWARDED SMS SEND: '
          'transactionId=$transactionId, '
          'forwardingJobId=$forwardingJobId, '
          'sender=$senderDeviceName, '
          'recipient=$recipientDeviceName',
        );

        final result = await BackendService().post(
          '/api/fcm/send-secure',
          body: {
            'title': "BSAT Online Forwarding",
            'body': message,
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': recipientDeviceName,
            'data': {
              'type': 'forwarded_sms',
              'body': message,
              'title': "Forwarded Message",
              'messageId': getMpesaCode(message),
              'transactionId': transactionId,
              'forwardingJobId': forwardingJobId,
              'forwardingStatus': ForwardingJobStatuses.pending,
              'senderDeviceName': senderDeviceName,
            }
          },
        );
        debugPrint(
          'FORWARDED SMS SEND RESULT: '
          'transactionId=$transactionId, '
          'forwardingJobId=$forwardingJobId, '
          'success=${result['success']}',
        );
      }
    }

    if (devices.isNotEmpty) {
      return true;
    }

    // debugPrint("No forwarding devices found to forward the message.");
    return false;
  }

  Future<List<dynamic>> unavailableAmountCanCompound(
    int amount,
    int number,
  ) async {
    int yesterdayMidnight = getTodayMidnightMillis() - 86400000;
    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'status IN (?, ?) AND number = ? AND timeStamp >= ? AND '
          'COALESCE(awaitingTopUp, 0) != 1',
      [
        TransactionStatuses.secondAttempt,
        TransactionStatuses.unavailableOffer,
        number,
        yesterdayMidnight
      ],
      columns: ['id', 'amount', 'simSubId', 'canRetry'],
    );

    for (var stuff in rawStuff) {
      amount += (stuff['amount'] ?? 0) as int;
    }

    int fromSim = rawStuff.isNotEmpty ? rawStuff.first['simSubId'] : 0;

    List reply =
        (await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      fromSim,
    ));

    bool canForward = (await _sqliteService.getCount(
          'forwarded',
          args: [
            '[$amount,%',
            '%,$amount,%',
            '%,$amount]',
            '[$amount]',
          ],
          appendQuery:
              'WHERE (amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ? OR amounts LIKE ?)',
        )) >
        0;

    bool canForwardToDevices = (await _sqliteService.getCount(
          'forwardingDevices',
          args: [
            '[$amount,%',
            '%,$amount,%',
            '%,$amount]',
            '[$amount]',
          ],
          appendQuery:
              'WHERE (amounts_to_forward LIKE ? OR amounts_to_forward LIKE ? OR amounts_to_forward LIKE ? OR amounts_to_forward LIKE ?)',
        )) >
        0;

    canForward = canForward || canForwardToDevices;

    // delete the entries from transactions
    if (rawStuff.isNotEmpty && (reply[3] || canForward)) {
      reply[3] = true;
      await _sqliteService.deleteWhere(
        'transactions',
        'id IN (${rawStuff.map((e) => e['id']).join(',')})',
        [],
      );
    }

    return [
      ...reply,
      amount,
      rawStuff.isNotEmpty,
    ];
  }

  Future<bool> hasConfiguredReplyFor(String status, int amount) async {
    final condition = TransactionStatuses.statuses.entries
        .where((entry) => entry.value == status)
        .map((entry) => entry.key)
        .firstOrNull;
    if (condition == null) return false;
    final rows = await _sqliteService.queryCustom(
      'replies',
      'condition = ? AND conditionAmount = 1',
      [condition],
      columns: ['reply', 'amounts'],
    );
    for (final row in rows) {
      if ((row['reply']?.toString().trim().isEmpty ?? true)) continue;
      final rawAmounts = row['amounts']?.toString() ?? '';
      if (rawAmounts.isEmpty || rawAmounts == '[]' || rawAmounts == '""') {
        return true;
      }
      try {
        final amounts = (jsonDecode(rawAmounts) as List)
            .map((value) => int.tryParse(value.toString()))
            .whereType<int>();
        if (amounts.contains(amount)) return true;
      } catch (_) {}
    }
    return false;
  }

  Future<({int id, int? amount})?> findConfiguredUnavailableTarget(
    int amount,
  ) async {
    final reply = await _findReplyFor(
      TransactionStatuses.unavailableOffer,
      amount,
    );
    final offerId = int.tryParse(reply?['targetOfferId']?.toString() ?? '');
    if (offerId == null) return null;
    return (
      id: offerId,
      amount: await getOfferAmountById(offerId),
    );
  }

  Future<int?> getOfferAmountById(int offerId) async {
    final rows = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [offerId],
      columns: ['amount'],
      limit: 1,
    );
    return rows.isEmpty
        ? null
        : int.tryParse(rows.first['amount']?.toString() ?? '');
  }

  Future<Map<String, dynamic>?> _findReplyFor(
    String transactionStatus,
    int amount,
  ) async {
    final condition = TransactionStatuses.statuses.entries
        .where((entry) => entry.value == transactionStatus)
        .map((entry) => entry.key)
        .firstOrNull;
    if (condition == null) return null;

    final replies = await _sqliteService.queryCustom(
      'replies',
      '''conditionAmount = 1 AND condition = ? AND (
        amounts LIKE ? OR
        amounts LIKE ? OR
        amounts LIKE ? OR
        amounts LIKE ? OR
        amounts = '[]' OR amounts = ""
      )''',
      [
        condition,
        '[$amount,%',
        '%,$amount,%',
        '%,$amount]',
        '[$amount]',
      ],
      orderBy:
          'CASE WHEN amounts IS NULL OR amounts = "" THEN 1 ELSE 0 END, CAST(amounts AS INTEGER) ASC',
    );
    if (replies.isEmpty) return null;

    final matchingReplies = replies.where((reply) {
      final rawAmounts = reply['amounts']?.toString();
      if (rawAmounts == null || rawAmounts.isEmpty) return true;
      try {
        return (jsonDecode(rawAmounts) as List).contains(amount);
      } catch (error) {
        debugPrint('Error parsing amounts JSON: $error');
        return false;
      }
    }).toList();
    return (matchingReplies.isEmpty ? replies : matchingReplies).first;
  }

  Future<int?> findNextSupportedAmount(int amount) async {
    final candidates = <int>{};
    final offers = await _sqliteService.queryCustom(
      'ussdCodes',
      'enabled = 1 AND amount > ?',
      [amount],
      columns: ['amount'],
    );
    for (final row in offers) {
      final value = int.tryParse(row['amount']?.toString() ?? '');
      if (value != null && value > amount) candidates.add(value);
    }

    for (final device in await _sqliteService.queryAll('forwardingDevices')) {
      if ((device['paused'] ?? 0) == 1) continue;
      final raw = device['amounts_to_forward']?.toString() ?? '';
      for (final token in raw.replaceAll(RegExp(r'[\[\]"]'), '').split(',')) {
        final value = int.tryParse(token.trim());
        if (value != null && value > amount) candidates.add(value);
      }
    }
    for (final device in await _sqliteService.queryAll('forwarded')) {
      if ((device['paused'] ?? 0) == 1) continue;
      final raw = device['amounts']?.toString() ?? '';
      for (final token in raw.replaceAll(RegExp(r'[\[\]"]'), '').split(',')) {
        final value = int.tryParse(token.trim());
        if (value != null && value > amount) candidates.add(value);
      }
    }
    if (candidates.isEmpty) return null;
    final sorted = candidates.toList()..sort();
    return sorted.first;
  }

  Future<void> runScheduled() async {
    bool isUsingToken = false;

    int currentTime = DateTime.now().millisecondsSinceEpoch;

    List tasks = await _sqliteService.queryCustom(
      'tasks',
      'startDate <= ? AND (startDate + duration * 86400000) >= ? AND nextTaskDate <= ?',
      [currentTime, currentTime, currentTime],
    );

    for (var task in tasks) {
      int number = getNumberFromCode(task['code']);

      bool hasPaid = await _paymentOps.hasActiveSubscription();

      if (!hasPaid) {
        bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;
        int tokenBalance =
            await _sharedPreferencesService.getDeliveryTokens() ?? 0;

        if (tokenBalance > 0) {
          isUsingToken = true;
        } else if (canRenew) {
          // get last entry from payments table
          List<String> reply = await _paymentOps.autoRenewSubscription();

          if (reply[1] != TransactionStatuses.done) {
            return;
          }
        } else {
          await dontProcess(
            'Scheduled',
            '',
            number,
            task['code'],
            0,
            task['dialSim'],
          );

          continue;
        }
      }

      List value = await _phoneService.makeMyRequest(
        task['code'],
        task['dialSim'],
      );

      await _sqliteService.updateStuff(
        {"nextTaskDate": task['nextTaskDate'] + 86400000},
        'id = ?',
        [task['id']],
        'tasks',
      );

      value[1] = await transactionStatus(value);

      if (value[1] == TransactionStatuses.done) {
        if (isUsingToken) {
          await _paymentOps.deductSingleToken();
        }
      }

      await _sqliteService.insertStuff(
        {
          'initialMessage': 'Scheduled',
          'transactionId': '',
          'number': number,
          'date': getNormalDate(DateTime.now()),
          'time': getNormalTime(DateTime.now()),
          'ussdDialed': task['code'],
          'ussdReply': value[0],
          'amount': task['amount'],
          'smsDate': getNormalDate(DateTime.now()),
          'smsTime': getNormalTime(DateTime.now()),
          'simSubId': task['dialSim'],
          // 'smsSubId': task['dialSim'],
          'status': value[1],
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
          'canRetry': 1,
          'source': 'scheduled',
        },
        "transactions",
      );

      debugPrint("start ${task['startDate'] - currentTime}");
      debugPrint("next ${task['nextTaskDate'] - currentTime}");
      debugPrint("deleteAfterRunning ${task['deleteAfterRunning']}");

      if (task['deleteAfterRunning'] == 1 &&
          (task['startDate'] + (task['duration'] - 1) * 86400000) <
              currentTime) {
        await _sqliteService.deleteStuff(
          task['id'],
          'tasks',
        );
      }
    }
  }

  Future<void> addAllToAutomated(List<int> ids) async {
    await _sqliteService.addColumnIfNotExists('tasks', 'offer', 'TEXT');
    await _sqliteService.addColumnIfNotExists('tasks', 'number', 'INTEGER');
    await _sqliteService.addColumnIfNotExists('tasks', 'amount', 'INTEGER');
    await _sqliteService.addColumnIfNotExists(
        'tasks', 'deleteAfterRunning', 'INTEGER');

    if (ids.isEmpty) return;

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'id IN (${ids.join(',')})',
      [],
      columns: [
        'id',
        'ussdDialed',
        'simSubId',
        'canRetry',
        'number',
        'amount',
      ],
    );

    debugPrint("Adding ${rawStuff.length} tasks to automated");

    for (var stuff in rawStuff) {
      await _sqliteService.insertStuff(
        {
          'code': stuff['ussdDialed'],
          'dialSim': stuff['simSubId'],
          'duration': 1,
          'startDate': getTodayMidnightMillis() + 86400000,
          'timeOfDay': getNormalTime(
            DateTime.fromMillisecondsSinceEpoch(
              getTodayMidnightMillis() + 86400000,
            ),
          ),
          'nextTaskDate': getTodayMidnightMillis() + 86400000,
          'offer': getCodeFromUssd(stuff['ussdDialed']),
          'amount': stuff['amount'],
          'number': stuff['number'],
          'deleteAfterRunning': 1,
        },
        'tasks',
      );
    }
  }

  Future<void> redoTransaction(
      int id, String ussdCode, int simSubId, int canRetry, String reply,
      {String? mpesaMessage,
      CodeSignature? codeSignature,
      bool offerResumeClaimed = false,
      bool skipForwardingCheck = false}) async {
    debugPrint(
        "Retrying transaction $id with code $ussdCode on sim $simSubId. Can retry: $canRetry. Previous reply: $reply");
    int retryTimes = await _sharedPreferencesService.getRetryMinutes() ?? 6;

    List<Map<String, dynamic>> tx = await _sqliteService.queryCustom(
      'transactions',
      'id = ?',
      [id],
      limit: 1,
    );

    if (tx.isEmpty) {
      debugPrint("Transaction with id $id not found for retry.");
      return;
    }

    final isPausedOfferTransaction =
        tx.first['status'] == TransactionStatuses.paused &&
            int.tryParse(tx.first['targetOfferId']?.toString() ?? '') != null;
    if (isPausedOfferTransaction && !offerResumeClaimed) {
      await _resumePausedOfferTransaction(id);
      return;
    }
    if (isPausedOfferTransaction &&
        (offerResumeClaimed
            ? !(tx.first['ussdReply']
                    ?.toString()
                    .startsWith(_pausedOfferResumeClaimPrefix) ??
                false)
            : tx.first['ussdReply']?.toString() ==
                _pausedOfferLocalExecutionClaim)) {
      debugPrint(
        'Skipping paused offer transaction $id; resume claim is not valid.',
      );
      return;
    }
    final pausedOfferResumeClaim =
        offerResumeClaimed ? tx.first['ussdReply']?.toString() ?? '' : '';
    final pausedOfferId = offerResumeClaimed
        ? int.tryParse(tx.first['targetOfferId']?.toString() ?? '')
        : null;

    int firstFailedTimeStamp = (tx.first['firstFailedTimeStamp'] as int?) ??
        DateTime.now().millisecondsSinceEpoch;

    if (tx.first['firstFailedTimeStamp'] == null) {
      await _sqliteService.updateStuff(
        {'firstFailedTimeStamp': firstFailedTimeStamp},
        'id = ?',
        [id],
        'transactions',
      );
    }

    MyTransaction transaction = MyTransaction.fromMap(tx.first);

    if (tx.first['status'] == TransactionStatuses.alternativeFailed ||
        tx.first['status'] == TransactionStatuses.alternativeExecuting) {
      debugPrint(
        'Skipping primary retry for alternative terminal/in-progress '
        'transaction $id (${tx.first['status']}).',
      );
      return;
    }

    // A configured recommendation-failure alternative owns this transaction
    // after the delay. Never let a manual or scheduled retry dial the primary
    // code while that alternative is pending.
    if (tx.first['status'] == TransactionStatuses.secondAttempt) {
      final offerRows = await _sqliteService.queryCustom(
        'ussdCodes',
        'amount = ?',
        [transaction.amount],
        limit: 1,
      );
      if (offerRows.isNotEmpty) {
        final variant = await _getActiveVariantWithLegacyFallback(
          offerRows.first['id'] ?? -1,
        );
        final alternative = variant?['alternativeUssdCode']?.toString();
        if (alternative != null && alternative.trim().isNotEmpty) {
          await _checkDelayedAlternativeForwards();
          return;
        }
      }
    }

    final forwardingJobId = tx.first['forwardingJobId']?.toString();

    final forwardingSenderDeviceName =
        tx.first['forwardingSenderDeviceName']?.toString();

    final forwardingRecipientDeviceName =
        tx.first['forwardingRecipientDeviceName']?.toString();

    String trimmedBody = transaction.initialMessage.length > 160
        ? transaction.initialMessage.substring(0, 160)
        : transaction.initialMessage;

    ForwardingAttemptResult? forwardingResult;
    if (!skipForwardingCheck) {
      forwardingResult = await forwardIfNeeded(
        transaction.amount,
        trimmedBody,
        transaction.initialMessage,
        transaction.transactionId,
        transaction.number,
        transaction.source,
        true,
        txId: id,
        forwardingRecipientDeviceName: forwardingRecipientDeviceName,
      );
    }

    if (forwardingResult?.state ==
        ForwardingAttemptState.forwardedSuccessfully) {
      await purgeAndMerge(forwardingResult!.transactionId!, id);
      return;
    }
    if (forwardingResult?.state ==
            ForwardingAttemptState.configuredButUnavailable ||
        forwardingResult?.state == ForwardingAttemptState.configuredButPaused) {
      await _persistUnavailableForwardingTransaction(
        transactionId: id,
        initialMessage: transaction.initialMessage,
        transactionCode: transaction.transactionId,
        number: transaction.number,
        amount: transaction.amount,
        source: transaction.source,
        parentTransactionId: transaction.parentTransactionId,
        destinationPaused: forwardingResult?.state ==
            ForwardingAttemptState.configuredButPaused,
      );
      return;
    }

    // Map<String, dynamic> transaction = tx.first;

    // if (transaction.isEmpty) {
    //   return;
    // }

    bool hasPaid = await _paymentOps.hasActiveSubscription();

    bool isUsingToken = false;

    if (!hasPaid) {
      bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;

      int tokenBalance =
          await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      if (tokenBalance > 0) {
        isUsingToken = true;
      } else if (canRenew) {
        // get last entry from payments table
        List<String> reply = await _paymentOps.autoRenewSubscription();

        if (reply[1] != TransactionStatuses.done) {
          return;
        }
      } else {
        return;
      }
    }

    int number = getNumberFromCode(ussdCode);
    int amount = getAmount(transaction.initialMessage);

    if (ussdCode.isEmpty) {
      number = extract9DigitNumber(transaction.initialMessage);
    }

    if (number == 0) {
      number = transaction.number;
    }

    if (amount <= 0) {
      amount = transaction.amount;
    }

    // if (compoundedAmount > 0) {
    //   amount = compoundedAmount;
    // }

    //print("New number: $number, amount: $amount, ussdCode: $ussdCode");

    List<Map<String, dynamic>> lecodes = (await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ?',
      [amount],
    ));

    if (lecodes.isEmpty) {
      final forwardingResult = await forwardIfNeeded(
        amount,
        trimmedBody,
        transaction.initialMessage,
        transaction.transactionId,
        number,
        transaction.source,
        false,
        status: TransactionStatuses.unavailableOffer,
        txId: id,
      );

      if (forwardingResult.state ==
          ForwardingAttemptState.forwardedSuccessfully) {
        await purgeAndMerge(forwardingResult.transactionId!, id);
        return;
      }
      if (forwardingResult.state ==
              ForwardingAttemptState.configuredButUnavailable ||
          forwardingResult.state ==
              ForwardingAttemptState.configuredButPaused) {
        await _persistUnavailableForwardingTransaction(
          transactionId: id,
          initialMessage: transaction.initialMessage,
          transactionCode: transaction.transactionId,
          number: number,
          amount: amount,
          source: transaction.source,
          parentTransactionId: transaction.parentTransactionId,
          destinationPaused: forwardingResult.state ==
              ForwardingAttemptState.configuredButPaused,
        );
        return;
      }
      if (ussdCode.isNotEmpty && simSubId > -1) {
        int? transactionId;
        transactionId = await transactGivenUssdAndDialSim(
          ussdCode,
          simSubId,
          amount,
          true,
          extract9DigitNumber(ussdCode),
          message: mpesaMessage,
        );

        await purgeAndMerge(transactionId ?? -1, id);
        return;
      }
    }

    //print("Redoing transaction $id with code $ussdCode on sim $simSubId");

    List<dynamic> ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive =
        await get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
      amount,
      number,
      simSubId,
    );
    if (offerResumeClaimed) {
      final offerId = int.tryParse(tx.first['targetOfferId']?.toString() ?? '');
      final exactOfferRows = offerId == null
          ? <Map<String, dynamic>>[]
          : await _sqliteService.queryCustom(
              'ussdCodes',
              'id = ? AND enabled = 1',
              [offerId],
              limit: 1,
            );
      if (exactOfferRows.isEmpty) {
        await _sqliteService.updateStuff(
          {
            'status': TransactionStatuses.paused,
            'ussdReply': 'Offer paused. Please check/retry.',
          },
          'id = ? AND status = ? AND ussdReply = ?',
          [id, TransactionStatuses.paused, _pausedOfferLocalExecutionClaim],
          'transactions',
        );
        return;
      }
      final exactOffer = exactOfferRows.first;
      final exactCode = await selectBongaUssdCode(offerId!);
      ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive = [
        exactCode.replaceAll(RegExp(r'n'), '0$number'),
        int.tryParse(exactOffer['dialSim']?.toString() ?? '') ?? -1,
        exactOffer['canRetry'] == 1,
        true,
        exactOffer['isAdvanced'] == 1,
        true,
      ];
    }

    if (kDebugMode) {
      debugPrint(
          "Fetched USSD and sim info for retry: $ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive");
    }

    ussdCode = ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[0];
    simSubId = ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[1];

    List<dynamic> response = [];

    // //print("Is Adv 0: ${await isAdvanced(ussdCode)}");
    // //print("is adv ${ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]}");

    if (ussdToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive[4]) {
      bool isActive =
          await _sharedPreferencesService.getAppIsActiveState() ?? false;

      if (!isActive) return;

      Map<String, dynamic> thisCode = {};
      final variantMatches = await _sqliteService.queryCustom(
        'ussdCodeVariants',
        'code = ?',
        [getCodeFromUssd(ussdCode)],
        limit: 1,
      );

      // Note: `ussdCodes` has no `code` column (it only lives on
      // `ussdCodeVariants`), so there is no legacy table to fall back to.
      if (variantMatches.isNotEmpty) {
        thisCode = variantMatches.first;
      }

      var signatureQuery = await _sqliteService.queryCustom(
        'codeSignature',
        'ussdCodeId = ?',
        [thisCode['ussdCodeId'] ?? thisCode['id'] ?? -1],
      );

      codeSignature = codeSignature ??
          CodeSignature.fromMap(
            signatureQuery.isNotEmpty ? signatureQuery.first : {},
          );

      if (kDebugMode) {
        debugPrint("so far so good");
      }

      if (offerResumeClaimed &&
          (pausedOfferId == null ||
              !await _markPausedOfferLocalExecutionStarted(
                id,
                pausedOfferId,
                pausedOfferResumeClaim,
              ))) {
        return;
      }
      response = await PhoneService().makeAdvancedRequest(
        ussdCode,
        simSubId,
        codeSignature: codeSignature,
      );

      response[1] = await transactionStatus(response);

      if ((response[0]).toString().contains("MissingPluginException")) {
        if (kDebugMode) {
          debugPrint("MissingPluginException yoo");
        }
        int? newTxId = await transactGivenUssdAndDialSim(
          ussdCode,
          simSubId,
          amount,
          true,
          extract9DigitNumber(ussdCode),
        );

        if (newTxId != null) {
          await purgeAndMerge(newTxId, id);
        }
      }
    } else {
      if (offerResumeClaimed &&
          (pausedOfferId == null ||
              !await _markPausedOfferLocalExecutionStarted(
                id,
                pausedOfferId,
                pausedOfferResumeClaim,
              ))) {
        return;
      }
      response = await PhoneService().makeMyRequest(
        ussdCode,
        simSubId,
      );
      response[1] = await transactionStatus(response);
    }

    if (response[1] == TransactionStatuses.done ||
        response[1] == TransactionStatuses.advancedUssd) {
      if (isUsingToken) {
        await _paymentOps.deductSingleToken();
      }
    }

    if (response[1] == TransactionStatuses.secondAttempt) {
      String bsatMessage = "(Number Altered by BSAT): ";
      canRetry = 20;
      if (kDebugMode) {
        debugPrint("second attempt");

        debugPrint(
          'ALT DEBUG 1: secondAttempt reached '
          'transactionId=$id, canRetry=$canRetry',
        );
      }
      Client? dbClient = await ClientService().getClientByPhone('0$number');
      if (dbClient != null &&
          dbClient.alternativePhoneNumber != null &&
          dbClient.alternativePhoneNumber!.trim().isNotEmpty) {
        int altNumber = extract9DigitNumber(dbClient.alternativePhoneNumber!);
        if (!transaction.initialMessage.contains(bsatMessage)) {
          String altMessage = replaceNumberInMessage(
            "0$number",
            dbClient.alternativePhoneNumber ?? "",
            transaction.initialMessage,
            bsatMessage,
          );
          if (altNumber != number && altNumber > 0) {
            int? newTransactionId =
                await makeTransactionGivenSmsBody(altMessage);
            if (kDebugMode) {
              debugPrint("new transaction id: $newTransactionId");
            }
            if (newTransactionId != null) {
              await purgeAndMerge(newTransactionId, id);
              // get transactionstatus of transactionId
              List<Map<String, dynamic>> txs =
                  (await _sqliteService.queryCustom(
                'transactions',
                'id = ?',
                [id],
                limit: 1,
              ));

              if (kDebugMode) {
                debugPrint(txs.toString());
              }
              if (txs.isNotEmpty) {
                if (txs.first['status'] != TransactionStatuses.secondAttempt) {
                  return;
                }
              }
            }
          }
        }
      }
    }

    canRetry = canRetry + 2;

    //print("Response: $response, canRetry: $canRetry");

    final updateFirstFailedTimeStamp =
        response[1] == TransactionStatuses.secondAttempt;
    await _sqliteService.updateOnly(
      "UPDATE transactions SET ussdDialed=?, date=?, time=?, ussdReply=?, status=?, timeStamp=?, canRetry=?, initialMessage=?${updateFirstFailedTimeStamp ? ', firstFailedTimeStamp=COALESCE(firstFailedTimeStamp, ?)' : ''} WHERE id=?",
      [
        ussdCode,
        getNormalDate(DateTime.now()),
        getNormalTime(DateTime.now()),
        response[0],
        response[1] == "" ? "No reply" : response[1],
        DateTime.now().millisecondsSinceEpoch,
        canRetry,
        transaction.initialMessage,
        if (updateFirstFailedTimeStamp) firstFailedTimeStamp,
        id,
      ],
    );
    if (updateFirstFailedTimeStamp) {
      debugPrint('[ALT FIX] transaction=$id');
      debugPrint('[ALT FIX] status=${response[1]}');
      debugPrint('[ALT FIX] firstFailedTimeStamp=$firstFailedTimeStamp');
    }
    if (response[1] == TransactionStatuses.doneConfirmed &&
        forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      debugPrint(
        'FORWARDED_SMS RETRY CONFIRMED: '
        'jobId=$forwardingJobId, '
        'senderDevice=$forwardingSenderDeviceName',
      );

      await _sendForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: forwardingSenderDeviceName,
        transactionId: id.toString(),
      );
    }
    if (canRetry < (retryTimes) &&
        (response[1] == TransactionStatuses.secondAttempt ||
            response[1] == TransactionStatuses.error)) {
      return;
    }

    amount = amount > 0
        ? amount
        : (await _sqliteService.queryCustom(
              'transactions',
              'id = ?',
              [id],
              columns: ['amount'],
            ))
                .first['amount'] ??
            '';

    number = number < 100000000
        ? extract9DigitNumber(transaction.initialMessage)
        : number;
    debugPrint(getName(transaction.initialMessage));
    debugPrint(amount.toString());
    debugPrint(number.toString());

    await processReply(
      number,
      response[1],
      getName(transaction.initialMessage).split(' ')[0],
      getName(transaction.initialMessage).trim().split(RegExp(r'\s+')).length >
              1
          ? getName(transaction.initialMessage).trim().split(RegExp(r'\s+'))[1]
          : '',
      amount,
    );
  }

  Future<List<dynamic>>
      get0USSDToDial1Sim2CanRetry3DoesExist4IsAdvanced5IsActive(
    int amount,
    int number,
    int fromId,
  ) async {
    String rawUSSD = "";
    String ussdToDial = "";
    int sim = -1;
    bool canRetry = false;
    bool doesExist = false;
    bool isAdvanced = false;
    bool enabled = true;

    final matchingOffer = await _findMatchingUssdCode(amount, fromId);
    final List<Map<String, dynamic>> ussdCodes =
        matchingOffer == null ? [] : [matchingOffer];

    debugPrint(
      'USSD DEBUG: Looking for ussdCodes amount=$amount, fromId=$fromId',
    );

    debugPrint(
      'USSD DEBUG: Matching ussdCodes: $ussdCodes',
    );

    if (ussdCodes.isNotEmpty) {
      doesExist = true;
      rawUSSD = await selectBongaUssdCode(ussdCodes.first['id']);
      sim = ussdCodes.first['dialSim'];
      ussdToDial = rawUSSD.replaceAll(RegExp(r'n'), '0$number');
      canRetry = ussdCodes.first['canRetry'] == 1;
      isAdvanced = (ussdCodes.first['isAdvanced'] != null)
          ? ussdCodes.first['isAdvanced'] == 1
          : false;
      enabled = (ussdCodes.first['enabled'] == null ||
          ussdCodes.first['enabled'] == 1);
    }

    if (sim < 0) {
      final dialSims = await _phoneService.getAllDialSims();
      sim = dialSims.isNotEmpty ? dialSims.first : -1;
    }

    return [
      ussdToDial,
      sim,
      canRetry,
      doesExist,
      isAdvanced,
      enabled,
    ];
  }

  Future<Map<String, dynamic>?> _findMatchingUssdCode(
    int amount,
    int fromId,
  ) async {
    final ussdCodes = await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ? AND (fromSim = ? OR fromSim < 0)',
      [amount, fromId],
      limit: 1,
    );
    return ussdCodes.firstOrNull;
  }

  Future<void> resumePausedTransactionsForOffer(int offerId) async {
    final transactions = await _sqliteService.queryCustom(
      'transactions',
      'status = ? AND targetOfferId = ?',
      [TransactionStatuses.paused, offerId],
      orderBy: 'timeStamp ASC',
    );
    for (final transaction in transactions) {
      final id = int.tryParse(transaction['id']?.toString() ?? '');
      if (id != null) await _resumePausedOfferTransaction(id);
    }
  }

  Future<void> _resumeEligiblePausedOfferTransactions() async {
    final transactions = await _sqliteService.queryCustom(
      'transactions',
      'status = ? AND targetOfferId IS NOT NULL',
      [TransactionStatuses.paused],
      orderBy: 'timeStamp ASC',
    );
    for (final transaction in transactions) {
      final id = int.tryParse(transaction['id']?.toString() ?? '');
      final offerId =
          int.tryParse(transaction['targetOfferId']?.toString() ?? '');
      if (id == null || offerId == null) continue;
      await _resumePausedOfferTransaction(id, expectedOfferId: offerId);
    }
  }

  Future<void> _resumePausedOfferTransaction(
    int transactionId, {
    int? expectedOfferId,
  }) async {
    if (!_activePausedOfferResumes.add(transactionId)) return;
    try {
      await _resumeClaimedPausedOfferTransaction(
        transactionId,
        expectedOfferId: expectedOfferId,
      );
    } finally {
      _activePausedOfferResumes.remove(transactionId);
    }
  }

  Future<void> _resumeClaimedPausedOfferTransaction(
    int transactionId, {
    int? expectedOfferId,
  }) async {
    final rows = await _sqliteService.queryCustom(
      'transactions',
      'id = ? AND status = ?',
      [transactionId, TransactionStatuses.paused],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final transaction = rows.first;
    final offerId =
        int.tryParse(transaction['targetOfferId']?.toString() ?? '');
    if (offerId == null ||
        (expectedOfferId != null && offerId != expectedOfferId)) {
      return;
    }

    final offerRows = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ? AND enabled = 1',
      [offerId],
      limit: 1,
    );
    if (offerRows.isEmpty) return;

    final currentReply = transaction['ussdReply']?.toString() ?? '';
    if (currentReply == _pausedForwardingReply) return;
    if (currentReply == _pausedOfferLocalExecutionClaim) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    if (currentReply.startsWith(_pausedOfferResumeClaimPrefix)) {
      final claimedAt = int.tryParse(
        currentReply.substring(_pausedOfferResumeClaimPrefix.length),
      );
      if (claimedAt == null ||
          now - claimedAt < _pausedOfferResumeClaimLease.inMilliseconds) {
        return;
      }
    }
    final claimReply = '$_pausedOfferResumeClaimPrefix$now';
    final where = transaction['ussdReply'] == null
        ? 'id = ? AND status = ? AND targetOfferId = ? AND ussdReply IS NULL'
        : 'id = ? AND status = ? AND targetOfferId = ? AND ussdReply = ?';
    final whereArgs = transaction['ussdReply'] == null
        ? <Object?>[
            transactionId,
            TransactionStatuses.paused,
            offerId,
          ]
        : <Object?>[
            transactionId,
            TransactionStatuses.paused,
            offerId,
            currentReply,
          ];
    final claimed = await _sqliteService.updateStuff(
      {'ussdReply': claimReply},
      where,
      whereArgs,
      'transactions',
    );
    if (claimed != 1) return;

    final amount = int.tryParse(transaction['amount']?.toString() ?? '') ?? 0;
    final forwardingJobId =
        transaction['forwardingJobId']?.toString().trim() ?? '';
    if (forwardingJobId.isEmpty &&
        await _hasPairedDeviceRouteForAmount(amount)) {
      final initialMessage = transaction['initialMessage']?.toString() ?? '';
      final forwardingResult = await forwardIfNeeded(
        amount,
        initialMessage.length > 160
            ? initialMessage.substring(0, 160)
            : initialMessage,
        initialMessage,
        transaction['transactionId']?.toString() ?? '',
        int.tryParse(transaction['number']?.toString() ?? '') ?? 0,
        transaction['source']?.toString() ?? '',
        true,
        txId: transactionId,
        forwardingRecipientDeviceName:
            transaction['forwardingRecipientDeviceName']?.toString(),
        parentTransactionId:
            int.tryParse(transaction['parentTransactionId']?.toString() ?? ''),
        pairedDeviceOnly: true,
      );
      if (forwardingResult.state ==
          ForwardingAttemptState.forwardedSuccessfully) {
        return;
      }

      if (forwardingResult.state ==
              ForwardingAttemptState.configuredButUnavailable ||
          forwardingResult.state ==
              ForwardingAttemptState.configuredButPaused) {
        await _persistUnavailableForwardingTransaction(
          transactionId: transactionId,
          initialMessage: transaction['initialMessage']?.toString() ?? '',
          transactionCode: transaction['transactionId']?.toString() ?? '',
          number: int.tryParse(transaction['number']?.toString() ?? '') ?? 0,
          amount: amount,
          source: transaction['source']?.toString() ?? '',
          parentTransactionId: int.tryParse(
              transaction['parentTransactionId']?.toString() ?? ''),
          destinationPaused: forwardingResult.state ==
              ForwardingAttemptState.configuredButPaused,
        );
        return;
      }

      await _sqliteService.updateStuff(
        {'ussdReply': currentReply},
        'id = ? AND status = ? AND ussdReply = ?',
        [transactionId, TransactionStatuses.paused, claimReply],
        'transactions',
      );
      return;
    }

    await redoTransaction(
      transactionId,
      transaction['ussdDialed']?.toString() ?? '',
      int.tryParse(transaction['simSubId']?.toString() ?? '') ?? -1,
      int.tryParse(transaction['canRetry']?.toString() ?? '') ?? 0,
      claimReply,
      offerResumeClaimed: true,
      skipForwardingCheck: true,
    );
  }

  Future<bool> _markPausedOfferLocalExecutionStarted(
    int transactionId,
    int offerId,
    String claimReply,
  ) async {
    final offerRows = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ? AND enabled = 1',
      [offerId],
      limit: 1,
    );
    if (offerRows.isEmpty) {
      await _sqliteService.updateStuff(
        {'ussdReply': 'Offer paused. Please check/retry.'},
        'id = ? AND status = ? AND targetOfferId = ? AND ussdReply = ?',
        [
          transactionId,
          TransactionStatuses.paused,
          offerId,
          claimReply,
        ],
        'transactions',
      );
      return false;
    }
    return await _sqliteService.updateStuff(
          {'ussdReply': _pausedOfferLocalExecutionClaim},
          'id = ? AND status = ? AND targetOfferId = ? AND ussdReply = ?',
          [
            transactionId,
            TransactionStatuses.paused,
            offerId,
            claimReply,
          ],
          'transactions',
        ) ==
        1;
  }

  Future<bool> _hasPairedDeviceRouteForAmount(int amount) async {
    final devices = await _sqliteService.queryAll('forwardingDevices');
    for (final device in devices) {
      final amounts =
          (device['amounts_to_forward']?.toString() ?? '').replaceAll(
        RegExp(r'[\[\]"]'),
        '',
      );
      if (amounts.split(',').any((value) => value.trim() == '$amount')) {
        return true;
      }
    }
    return false;
  }

  int getNumberFromCode(String code) {
    RegExp amountRegex = RegExp(r'\d{10}');
    RegExpMatch? amountMatch = amountRegex.firstMatch(code);
    return amountMatch?.group(0) != null
        ? double.parse(amountMatch!.group(0)!).truncate()
        : 0;
  }

  Future<bool> changeBlackListStatus(int number) async {
    if (await _sqliteService.getCount('blacklist',
            args: [number], appendQuery: 'WHERE number = ?') >
        0) {
      await _sqliteService.deleteWhere('blacklist', 'number = ?', [number]);
      return false;
    }
    await _sqliteService.insertStuff({'number': number}, 'blacklist');
    return true;
  }

  Future<void> checkSkipped() async {
    // print("Checking skipped transactions");

    int lastCheckSkippedTime =
        await _sharedPreferencesService.getLastCheckSkippedTime() ?? 0;
    //
    if (lastCheckSkippedTime == 0) {
      // print("No last check skipped time found. Returning.");
      await _sharedPreferencesService.setLastCheckSkippedTime(
        DateTime.now().millisecondsSinceEpoch,
      );
      return;
    }

    List<SmsMessage> smss = await getAllSince(
        DateTime.now().millisecondsSinceEpoch + 24 * 60 * 60 * 1000);

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'timeStamp > ? AND status = ?',
      [lastCheckSkippedTime, TransactionStatuses.error],
      columns: ['number'],
    );

    Set errorNumbers = rawStuff.toSet();

    for (var sms in smss) {
      int number = extract9DigitNumber(sms.body ?? "");
      if (errorNumbers.contains(number)) {
        onMessageReceive(sms);
      }
    }

    await _sharedPreferencesService.setLastCheckSkippedTime(
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<int?> dontProcess(
    String initialMessage,
    String transactionId,
    int number,
    String ussdDialed,
    int amount,
    int simSubId, {
    String? reply,
    String? status,
    String? source,
    bool? canRetry,
    int? id,
    String? forwardingJobId,
    String? forwardingSenderDeviceName,
    String? forwardingRecipientDeviceName,
    int? parentTransactionId,
    bool awaitingTopUp = false,
    int? requiredTopUp,
    int? targetAmount,
    int? targetOfferId,
  }) async {
    List<Map<String, dynamic>> transactions = await _sqliteService.queryCustom(
      'transactions',
      'id = ?',
      [id ?? -1],
    );

    if (transactions.isNotEmpty && id != null) {
      await _sqliteService.deleteStuff(id, 'transactions');
    }

    final insertedId = await _sqliteService.insertStuff(
      {
        'id': id,
        'initialMessage': initialMessage,
        'transactionId': transactionId,
        'forwardingJobId': forwardingJobId,
        'forwardingSenderDeviceName': forwardingSenderDeviceName,
        'forwardingRecipientDeviceName': forwardingRecipientDeviceName,
        'parentTransactionId': parentTransactionId,
        'awaitingTopUp': awaitingTopUp ? 1 : 0,
        'requiredTopUp': requiredTopUp,
        'targetAmount': targetAmount,
        'targetOfferId': targetOfferId,
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': ussdDialed,
        'ussdReply': reply ??
            'Error processing. Your subscription has expired. Please recharge and retry.',
        'amount': amount,
        'smsDate': getNormalDate(
          DateTime.now(),
        ),
        'smsTime': getNormalTime(
          DateTime.now(),
        ),
        'status': status ?? TransactionStatuses.error,
        'simSubId': simSubId,
        'source': source ?? 'bingwa',
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry': canRetry ?? false ? 1 : 0,
      },
      'transactions',
    );

    // Early terminal paths bypass the normal post-USSD result handling.
    if (forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty &&
        (status == TransactionStatuses.unavailableOffer ||
            status == TransactionStatuses.doneConfirmed)) {
      await _sendForwardingConfirmation(
        forwardingJobId: forwardingJobId,
        recipientDeviceName: forwardingSenderDeviceName,
        transactionId: transactionId,
        resultStatus: status ?? TransactionStatuses.doneConfirmed,
        requiredTopUp: requiredTopUp,
        targetAmount: targetAmount,
      );
    }
    return insertedId;
  }

  Future<void> _checkDelayedAlternativeForwards({
    bool useMainEngineBridge = false,
    ServiceInstance? backgroundService,
  }) async {
    final pending = await _sqliteService.queryCustom(
      'transactions',
      'status IN (?, ?)',
      [
        TransactionStatuses.secondAttempt,
        TransactionStatuses.alternativeDeliveryPending,
      ],
      columns: [
        'id',
        'status',
        'amount',
        'number',
        'simSubId',
        'initialMessage',
        'firstFailedTimeStamp',
        'forwardingJobId',
        'forwardingSenderDeviceName',
        'forwardingRecipientDeviceName',
        'alternativeRequestSenderDeviceName',
        'alternativeExecuteAt',
        'alternativeRequestCode',
        'alternativeRequestIsAdvanced',
        'alternativeDeliveryNextAttemptAt',
      ],
      orderBy: 'COALESCE(firstFailedTimeStamp, timeStamp) ASC, id ASC',
    );

    for (final tx in pending) {
      if (tx['status'] == TransactionStatuses.alternativeDeliveryPending) {
        final target =
            tx['forwardingRecipientDeviceName']?.toString() ?? '';
        if (target.isNotEmpty) {
          await dispatchNextAlternativeDelivery(target);
        }
        continue;
      }

      debugPrint(
        '[ALT DEBUG] found secondAttempt transaction=${tx['id']}',
      );
      final failedAt =
          int.tryParse(tx['firstFailedTimeStamp']?.toString() ?? '');
      debugPrint('[ALT DEBUG] failedAt=$failedAt');
      if (failedAt == null) continue;

      final codeRows = await _sqliteService.queryCustom(
        'ussdCodes',
        'amount = ?',
        [tx['amount']],
        limit: 1,
      );
      if (codeRows.isEmpty) continue;
      final variant = await _getActiveVariantWithLegacyFallback(
        codeRows.first['id'] ?? -1,
      );
      final altCode = variant?['alternativeUssdCode']?.toString();
      final target = variant?['runAltOn']?.toString();
      final delay =
          int.tryParse(variant?['altDelayMinutes']?.toString() ?? '') ?? 0;
      if (altCode == null || altCode.trim().isEmpty) continue;
      final executeAt = int.tryParse(
            tx['alternativeExecuteAt']?.toString() ?? '',
          ) ??
          (failedAt + delay * 60000);
      if (tx['alternativeExecuteAt'] == null) {
        await _sqliteService.updateStuff(
          {'alternativeExecuteAt': executeAt},
          'id = ?',
          [tx['id']],
          'transactions',
        );
      }
      final now = DateTime.now().millisecondsSinceEpoch;
      final due = executeAt > 0 && now >= executeAt;
      debugPrint(
        '[ALT DEBUG] altDelayMinutes=$delay',
      );
      debugPrint('[ALT DEBUG] executeAt=$executeAt');
      debugPrint('[ALT DEBUG] now=$now');
      debugPrint('[ALT DEBUG] due=$due');

      if (!due) continue;

      final number = int.tryParse(tx['number']?.toString() ?? '') ?? 0;
      final transactionId = int.tryParse(tx['id'].toString());
      if (number <= 0 || transactionId == null) continue;
      final processedCode = replaceNWithNumber(altCode, number);
      final isAdvanced = (variant?['altIsAdvanced'] ?? 0) == 1;
      debugPrint(
        '[ALT DEBUG] executing alternative for transaction=$transactionId',
      );
      debugPrint('[ALT DEBUG] alternativeCode=$altCode');
      debugPrint(
        '[ALT DEBUG] altIsAdvanced=${variant?['altIsAdvanced'] ?? 0}',
      );

      if (target == null || target.trim().isEmpty) {
        // Leave the retryable state before dialing to avoid duplicate runs.
        await _sqliteService.updateOnly(
          'UPDATE transactions SET status = ?, alternativeExecuteAt = -1 WHERE id = ? AND status = ?',
          [
            TransactionStatuses.alternativeExecuting,
            transactionId,
            TransactionStatuses.secondAttempt
          ],
        );
        final signatureRows = isAdvanced
            ? await _sqliteService.queryCustom(
                'codeSignature',
                'ussdCodeId = ?',
                [variant?['ussdCodeId'] ?? codeRows.first['id'] ?? -1],
                limit: 1,
              )
            : <Map<String, dynamic>>[];
        final simSubId = int.tryParse(tx['simSubId']?.toString() ?? '') ?? -1;
        final signature = signatureRows.isEmpty
            ? null
            : CodeSignature.fromMap(signatureRows.first);
        final List<dynamic> altResponse = useMainEngineBridge
            ? backgroundService == null
                ? <String>[
                    'Background service instance is required for the main-engine USSD bridge.',
                    'alternative-failed',
                  ]
                : await executeAlternativeUssdOnMainEngine(
                    service: backgroundService,
                    code: processedCode,
                    subscriptionId: simSubId,
                    isAdvanced: isAdvanced,
                    codeSignature: signature,
                  )
            : isAdvanced
                ? await PhoneService().makeAdvancedRequest(
                    processedCode,
                    simSubId,
                    codeSignature: signature,
                  )
                : await PhoneService().makeMyRequest(processedCode, simSubId);
        final executionStatus = altResponse.length > 1
            ? altResponse[1]?.toString()
            : TransactionStatuses.error;
        if (executionStatus == 'alternative-failed' ||
            executionStatus == TransactionStatuses.error ||
            executionStatus == TransactionStatuses.secondAttempt) {
          altResponse[1] = TransactionStatuses.alternativeFailed;
        } else {
          altResponse[1] = await transactionStatus(altResponse);
          if (altResponse[1] == TransactionStatuses.error ||
              altResponse[1] == TransactionStatuses.secondAttempt) {
            altResponse[1] = TransactionStatuses.alternativeFailed;
          }
        }
        final latestRows = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [transactionId],
          columns: ['status', 'ussdReply'],
          limit: 1,
        );
        final latestStatus = latestRows.firstOrNull?['status']?.toString();
        final bool smsAlreadyConfirmed =
            latestStatus == TransactionStatuses.doneConfirmed;
        final bool smsAlreadyFailed =
            latestStatus == TransactionStatuses.alternativeFailed;
        final finalAlternativeStatus = smsAlreadyConfirmed || smsAlreadyFailed
            ? latestStatus
            : altResponse[1];

        final alternativeUpdateRows = await _sqliteService.updateStuff(
          {
            'ussdDialed': processedCode,
            'ussdReply': smsAlreadyConfirmed || smsAlreadyFailed
                ? latestRows.first['ussdReply']?.toString() ?? ''
                : altResponse[0]?.toString() ?? '',
            'status': finalAlternativeStatus,
            'timeStamp': DateTime.now().millisecondsSinceEpoch,
          },
          'id = ? AND (status IS NULL OR status != ?)',
          [transactionId, TransactionStatuses.doneConfirmed],
          'transactions',
        );
        final transactionRows = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [transactionId],
          limit: 1,
        );
        final forwardingJobId =
            transactionRows.firstOrNull?['forwardingJobId']?.toString();
        final senderDevice = transactionRows
            .firstOrNull?['forwardingSenderDeviceName']
            ?.toString();
        final alternativeSucceeded =
            finalAlternativeStatus == TransactionStatuses.doneConfirmed;

        if (alternativeUpdateRows == 1 &&
            alternativeSucceeded &&
            forwardingJobId != null &&
            forwardingJobId.isNotEmpty &&
            senderDevice != null &&
            senderDevice.isNotEmpty) {
          debugPrint(
            'LOCAL ALTERNATIVE CONFIRMED: '
            'transactionId=$transactionId, '
            'forwardingJobId=$forwardingJobId, '
            'status=$finalAlternativeStatus, '
            'sending confirmation to=$senderDevice',
          );

          await _sendForwardingConfirmation(
            forwardingJobId: forwardingJobId,
            recipientDeviceName: senderDevice,
            transactionId: transactionId.toString(),
          );
        }
        continue;
      }

      var devices = await _sqliteService.queryCustom(
        'forwardingDevices',
        'device_name = ?',
        [target],
      );
      if (devices.isEmpty) {
        devices = await _sqliteService.queryCustom(
          'whitelistedDevices',
          'device_name = ?',
          [target],
        );
      }
      if (devices.isEmpty) continue;

      var remoteForwardingJobId = tx['forwardingJobId']?.toString() ?? '';
      final alternativeRequestSenderDeviceName =
          await SharedPreferencesService().getDeviceName() ?? 'Unknown Device';
      final previousSenderDeviceName =
          tx['forwardingSenderDeviceName']?.toString() ?? '';

      if (remoteForwardingJobId.isEmpty) {
        if (previousSenderDeviceName.isNotEmpty) {
          debugPrint(
            'ALT FORWARD DISPATCH: transaction=$transactionId came from '
            '$previousSenderDeviceName but has no forwardingJobId; '
            'not generating a replacement ID',
          );
          continue;
        }

        // This node is originating the remote alternative job. Assign its
        // first job ID here and persist it before sending; never replace an
        // ID supplied by an upstream forwarding node.
        final createdJobId = ForwardingJobId.generate(
          mpesaCode: getMpesaCode(tx['initialMessage']?.toString() ?? ''),
        );
        await _sqliteService.updateStuff(
          {'forwardingJobId': createdJobId},
          'id = ? AND (forwardingJobId IS NULL OR forwardingJobId = ?)',
          [transactionId, ''],
          'transactions',
        );
        final storedJobRows = await _sqliteService.queryCustom(
          'transactions',
          'id = ?',
          [transactionId],
          columns: ['id', 'forwardingJobId'],
          limit: 1,
        );
        remoteForwardingJobId =
            storedJobRows.firstOrNull?['forwardingJobId']?.toString() ?? '';
        if (remoteForwardingJobId.isEmpty) {
          debugPrint(
            'ALT FORWARD DISPATCH: could not persist an originating '
            'forwardingJobId for transaction=$transactionId',
          );
          continue;
        }
        debugPrint(
          'ALT FORWARD JOB CREATED: '
          'localTransactionId=$transactionId, '
          'forwardingJobId=$remoteForwardingJobId',
        );
      }

      final persistedRows = await _sqliteService.updateStuff(
        {
          'status': TransactionStatuses.alternativeDeliveryPending,
          'forwardingJobId': remoteForwardingJobId,
          'forwardingRecipientDeviceName': target,
          'alternativeRequestSenderDeviceName':
              alternativeRequestSenderDeviceName,
          'alternativeQueueState': 'waiting',
          'alternativeRequestCode': processedCode,
          'alternativeRequestIsAdvanced': isAdvanced ? 1 : 0,
          'alternativeExecuteAt': -1,
          'alternativeDeliveryNextAttemptAt': null,
          'ussdReply': 'Alternative request queued for $target.',
        },
        'id = ? AND status = ?',
        [transactionId, TransactionStatuses.secondAttempt],
        'transactions',
      );
      if (persistedRows == 1) {
        debugPrint(
          'ALT_QUEUE: recipient=$target waiting=T$transactionId',
        );
        await dispatchNextAlternativeDelivery(target);
      }
    }
  }

  Future<void> dispatchNextAlternativeDelivery(
    String recipientDeviceName,
  ) async {
    if (recipientDeviceName.isEmpty) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final active = await _sqliteService.claimNextAlternativeDelivery(
      recipientDeviceName: recipientDeviceName,
      now: now,
      nextAttemptAt: now + const Duration(seconds: 20).inMilliseconds,
    );
    if (active == null) {
      final activeRows = await _sqliteService.queryCustom(
        'transactions',
        'forwardingRecipientDeviceName = ? AND '
            'alternativeRequestCode IS NOT NULL AND '
            'alternativeQueueState = ? AND status IN (?, ?, ?)',
        [
          recipientDeviceName,
          'active',
          TransactionStatuses.alternativeDeliveryPending,
          TransactionStatuses.forwardedPending,
          TransactionStatuses.alternativeAmbiguous,
        ],
        columns: ['id'],
        orderBy: 'COALESCE(firstFailedTimeStamp, timeStamp) ASC, id ASC',
        limit: 1,
      );
      if (activeRows.isNotEmpty) {
        debugPrint(
          'ALT_QUEUE: recipient=$recipientDeviceName '
          'blocked by active=T${activeRows.first['id']}',
        );
      }
      return;
    }

    debugPrint(
      'ALT_QUEUE: recipient=$recipientDeviceName active=T${active['id']}',
    );
    debugPrint(
      'ALT_QUEUE: recipient=$recipientDeviceName '
      'dispatching T${active['id']}',
    );
    await _sendPendingAlternativeDelivery(active);
  }

  Future<void> _sendPendingAlternativeDelivery(
    Map<String, dynamic> tx,
  ) async {
    final transactionId = int.tryParse(tx['id']?.toString() ?? '');
    final jobId = tx['forwardingJobId']?.toString() ?? '';
    final target = tx['forwardingRecipientDeviceName']?.toString() ?? '';
    final code = tx['alternativeRequestCode']?.toString() ?? '';
    if (transactionId == null ||
        jobId.isEmpty ||
        target.isEmpty ||
        code.isEmpty) {
      debugPrint(
        'ALT DELIVERY PENDING: required persisted fields missing '
        'transaction=${tx['id']}, job=$jobId, target=$target',
      );
      return;
    }

    final sender = tx['alternativeRequestSenderDeviceName']?.toString() ??
        await SharedPreferencesService().getDeviceName() ??
        'Unknown Device';
    debugPrint(
      'ALT DELIVERY SEND: job=$jobId, target=$target, '
      'transaction=$transactionId',
    );
    final result = await BackendService().post(
      '/api/fcm/send-secure',
      body: {
        'title': 'BSAT Online Forwarding',
        'body': 'Forwarded alternative USSD request',
        'senderDeviceName': sender,
        'recipientDeviceName': target,
        'data': {
          'type': 'process_alt_request',
          'transactionId': transactionId.toString(),
          'forwardingJobId': jobId,
          'senderDeviceName': sender,
          'recipientDeviceName': target,
          'ussdCode': code,
          'isAdvanced':
              tx['alternativeRequestIsAdvanced'] == 1 ? 'true' : 'false',
          'smsMessage': tx['initialMessage']?.toString() ?? '',
          'body': 'Forwarded alternative USSD request',
          'title': 'Forwarded Code',
        },
      },
    );
    debugPrint(
      'ALT DELIVERY ${result['success'] == true ? 'BACKEND ACCEPTED' : 'RETRY'}: '
      'job=$jobId, target=$target, '
      'awaiting C receipt; result=$result',
    );
  }

  Future<void> retryAll(
    bool isAutoRetrying, {
    bool useMainEngineBridge = false,
    ServiceInstance? backgroundService,
  }) async {
    await _recoverStaleAlternativeRequests();
    await _resumeReservedAlternativeRequests();
    await _recoverSuccessfulPendingAlternativeResults();
    await _retryPendingForwardedAlternativeResults();
    await _resumeEligiblePausedOfferTransactions();

    // Alternative routing has its own delay and must not be blocked by normal
    // retry settings or the offer-change guard.
    await _checkDelayedAlternativeForwards(
      useMainEngineBridge: useMainEngineBridge,
      backgroundService: backgroundService,
    );

    bool mightHaveChanged =
        await _sharedPreferencesService.getOffersMightHaveChanged() ?? false;

    if (isAutoRetrying && mightHaveChanged) {
      return;
    }

    int retryTimes = await _sharedPreferencesService.getRetryMinutes() ?? 6;

    retryTimes *= 2;

    // print("Retrying. all: ${await _sqliteService.queryAll('transactions')}");

    String query = '''
     (status = ? AND (canRetry >= 1 OR canRetry = ? OR canRetry IS NULL)) 
     OR 
     (status = ? AND date = ? AND canRetry < $retryTimes)
    ''';

    List<Object> args = [
      TransactionStatuses.error,
      isAutoRetrying ? 1 : 0,
      TransactionStatuses.timedOut,
      getNormalDate(DateTime.now()),
      // TransactionStatuses.advance
    ];

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      query,
      args,
      columns: [
        'id',
        'ussdDialed',
        'simSubId',
        'canRetry',
        'ussdReply',
        'amount',
        'initialMessage'
      ],
    );

    //print('Retrying all: ${rawStuff.length}');

    // debugPrint('Retrying all transactions: ${rawStuff}');

    for (var stuff in rawStuff) {
      List<Map<String, dynamic>> codeMap = await _sqliteService.queryCustom(
        'ussdCodes',
        'amount = ?',
        [rawStuff.first['amount']],
        limit: 1,
      );

      CodeSignature? signature;
      if (codeMap.isNotEmpty) {
        signature = CodeSignature.fromMap(
          (await _sqliteService.queryCustom(
                'codeSignature',
                'ussdCodeId = ?',
                [codeMap.first['id'] ?? -1],
              ))
                  .firstOrNull ??
              {},
        );

        Map<String, dynamic> code = codeMap.first;

        if (code.isNotEmpty) {
          if (code['enabled'] != 1) {
            continue;
          }
        }
      }

      debugPrint(' retrytimes $retryTimes, canRetry ${stuff['canRetry']}');
      await redoTransaction(
        stuff['id'],
        stuff['ussdDialed'],
        stuff['simSubId'],
        stuff['canRetry'] ?? 0,
        stuff["ussdReply"],
        codeSignature: signature,
      );
    }
  }

  Future<void> retryTransactionsGivenIds(List<int> ids) async {
    if (ids.isEmpty) return;

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      'id IN (${ids.join(',')})',
      [],
      columns: ['id', 'ussdDialed', 'simSubId', 'canRetry', 'ussdReply'],
    );

    for (var stuff in rawStuff) {
      await redoTransaction(stuff['id'], stuff['ussdDialed'], stuff['simSubId'],
          stuff['canRetry'] ?? 0, stuff["ussdReply"]);
    }
  }

  Future<bool> reserveAlternativeRequest({
    required String forwardingJobId,
    required String transactionId,
    required String ussdCode,
    required bool isAdvanced,
    required String smsMessage,
    required String senderDeviceName,
    required String recipientDeviceName,
  }) async {
    if (forwardingJobId.isEmpty || transactionId.isEmpty || ussdCode.isEmpty) {
      return false;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final inserted = await _sqliteService.reserveAlternativeJob({
      'forwardingJobId': forwardingJobId,
      'transactionId': transactionId,
      'state': 'eligibility_pending',
      'ussdCode': ussdCode,
      'isAdvanced': isAdvanced ? 1 : 0,
      'smsMessage': smsMessage,
      'senderDeviceName': senderDeviceName,
      'recipientDeviceName': recipientDeviceName,
      'createdAt': now,
      'updatedAt': now,
    });
    debugPrint(
      'ALT DELIVERY ${inserted ? 'PERSIST' : 'DUPLICATE'}: '
      'job=$forwardingJobId, target=$recipientDeviceName',
    );
    return inserted;
  }

  Future<Map<String, dynamic>?> getAlternativeRequest(
    String forwardingJobId,
  ) {
    return _sqliteService.getAlternativeJob(forwardingJobId);
  }

  Future<bool> activateAlternativeRequest(String forwardingJobId) async {
    return await _sqliteService.updateAlternativeJob(
          forwardingJobId,
          {
            'state': 'reserved',
            'updatedAt': DateTime.now().millisecondsSinceEpoch,
          },
          expectedState: 'eligibility_pending',
        ) ==
        1;
  }

  Future<void> discardIneligibleAlternativeRequest(
    String forwardingJobId,
  ) async {
    await _sqliteService.deleteAlternativeJob(
      forwardingJobId,
      expectedState: 'eligibility_pending',
    );
  }

  Future<void> processReservedAlternativeRequest(
    String forwardingJobId,
  ) async {
    final job = await _sqliteService.getAlternativeJob(forwardingJobId);
    if (job == null) return;

    final state = job['state']?.toString();
    if (state == 'executing') {
      await _reconcileExecutingAlternativeRequest(job);
      return;
    }
    if (state == 'completed' || state == 'ambiguous') {
      final resultStatus = job['resultStatus']?.toString() ?? '';
      if (resultStatus.isNotEmpty &&
          resultStatus != TransactionStatuses.successfulPending &&
          resultStatus != TransactionStatuses.advancedUssd) {
        await _queueForwardedAlternativeResult(
          forwardingJobId: forwardingJobId,
          state: state!,
          status: resultStatus,
          transactionId: job['localTransactionId']?.toString() ??
              job['transactionId']?.toString() ??
              '',
          ussdReply: job['ussdReply']?.toString() ?? '',
        );
      }
      return;
    }
    if (state != 'reserved') return;

    final executionStartedAt = DateTime.now().millisecondsSinceEpoch;
    final claimed = await _sqliteService.updateAlternativeJob(
      forwardingJobId,
      {
        'state': 'executing',
        'executionStartedAt': executionStartedAt,
        'updatedAt': executionStartedAt,
      },
      expectedState: 'reserved',
    );
    if (claimed != 1) return;

    // Keep the durable claim before dialing; a crash afterward leaves an
    // ambiguous carrier outcome, so this job must not be executed again.
    final ussdCode = job['ussdCode']?.toString() ?? '';
    final smsMessage = job['smsMessage']?.toString() ?? '';
    if (ussdCode.isEmpty) return;

    final simSubId = await PhoneService().mostCommonDialSim();
    final amount = getAmount(smsMessage);
    final number = extract9DigitNumber(smsMessage);
    final insertedId = await transactGivenUssdAndDialSim(
      ussdCode,
      simSubId,
      amount,
      job['isAdvanced'] == 1,
      number,
      message: smsMessage,
      forwardingJobId: forwardingJobId,
      forwardingTransactionId: getMpesaCode(smsMessage),
      forwardingSenderDeviceName: job['senderDeviceName']?.toString(),
      forwardingRecipientDeviceName: job['recipientDeviceName']?.toString(),
    );

    final transactionRows = insertedId == null
        ? <Map<String, dynamic>>[]
        : await _sqliteService.queryCustom(
            'transactions',
            'id = ?',
            [insertedId],
            columns: ['status', 'ussdReply'],
            limit: 1,
          );
    final hasRecordedTransaction = transactionRows.isNotEmpty;
    final resultStatus = hasRecordedTransaction
        ? transactionRows.first['status']?.toString() ?? 'unknown'
        : TransactionStatuses.alternativeAmbiguous;
    final resultReply = hasRecordedTransaction
        ? transactionRows.first['ussdReply']?.toString() ?? ''
        : 'Alternative execution returned without a durable transaction '
            'outcome; it was not automatically dialed again.';
    final resultState = resultStatus == TransactionStatuses.alternativeAmbiguous
        ? 'ambiguous'
        : resultStatus == TransactionStatuses.successfulPending ||
                resultStatus == TransactionStatuses.advancedUssd
            ? 'awaiting_confirmation'
            : 'completed';
    await _sqliteService.updateAlternativeJob(
      forwardingJobId,
      {
        'localTransactionId': insertedId,
        'state': resultState,
        'resultStatus': resultStatus,
        if (resultStatus == TransactionStatuses.successfulPending)
          'resultDeliveryState': 'pending',
        'ussdReply': resultReply,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
      },
      expectedState: 'executing',
    );
    if (resultStatus == TransactionStatuses.successfulPending) {
      await _reportForwardedAlternativeFirstSuccess(
        forwardingJobId: forwardingJobId,
        transactionId:
            insertedId?.toString() ?? job['transactionId']?.toString() ?? '',
        ussdReply: resultReply,
      );
    } else if (resultStatus.isNotEmpty &&
        resultStatus != TransactionStatuses.successfulPending &&
        resultStatus != TransactionStatuses.advancedUssd) {
      await _queueForwardedAlternativeResult(
        forwardingJobId: forwardingJobId,
        state: 'completed',
        status: resultStatus,
        transactionId:
            insertedId?.toString() ?? job['transactionId']?.toString() ?? '',
        ussdReply: resultReply,
      );
    }
  }

  Future<void> _reconcileExecutingAlternativeRequest(
    Map<String, dynamic> job,
  ) async {
    final forwardingJobId = job['forwardingJobId']?.toString() ?? '';
    if (forwardingJobId.isEmpty) return;
    final existingTransactions = await _sqliteService.queryCustom(
      'transactions',
      'forwardingJobId = ?',
      [forwardingJobId],
      orderBy: 'timeStamp DESC',
      limit: 1,
    );
    if (existingTransactions.isNotEmpty) {
      final transaction = existingTransactions.first;
      final status = transaction['status']?.toString() ?? '';
      final awaitingConfirmation =
          status == TransactionStatuses.successfulPending ||
              status == TransactionStatuses.advancedUssd;
      final firstSuccess = status == TransactionStatuses.successfulPending;
      final nextState =
          awaitingConfirmation ? 'awaiting_confirmation' : 'completed';
      await _sqliteService.updateAlternativeJob(
        forwardingJobId,
        {
          'localTransactionId': transaction['id'],
          'state': nextState,
          'resultStatus': status,
          'ussdReply': transaction['ussdReply']?.toString() ?? '',
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
        },
        expectedState: 'executing',
      );
      if (firstSuccess) {
        await _reportForwardedAlternativeFirstSuccess(
          forwardingJobId: forwardingJobId,
          transactionId: transaction['id']?.toString() ?? '',
          ussdReply: transaction['ussdReply']?.toString() ?? '',
        );
        return;
      }
      if (status.isNotEmpty && !awaitingConfirmation && status != 'unknown') {
        await _queueForwardedAlternativeResult(
          forwardingJobId: forwardingJobId,
          state: 'completed',
          status: status,
          transactionId: transaction['id'].toString(),
          ussdReply: transaction['ussdReply']?.toString() ?? '',
        );
      }
      return;
    }

    final updatedAt = int.tryParse(job['updatedAt']?.toString() ?? '') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (updatedAt == 0 ||
        now - updatedAt < const Duration(minutes: 5).inMilliseconds) {
      return;
    }

    const ambiguousReply =
        'Alternative USSD outcome is unknown after interruption. '
        'It was not automatically dialed again.';
    final updated = await _sqliteService.updateAlternativeJob(
      forwardingJobId,
      {
        'state': 'ambiguous',
        'resultStatus': TransactionStatuses.alternativeAmbiguous,
        'ussdReply': ambiguousReply,
        'updatedAt': now,
      },
      expectedState: 'executing',
    );
    if (updated == 1) {
      await _queueForwardedAlternativeResult(
        forwardingJobId: forwardingJobId,
        state: 'ambiguous',
        status: TransactionStatuses.alternativeAmbiguous,
        transactionId: job['transactionId']?.toString() ?? '',
        ussdReply: ambiguousReply,
      );
    }
  }

  Future<void> _resumeReservedAlternativeRequests() async {
    final reserved = await _sqliteService.getAlternativeJobsByState('reserved');
    for (final job in reserved) {
      await processReservedAlternativeRequest(
        job['forwardingJobId']?.toString() ?? '',
      );
    }
  }

  Future<void> _recoverStaleAlternativeRequests() async {
    final eligibilityPending =
        await _sqliteService.getAlternativeJobsByState('eligibility_pending');
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final job in eligibilityPending) {
      final updatedAt = int.tryParse(job['updatedAt']?.toString() ?? '') ?? 0;
      if (updatedAt == 0 ||
          now - updatedAt < const Duration(minutes: 5).inMilliseconds) {
        continue;
      }
      final forwardingJobId = job['forwardingJobId']?.toString() ?? '';
      if (forwardingJobId.isEmpty) continue;
      const reply = 'Alternative eligibility processing was interrupted '
          'before USSD execution; it was not automatically dialed.';
      final updated = await _sqliteService.updateAlternativeJob(
        forwardingJobId,
        {
          'state': 'completed',
          'resultStatus': TransactionStatuses.alternativeFailed,
          'ussdReply': reply,
          'updatedAt': now,
        },
        expectedState: 'eligibility_pending',
      );
      if (updated == 1) {
        await _queueForwardedAlternativeResult(
          forwardingJobId: forwardingJobId,
          state: 'completed',
          status: TransactionStatuses.alternativeFailed,
          transactionId: job['transactionId']?.toString() ?? '',
          ussdReply: reply,
        );
      }
    }

    final executing =
        await _sqliteService.getAlternativeJobsByState('executing');
    for (final job in executing) {
      await _reconcileExecutingAlternativeRequest(job);
    }
  }

  Future<void> retrySpecific(
    bool errors,
    bool successful,
    bool retrySuccPending,
    bool failed,
    bool paused,
    bool okoa,
    bool advanced,
    int startTime,
    int endTime,
  ) async {
    String query = 'status = ? OR status = ? OR status = ?';
    List args = [];

    int checkCount = 0;

    if (errors) {
      checkCount++;
      query = 'status = ?';
      args.add(TransactionStatuses.error);
    }
    if (successful) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status LIKE ?';
      }
      checkCount++;
      args.add(TransactionStatuses.done);
    }
    if (failed) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status = ?';
      }
      checkCount++;
      args.add(TransactionStatuses.secondAttempt);
    }
    if (paused) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status = ?';
      }
      checkCount++;
      args.add(TransactionStatuses.paused);
    }
    if (okoa) {
      if (checkCount > 0) {
        query += ' OR status = ?';
      } else {
        query = 'status = ?';
      }
      checkCount++;
      args.add(TransactionStatuses.hasOkoa);
    }
    if (advanced) {
      if (checkCount > 0) {
        query += ' OR (status = ? OR status = ?)';
      } else {
        query = '(status = ? OR status = ?)';
      }
      checkCount++;
      args.add(TransactionStatuses.advancedUssd);
      args.add(TransactionStatuses.advancedQueue);
    }
    if (retrySuccPending) {
      if (checkCount > 0) {
        query += ' OR (status = ? AND canRetry < ?)';
      } else {
        query = '(status = ? AND canRetry < ?)';
      }
      checkCount++;
      args.add(TransactionStatuses.done);
    }

    List<Map<String, dynamic>> rawStuff = await _sqliteService.queryCustom(
      'transactions',
      '($query) AND timeStamp >= ? AND timeStamp <= ?',
      [...args, startTime, endTime],
      columns: ['id', 'ussdDialed', 'simSubId', 'canRetry', 'ussdReply'],
    );

    for (var stuff in rawStuff) {
      await redoTransaction(stuff['id'], stuff['ussdDialed'], stuff['simSubId'],
          stuff['canRetry'] ?? 0, stuff["ussdReply"]);
    }
  }

  Future<bool> numberIsBlacklisted(int number) async {
    int blacklistExists = await _sqliteService
        .getCount('blacklist', appendQuery: 'WHERE number = ?', args: [number]);

    return blacklistExists > 0;
  }

  Future<void> processReply(
    int number,
    String transactionStatus,
    String firstName,
    String lastName,
    int amount,
  ) async {
    final reply = await _findReplyFor(transactionStatus, amount);
    var message = '';
    if (reply != null) {
      message = fillReplyTemplate(
        reply['reply'],
        number: number,
        firstName: firstName,
        lastName: lastName,
        amount: amount,
      );
    }

    List similar = await searchSentSms(
      '254$number',
      message.substring(
        0,
        message.length > 160 ? 160 : message.length,
      ),
      getTodayMidnightMillis(),
    );

    if (similar.isNotEmpty) return;

    sendEvenInBackground('254$number', message);
  }

  Future<String> transactionStatus(List response) async {
    debugPrint("Response: ${response[0]}");

    final String responseText =
        response.isNotEmpty ? response[0].toString() : '';

    // 1) Check custom codes first
    final List<Map<String, dynamic>> customCodes =
        await _sqliteService.getCustomCodes();

    for (final row in customCodes) {
      final String pattern = (row['pattern'] ?? '').toString().trim();
      final String mappedStatus = (row['transactionStatus'] ?? '').toString();
      final bool isCaseSensitive = (row['isCaseSensitive'] ?? 0) == 1;

      if (pattern.isEmpty || mappedStatus.isEmpty) continue;

      final bool matches = isCaseSensitive
          ? responseText.contains(pattern)
          : responseText.toLowerCase().contains(pattern.toLowerCase());

      if (matches) {
        return mappedStatus;
      }
    }

    if (responseText
        .contains(RegExp(r'Invalid choice', caseSensitive: false))) {
      return TransactionStatuses.paused;
    }

    if (responseText == "Success") {
      return TransactionStatuses.error;
    }

    // Successful (Confirmed):
    // A purchase confirmation is final. Recommendation success/commission
    // wording remains pending here because the later Safaricom SMS is the
    // confirmation source for recommendations.
    if (RegExp(
      r'successfully purchased|continue connecting|have purchased',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      debugPrint(
        "TRANSACTION STATUS DEBUG: confirmed success response matched "
        "-> doneConfirmed",
      );
      return TransactionStatuses.doneConfirmed;
    }

    // Successful (Pending):
// The recommendation has been submitted successfully, but the final
// confirmation message has not yet been received.
    if (RegExp(
      r'submitted successfully|successfully recommended offer|total commission',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      debugPrint(
        "TRANSACTION STATUS DEBUG: submitted success response matched "
        "-> successfulPending",
      );
      return TransactionStatuses.successfulPending;
    }

    if (RegExp(
            r'bundle activation request has failed|okoa|pool state|Authentication failure',
            caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.hasOkoa;
    }

    if (RegExp(
      r'USSD session already in progress',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'max number of menu|error from application23',
            caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'connection code error|one minute', caseSensitive: false)
        .hasMatch(responseText)) {
      return TransactionStatuses.timedOut;
    }

    if (RegExp(r'queue', caseSensitive: false).hasMatch(responseText)) {
      return TransactionStatuses.advancedQueue;
    }

    if (RegExp(
      r'error|duplicate|not available|unavailable|max number|try again|apologize|invalid|sorry|mmi complete|timed out',
      caseSensitive: false,
    ).hasMatch(responseText)) {
      return TransactionStatuses.error;
    }

    if (RegExp(r'already', caseSensitive: false).hasMatch(responseText)) {
      return TransactionStatuses.secondAttempt;
    }

    debugPrint(
      "TRANSACTION STATUS DEBUG: no success pattern matched. "
      "response=[$responseText], existingStatus=[${response[1]}]",
    );

    return response[1];
  }

  Future<int?> transactGivenUssdAndDialSim(
    String ussdCode,
    int simSubId,
    int amount,
    bool isAdvanced,
    int number, {
    String? message,
    String? forwardingJobId,
    String? forwardingTransactionId,
    String? forwardingSenderDeviceName,
    String? forwardingRecipientDeviceName,
  }) async {
    bool hasPaid = await _paymentOps.hasActiveSubscription();

    bool isUsingToken = false;

    // bool hasPaid = await _paymentOps.hasActiveSubscription();

    if (!hasPaid) {
      bool canRenew = await _sharedPreferencesService.getAutoRenew() ?? false;
      int tokenBalance =
          await _sharedPreferencesService.getDeliveryTokens() ?? 0;

      if (tokenBalance > 0) {
        isUsingToken = true;
      } else if (canRenew) {
        // get last entry from payments table
        List<String> reply = await _paymentOps.autoRenewSubscription();

        if (reply[1] != TransactionStatuses.done) {
          return await dontProcess(
            message ?? "",
            "00",
            number,
            ussdCode,
            amount,
            simSubId,
            source: "manual",
            reply: 'No subscription found. Please renew.',
          );
        }
      } else {
        return dontProcess(
          message ?? "",
          "00",
          number,
          ussdCode,
          amount,
          simSubId,
          source: "manual",
        );
      }
    }

    List<dynamic> response = [];

    if (isAdvanced) {
      if (forwardingJobId != null && forwardingJobId.isNotEmpty) {
        debugPrint(
          'ALT USSD: advanced request started jobId=$forwardingJobId',
        );
      }
      String transStatus = TransactionStatuses.advancedUssd;
      String msg = 'Advanced. Added to queue.';

      bool anotherRunning = PhoneService.isRunning;

      if (anotherRunning) {
        transStatus = TransactionStatuses.error;
        msg = "Waiting for turn ...";
        return await dontProcess(
          message ?? "",
          "00",
          number,
          ussdCode,
          amount,
          simSubId,
          status: transStatus,
          reply: msg,
          canRetry: true,
          source: "manual",
        );
      }

      response = await _phoneService.makeAdvancedRequest(
        ussdCode,
        simSubId,
      );
    } else {
      response = await _phoneService.makeMyRequest(
        ussdCode,
        simSubId,
      );
    }

    if (isUsingToken &&
        (response[1] == TransactionStatuses.done ||
            response[1] == TransactionStatuses.advancedUssd)) {
      await _paymentOps.deductSingleToken();
    }

    response[1] = await transactionStatus(response);

    final insertedId = await _sqliteService.insertStuff(
      {
        'initialMessage': message ?? 'Manual',
        'transactionId': forwardingTransactionId ?? '',
        'number': number,
        'date': getNormalDate(DateTime.now()),
        'time': getNormalTime(DateTime.now()),
        'ussdDialed': ussdCode,
        'ussdReply': response[0],
        'amount': amount,
        'smsDate': getNormalDate(DateTime.now()),
        'smsTime': getNormalTime(DateTime.now()),
        'simSubId': simSubId,
        'status': response[1],
        'timeStamp': DateTime.now().millisecondsSinceEpoch,
        'canRetry': 1,
        'forwardingJobId': forwardingJobId ?? '',
        'forwardingSenderDeviceName': forwardingSenderDeviceName ?? '',
        'forwardingRecipientDeviceName': forwardingRecipientDeviceName ?? '',
        'source': 'manual',
      },
      'transactions',
    );
    debugPrint(
      'ALT USSD STORED: localTransactionId=$insertedId, '
      'forwardingTransactionId=${forwardingTransactionId ?? ''}, '
      'forwardingJobId=${forwardingJobId ?? ''}, '
      'sender=${forwardingSenderDeviceName ?? ''}, '
      'recipient=${forwardingRecipientDeviceName ?? ''}',
    );

    if (forwardingJobId != null &&
        forwardingJobId.isNotEmpty &&
        forwardingSenderDeviceName != null &&
        forwardingSenderDeviceName.isNotEmpty) {
      if (response[1] != TransactionStatuses.doneConfirmed) {
        debugPrint(
          'ALT USSD: status=${response[1]} is not final; '
          'waiting for doneConfirmed jobId=$forwardingJobId, '
          'localTransactionId=$insertedId',
        );
        return insertedId;
      }

      debugPrint(
        'ALT FORWARD RESULT: '
        'localTransactionId=$insertedId, '
        'forwardingTransactionId=$forwardingTransactionId, '
        'forwardingJobId=$forwardingJobId, '
        'status=${response[1]}, '
        'senderDevice=$forwardingSenderDeviceName',
      );

      final durableAlternative =
          await _sqliteService.getAlternativeJob(forwardingJobId);
      if (durableAlternative == null) {
        final senderDeviceName =
            (await _sharedPreferencesService.getDeviceName()) ?? '';

        final result = await BackendService().post(
          '/api/fcm/send-secure',
          body: {
            'title': 'BSAT Online Forwarding',
            'body': 'Alternative USSD execution result',
            'senderDeviceName': senderDeviceName,
            'recipientDeviceName': forwardingSenderDeviceName,
            'data': {
              'type': 'forwarded_alt_result',
              'transactionId': insertedId.toString(),
              'forwardingJobId': forwardingJobId,
              'status': response[1],
              'ussdReply': response[0]?.toString() ?? '',
              'senderDeviceName': senderDeviceName,
              'recipientDeviceName': forwardingSenderDeviceName,
            },
          },
        );
        debugPrint(
          'ALT RESULT: legacy direct result sent '
          'jobId=$forwardingJobId, status=${response[1]}, result=$result',
        );
      }
    }

    return insertedId;
  }

  String replaceNWithNumber(String ussdCode, int number) {
    return ussdCode.replaceAll(RegExp(r'n'), '0$number');
  }

  Future<double> getThisWeekCommision() async {
    List sales = await _sqliteService.queryCustom(
      'transactions',
      'timeStamp >= ? AND ussdDialed LIKE "%*180*%"',
      [getLastSundayMidnightMillis()],
    );

    double totalAmount =
        sales.fold(0, (sum, sale) => sum + (sale['amount'] ?? 0));
    return (totalAmount * 0.1);
  }

  Future<bool> isAdvanced(String code) async {
    String ussdRaw = getCodeFromUssd(code);

    // Note: `ussdCodes` has no `code` column (it only lives on
    // `ussdCodeVariants`), so there is no legacy table to fall back to.
    List offers = await _sqliteService.queryCustom(
      'ussdCodeVariants',
      'code = ?',
      [ussdRaw],
      columns: ['isAdvanced'],
    );

    return offers.isNotEmpty && offers.first['isAdvanced'] == 1;
  }

  String getCodeFromUssd(String code) {
    // Extract the 10-digit number from the USSD code
    RegExp amountRegex = RegExp(r'\d{10}');
    RegExpMatch? amountMatch = amountRegex.firstMatch(code);

    if (amountMatch != null) {
      // Get the matched amount
      String amount = amountMatch.group(0)!;

      // Replace the amount with 'n'
      String modifiedCode = code.replaceFirst(amount, 'n');

      return modifiedCode;
    }

    // Return original code if no match is found
    return code;
  }

  Future<void> updateWithMessage(TransactionMessage smsMessage) async {
    final confirmationBody = smsMessage.body ?? '';
    final isGiftConfirmation = RegExp(
      r'you\s+have\s+gifted',
      caseSensitive: false,
    ).hasMatch(confirmationBody);
    final hasCaringPhrase = RegExp(
      r'thank\s+you\s+for\s+caring',
      caseSensitive: false,
    ).hasMatch(confirmationBody);

    if (isGiftConfirmation && hasCaringPhrase) {
      debugPrint('SAFARICOM CONFIRMATION: confirmation SMS detected');

      // This confirmation SMS carries the offer price, while its recipient
      // phone number may be masked. Use the amount to locate the original
      // advanced transaction; proceed only when the match is unambiguous.
      final amountMatch = RegExp(
        r'\b(?:kshs?|kes)\s*([\d,]+)(?:\.\d+)?',
        caseSensitive: false,
      ).firstMatch(confirmationBody);
      final amount = int.tryParse(
        amountMatch?.group(1)?.replaceAll(',', '') ?? '',
      );
      debugPrint(
        'SAFARICOM CONFIRMATION: Safaricom amount=${amount ?? 'unknown'}',
      );

      final recipientMatch = RegExp(
        r'\bto\s+([+\d\s().-]*\*{2,})',
        caseSensitive: false,
      ).firstMatch(confirmationBody);
      final maskedRecipient = recipientMatch?.group(1) ?? '';
      var visibleRecipientPrefix = normalizeIncomingCallNumber(
        maskedRecipient.replaceAll('*', ''),
      );
      if (!visibleRecipientPrefix.startsWith('0') &&
          visibleRecipientPrefix.length >= 7 &&
          visibleRecipientPrefix.length <= 9) {
        visibleRecipientPrefix = '0$visibleRecipientPrefix';
      }
      if (visibleRecipientPrefix.isEmpty) {
        debugPrint(
          'SAFARICOM CONFIRMATION: could not extract masked recipient prefix',
        );
        return;
      }

      debugPrint(
        'SAFARICOM CONFIRMATION: amount=$amount, '
        'maskedRecipientPrefix=$visibleRecipientPrefix',
      );

      final smsTimestamp = smsMessage.date;
      if (smsTimestamp == null || smsTimestamp <= 0) {
        debugPrint(
          'SAFARICOM CONFIRMATION: missing SMS timestamp; leaving unresolved',
        );
        return;
      }

      final recipientDigits =
          visibleRecipientPrefix.replaceAll(RegExp(r'\D'), '');
      final nationalPrefix = recipientDigits.startsWith('0')
          ? recipientDigits.substring(1)
          : recipientDigits;
      final diagnosticRows = await _sqliteService.queryCustom(
        'transactions',
        'amount = ? OR CAST(number AS TEXT) LIKE ? OR '
            'CAST(number AS TEXT) LIKE ?',
        [amount ?? -1, '$nationalPrefix%', '254$nationalPrefix%'],
        columns: ['id', 'number', 'amount', 'status', 'timeStamp'],
        orderBy: 'timeStamp DESC',
      );

      for (final row in diagnosticRows) {
        final transactionId = row['id'];
        final rawNumber = row['number']?.toString() ?? '';
        final rawNumberDigits = rawNumber.replaceAll(RegExp(r'\D'), '');
        var normalizedNumber = normalizeIncomingCallNumber(rawNumber);
        if (normalizedNumber.length == 9 &&
            !rawNumberDigits.startsWith('254')) {
          normalizedNumber = '0$normalizedNumber';
        }
        final transactionAmount = int.tryParse(row['amount']?.toString() ?? '');
        final transactionTimestamp =
            int.tryParse(row['timeStamp']?.toString() ?? '');
        final transactionStatus = row['status']?.toString() ?? '';
        final amountMatched = transactionAmount == amount;
        final recipientPrefixMatched =
            normalizedNumber.startsWith(visibleRecipientPrefix);
        const timestampCorrelationWindowMs = 2 * 60 * 1000;
        final timestampMatched = transactionTimestamp != null &&
            (transactionTimestamp - smsTimestamp).abs() <=
                timestampCorrelationWindowMs;
        final statusMatched =
            transactionStatus == TransactionStatuses.advancedUssd ||
                transactionStatus == TransactionStatuses.successfulPending;

        if (!amountMatched ||
            !recipientPrefixMatched ||
            !timestampMatched ||
            !statusMatched) {
          debugPrint(
            'SAFARICOM CONFIRMATION DIAGNOSTIC: '
            'id=$transactionId, number=$rawNumber, '
            'amount=${row['amount']}, status=$transactionStatus, '
            'transactionTimestamp=${row['timeStamp']}, '
            'smsTimestamp=$smsTimestamp, '
            'normalizedNumber=$normalizedNumber, '
            'normalizedSmsPrefix=$visibleRecipientPrefix, '
            'amountMatched=$amountMatched, '
            'recipientPrefixMatched=$recipientPrefixMatched, '
            'timestampMatched=$timestampMatched, '
            'statusMatched=$statusMatched',
          );
        }
      }

      final amountAndStatusMatches = await _sqliteService.queryCustom(
        'transactions',
        'status IN (?, ?)',
        [
          TransactionStatuses.advancedUssd,
          TransactionStatuses.successfulPending,
        ],
        orderBy: 'timeStamp DESC',
      );

      final candidates = <Map<String, dynamic>>[];
      for (final transaction in amountAndStatusMatches) {
        final transactionTimestamp = int.tryParse(
          transaction['timeStamp']?.toString() ?? '',
        );
        const timestampCorrelationWindowMs = 2 * 60 * 1000;
        if (transactionTimestamp == null ||
            (transactionTimestamp - smsTimestamp).abs() >
                timestampCorrelationWindowMs) {
          debugPrint(
            'SAFARICOM CONFIRMATION: rejecting candidate '
            'id=${transaction['id']} due to timestamp outside '
            '${timestampCorrelationWindowMs}ms correlation window',
          );
          continue;
        }

        final rawNumber = transaction['number']?.toString() ?? '';
        final rawNumberDigits = rawNumber.replaceAll(RegExp(r'\D'), '');
        var normalizedNumber = normalizeIncomingCallNumber(rawNumber);
        if (normalizedNumber.length == 9 &&
            !rawNumberDigits.startsWith('254')) {
          normalizedNumber = '0$normalizedNumber';
        }

        if (!normalizedNumber.startsWith(visibleRecipientPrefix)) {
          debugPrint(
            'SAFARICOM CONFIRMATION: rejecting candidate '
            'id=${transaction['id']} due to recipient prefix',
          );
          continue;
        }
        candidates.add(transaction);
      }

      debugPrint(
        'SAFARICOM CONFIRMATION: eligible candidates=${candidates.length}',
      );

      if (candidates.length != 1) {
        if (candidates.isEmpty) {
          debugPrint(
            'SAFARICOM CONFIRMATION: ambiguous alternative jobs cannot be '
            'safely matched from a masked recipient; leaving unresolved',
          );
        }
        debugPrint(
          candidates.isEmpty
              ? 'SAFARICOM CONFIRMATION: zero candidates; leaving unresolved'
              : 'SAFARICOM CONFIRMATION: multiple candidates; '
                  'leaving unresolved',
        );
        return;
      }

      final candidate = candidates.first;
      final transactionId = candidate['id'];
      final previousStatus = candidate['status']?.toString() ?? '';
      debugPrint(
        'SAFARICOM CONFIRMATION: transaction=$transactionId '
        'statusBefore=$previousStatus amount=$amount',
      );

      final updatedRows = await _sqliteService.updateStuff(
        {
          'status': TransactionStatuses.doneConfirmed,
          'ussdReply': '${confirmationBody.trim()}\n$interpunct '
              '${candidate['ussdReply'] ?? ''}',
          'timeStamp': DateTime.now().millisecondsSinceEpoch,
          'canRetry': 0,
        },
        'id = ? AND status IN (?, ?)',
        [
          transactionId,
          TransactionStatuses.advancedUssd,
          TransactionStatuses.successfulPending,
        ],
        'transactions',
      );

      final updated = await _sqliteService.queryCustom(
        'transactions',
        'id = ?',
        [transactionId],
        limit: 1,
      );
      final updatedStatus = updated.firstOrNull?['status']?.toString();
      debugPrint(
        'SAFARICOM CONFIRMATION: transaction=$transactionId '
        'statusAfter=$updatedStatus',
      );

      if (updatedRows == 1 &&
          updatedStatus == TransactionStatuses.doneConfirmed) {
        debugPrint(
          'SAFARICOM CONFIRMATION: confirmed transaction=$transactionId',
        );
        final forwardingJobId = candidate['forwardingJobId']?.toString() ?? '';
        final forwardingSender =
            candidate['forwardingSenderDeviceName']?.toString() ?? '';
        if (forwardingJobId.isNotEmpty && forwardingSender.isNotEmpty) {
          final finalReply = updated.firstOrNull?['ussdReply']?.toString() ??
              confirmationBody.trim();
          final isAlternativeResult =
              candidate['source']?.toString() == 'manual' &&
                  await _completeForwardedAlternativeJobFromConfirmation(
                    forwardingJobId: forwardingJobId,
                    transactionId: transactionId.toString(),
                    ussdReply: finalReply,
                  );
          if (isAlternativeResult) {
            debugPrint(
              'ALT CONFIRMED: Safaricom confirmation matched '
              'jobId=$forwardingJobId, localTransactionId=$transactionId',
            );
          } else {
            debugPrint(
              'SAFARICOM CONFIRMATION: sending forwarding ACK '
              'for transaction=$transactionId',
            );
            await _sendForwardingConfirmation(
              forwardingJobId: forwardingJobId,
              recipientDeviceName: forwardingSender,
              transactionId: transactionId.toString(),
            );
          }
        }
      }
      return;
    }

    final body = smsMessage.body ?? '';
    final purchaseConfirmed = RegExp(
      r'thank\s+you\s+for\s+choosing\s+safaricom'
      r'.*?you\s+have\s+purchased\s+.+?'
      r'(?:for\s+\d+)?',
      caseSensitive: false,
      dotAll: true,
    ).hasMatch(body);
    final recommendationSubmitted = RegExp(
      r'recommendation\s+for\s+\d+\s+submitted\s+successfully',
      caseSensitive: false,
    ).hasMatch(body);
    final recommendationSuccessful = RegExp(
      r'you\s+have\s+successfully\s+recommended\s+offer',
      caseSensitive: false,
    ).hasMatch(body);
    final hasTotalCommission = RegExp(
      r'total\s+commission',
      caseSensitive: false,
    ).hasMatch(body);
    final recommendationFailed = RegExp(
      r'recommendation\s+failed',
      caseSensitive: false,
    ).hasMatch(body);

    if (!purchaseConfirmed &&
        !recommendationSubmitted &&
        !recommendationSuccessful &&
        !hasTotalCommission &&
        !recommendationFailed) {
      return;
    }

    final confirmed =
        purchaseConfirmed || recommendationSuccessful || hasTotalCommission;
    final targetStatus = recommendationFailed
        ? TransactionStatuses.secondAttempt
        : confirmed
            ? TransactionStatuses.doneConfirmed
            : TransactionStatuses.successfulPending;

    // Safaricom confirmations can omit the M-PESA code and offer amount. Only
    // use amount when the SMS ties a currency value directly to the offer or
    // bundle; weekly Total Commission is not the purchase amount.
    // A recipient can itself be ten digits, so only treat a ten-character
    // token containing both a letter and a digit as an M-PESA code here.
    final codeMatch = RegExp(
      r'\b(?=[A-Z0-9]*[A-Z])(?=[A-Z0-9]*[0-9])[A-Z0-9]{10}\b',
      caseSensitive: false,
    ).firstMatch(body);
    final code = codeMatch?.group(0) ?? '';
    final recipientMatch = RegExp(
      r'\b(?:to|for)\s+((?:\+?254|0)?[\d][\d\s().-]{7,15})',
      caseSensitive: false,
    ).firstMatch(body);
    final recipientDigits =
        recipientMatch?.group(1)?.replaceAll(RegExp(r'\D'), '') ?? '';
    final normalizedRecipientNumber =
        recipientDigits.length >= 9 && recipientDigits.length <= 12
            ? normalizeIncomingCallNumber(recipientDigits)
            : '';
    final recipientNumber = normalizedRecipientNumber.length == 9
        ? '0$normalizedRecipientNumber'
        : normalizedRecipientNumber;
    final amountMatch = RegExp(
      r'(?:offer|bundle|purchase|purchased)[^\n]{0,35}?(?:kshs?|kes)\s*([\d,]+)'
      r'|(?:kshs?|kes)\s*([\d,]+)[^\n]{0,25}?(?:offer|bundle|purchase)',
      caseSensitive: false,
    ).firstMatch(body);
    final confirmationAmount = int.tryParse(
      (amountMatch?.group(1) ?? amountMatch?.group(2) ?? '')
          .replaceAll(',', ''),
    );
    final smsTimestamp = smsMessage.date;

    if (code.isEmpty && recipientNumber.isEmpty) {
      debugPrint(
        'SAFARICOM CONFIRMATION: no transaction code or recipient; '
        'leaving unresolved',
      );
      return;
    }
    if (smsTimestamp == null || smsTimestamp <= 0) {
      debugPrint(
        'SAFARICOM CONFIRMATION: missing SMS timestamp; leaving unresolved',
      );
      return;
    }

    const confirmationWindowMs = 20 * 60 * 1000;
    final eligibleTransactions = await _sqliteService.queryCustom(
      'transactions',
      'status IN (?, ?, ?) AND timeStamp BETWEEN ? AND ?',
      [
        TransactionStatuses.successfulPending,
        TransactionStatuses.advancedUssd,
        TransactionStatuses.alternativeExecuting,
        smsTimestamp - confirmationWindowMs,
        smsTimestamp + confirmationWindowMs,
      ],
      columns: [
        'id',
        'transactionId',
        'number',
        'amount',
        'timeStamp',
        'status',
        'ussdReply',
        'source',
        'forwardingJobId',
        'forwardingSenderDeviceName',
        'firstFailedTimeStamp',
      ],
    );

    var candidates = eligibleTransactions;
    if (code.isNotEmpty) {
      candidates = candidates
          .where((row) => row['transactionId']?.toString() == code)
          .toList();
    }
    if (recipientNumber.isNotEmpty) {
      candidates = candidates.where((row) {
        final storedNumber = normalizeIncomingCallNumber(
          row['number']?.toString() ?? '',
        );
        final rawStoredDigits =
            (row['number']?.toString() ?? '').replaceAll(RegExp(r'\D'), '');
        final normalizedStoredNumber =
            storedNumber.length == 9 && !rawStoredDigits.startsWith('254')
                ? '0$storedNumber'
                : storedNumber;
        return normalizedStoredNumber == recipientNumber;
      }).toList();
    }
    if (confirmationAmount != null) {
      candidates = candidates
          .where((row) =>
              int.tryParse(row['amount']?.toString() ?? '') ==
              confirmationAmount)
          .toList();
    }

    if (candidates.length != 1) {
      if (candidates.isEmpty &&
          targetStatus == TransactionStatuses.doneConfirmed) {
        final resolvedAmbiguous =
            await _completeAmbiguousAlternativeFromConfirmation(
          recipientNumber: recipientNumber,
          confirmationAmount: confirmationAmount,
          smsTimestamp: smsTimestamp,
          confirmationBody: body,
        );
        if (resolvedAmbiguous) return;
      }
      debugPrint(
        'SAFARICOM CONFIRMATION: ${candidates.isEmpty ? 'no' : 'ambiguous'} '
        'eligible match; candidates=${candidates.length}, code=$code, '
        'recipient=$recipientNumber, amount=$confirmationAmount. '
        'Leaving transactions unchanged.',
      );
      return;
    }

    final candidate = candidates.single;
    final transactionId = candidate['id'];
    final currentStatus = candidate['status']?.toString() ?? '';
    final status = recommendationFailed
        ? (currentStatus == TransactionStatuses.alternativeExecuting
            ? TransactionStatuses.alternativeFailed
            : TransactionStatuses.secondAttempt)
        : targetStatus;
    final updatedRows = await _sqliteService.updateStuff(
      {
        'ussdReply': '$body \n$interpunct ${candidate['ussdReply'] ?? ''}',
        'status': status,
        if (status == TransactionStatuses.secondAttempt)
          'firstFailedTimeStamp': candidate['firstFailedTimeStamp'] ??
              DateTime.now().millisecondsSinceEpoch,
        if (status == TransactionStatuses.doneConfirmed) 'canRetry': 0,
      },
      'id = ? AND status IN (?, ?, ?)',
      [
        transactionId,
        TransactionStatuses.successfulPending,
        TransactionStatuses.advancedUssd,
        TransactionStatuses.alternativeExecuting,
      ],
      'transactions',
    );
    if (updatedRows != 1) {
      debugPrint(
        'SAFARICOM CONFIRMATION: transaction=$transactionId was not updated '
        '(row count=$updatedRows); leaving state unchanged',
      );
      return;
    }

    final number = int.tryParse(candidate['number']?.toString() ?? '') ?? 0;
    final amount = int.tryParse(candidate['amount']?.toString() ?? '') ?? 0;
    debugPrint(
      'SAFARICOM CONFIRMATION: updated transaction=$transactionId '
      'from=$currentStatus to=$status',
    );

    if (status == TransactionStatuses.successfulPending &&
        candidate['source']?.toString() == 'manual') {
      final forwardingJobId = candidate['forwardingJobId']?.toString() ?? '';
      if (forwardingJobId.isNotEmpty) {
        debugPrint(
          'ALT_QUEUE: T$transactionId Successful(Pending)',
        );
        await _reportForwardedAlternativeFirstSuccess(
          forwardingJobId: forwardingJobId,
          transactionId: transactionId.toString(),
          ussdReply: body,
        );
      }
    }

    if (status == TransactionStatuses.doneConfirmed) {
      final forwardingJobId = candidate['forwardingJobId']?.toString() ?? '';
      final forwardingSender =
          candidate['forwardingSenderDeviceName']?.toString() ?? '';
      if (forwardingJobId.isNotEmpty && forwardingSender.isNotEmpty) {
        final isAlternativeResult =
            candidate['source']?.toString() == 'manual' &&
                await _completeForwardedAlternativeJobFromConfirmation(
                  forwardingJobId: forwardingJobId,
                  transactionId: transactionId.toString(),
                  ussdReply: body,
                );
        if (!isAlternativeResult) {
          await _sendForwardingConfirmation(
            forwardingJobId: forwardingJobId,
            recipientDeviceName: forwardingSender,
            transactionId: transactionId.toString(),
          );
        }
      }
    }

    processReply(
      number,
      status,
      (candidate['source'] ?? 'unknown').toString().split(' ').first,
      (candidate['source'] ?? 'unknown').toString().split(' ').length > 1
          ? (candidate['source'] ?? 'unknown').toString().split(' ')[1]
          : '',
      amount,
    );
  }

  String alterMpesaMessage(String smsMessage, int amount) {
    return smsMessage.replaceFirst(
      RegExp(
        r'(?:(((K?)sh(s?)[\s:]?)|kes[\s:]?)(\d{1,6}(?:,\d{3})*(?:\.\d+)?))|(\d{1,6}(?:,\d{3})*(?:\.\d+)?)[\s:]?((K?)sh(s?)|kes)',
        caseSensitive: false,
      ),
      'Ksh$amount.00',
    );
  }

  String fillReplyTemplate(
    String template, {
    required int number,
    String? firstName,
    String? lastName,
    int? amount,
  }) {
    return template
        .replaceAll('grti?', getGreeting(withEmoji: false))
        .replaceAll('numb?', number.toString())
        .replaceAll('fnam?', firstName ?? '')
        .replaceAll('lnam?', lastName ?? '')
        .replaceAll('amnt?', amount?.toString() ?? '')
        .replaceAll('time?', getNormalTime(DateTime.now()))
        .replaceAll('date?', getNormalDate(DateTime.now()))
        .replaceAll('dayw?', getDayOfWeek(DateTime.now()));
  }

  Future<void> recordClientPurchase(
      String phoneNumber, String senderName) async {
    final clientService = ClientService();

    // Check if client exists
    Client? existingClient = await clientService.getClientByPhone(phoneNumber);

    if (existingClient != null) {
      // Update existing client
      final updatedClient = existingClient.copyWith(
        lastBought: DateTime.now(),
        noOfPurchases: existingClient.noOfPurchases + 1,
      );
      await clientService.updateClient(updatedClient);
    } else {
      // Create new client
      final nameParts = senderName.trim().split(' ');
      final firstName = nameParts.isNotEmpty ? nameParts.first : 'Unknown';
      final lastName =
          nameParts.length > 1 ? nameParts.skip(1).join(' ') : 'Client';

      final newClient = Client(
        firstName: firstName,
        lastName: lastName,
        phoneNumber: phoneNumber,
        createdAt: DateTime.now(),
        lastBought: DateTime.now(),
        noOfPurchases: 1,
      );

      await clientService.insertClient(newClient);
    }
  }

  Future<String> selectBongaUssdCode(int id) async {
    // Load the ussdCodes row
    List<Map<String, dynamic>> ussdCodeItem = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [id],
    );

    if (ussdCodeItem.isEmpty) return '';

    final row = ussdCodeItem.first;

    debugPrint('USSD DEBUG: ussdCodes row for id=$id: $row');

    final variants = await _sqliteService.queryCustom(
      'ussdCodeVariants',
      'ussdCodeId = ?',
      [id],
    );

    debugPrint('USSD DEBUG: variants for id=$id: $variants');

// choose active variant code for this ussdCode id
    String activeCode = await _getActiveVariantCode(row['id']);

    debugPrint('USSD DEBUG: activeCode for id=$id: "$activeCode"');

    if (row['usesBongaPoints'] == null || row['usesBongaPoints'] == 0) {
      return activeCode;
    }

    List<dynamic> reply = await _phoneService.makeMyRequest(
      row['balanceCheckCode'],
      row['dialSim'],
    );

    int bongaBalance = await getBongaBalance(reply[0]);

    if (bongaBalance > (row['bongaPointsPerTransaction'] ?? 0)) {
      return activeCode;
    }

    return row['fallbackCode'] ?? activeCode;
  }

  Future<String> _getActiveVariantCode(int ussdCodeId) async {
    try {
      final variant = await _getActiveVariantRow(ussdCodeId);

      if (variant == null) {
        return '';
      }

      return variant['code']?.toString() ?? '';
    } catch (e) {
      return '';
    }
  }

  Future<Map<String, dynamic>?> _getActiveVariantRow(int ussdCodeId) async {
    final variants = await _sqliteService.queryCustom(
      'ussdCodeVariants',
      'ussdCodeId = ?',
      [ussdCodeId],
    );

    if (variants.isEmpty) {
      return null;
    }

    final now = DateTime.now();
    final curMin = now.hour * 60 + now.minute;

    Map<String, dynamic>? fallback;
    for (final variant in variants) {
      fallback ??= variant;
      final s = variant['startTime']?.toString() ?? '';
      final e = variant['endTime']?.toString() ?? '';
      if (s.isEmpty && e.isEmpty) return variant;
      if (s.isEmpty || e.isEmpty) return variant;

      try {
        final sParts = s.split(':');
        final eParts = e.split(':');
        final sMin = int.parse(sParts[0]) * 60 + int.parse(sParts[1]);
        final eMin = int.parse(eParts[0]) * 60 + int.parse(eParts[1]);
        if (sMin <= eMin) {
          if (curMin >= sMin && curMin < eMin) return variant;
        } else {
          if (curMin >= sMin || curMin < eMin) return variant;
        }
      } catch (_) {
        return variant;
      }
    }

    return fallback;
  }

  Future<Map<String, dynamic>?> _getActiveVariantWithLegacyFallback(
    int ussdCodeId,
  ) async {
    final variantRow = await _getActiveVariantRow(ussdCodeId);
    final legacyRows = await _sqliteService.queryCustom(
      'ussdCodes',
      'id = ?',
      [ussdCodeId],
      limit: 1,
    );

    if (variantRow == null) {
      return legacyRows.isNotEmpty
          ? Map<String, dynamic>.from(legacyRows.first)
          : null;
    }

    // Query rows from sqflite are read-only; copy before mutating below.
    final variant = Map<String, dynamic>.from(variantRow);

    if (legacyRows.isNotEmpty) {
      final legacy = legacyRows.first;
      variant['alternativeUssdCode'] ??= legacy['alternativeUssdCode'];
      variant['runAltOn'] ??= legacy['runAltOn'];
      variant['altIsAdvanced'] ??= legacy['altIsAdvanced'];
      variant['altDelayMinutes'] ??= legacy['altDelayMinutes'];
    }

    return variant;
  }

  Future<Map<String, dynamic>> getOfferSignature(
      String code, int number, int simSubId) async {
    code = replaceNWithNumber(code, number);
    PhoneService phoneService = PhoneService();
    return (await phoneService.makeMyRequest(
      code,
      simSubId,
    ))[2];
  }

  Future<void> unmaskFromCall(String number) async {
    number = normalizeIncomingCallNumber(number);

    if (number.isEmpty) {
      return;
    }

    // llok for transactions with status masked which can
    // fit the number in the initialMessage

    List<Map<String, dynamic>> transactions = await _sqliteService.queryCustom(
      'transactions',
      'status = ?',
      [TransactionStatuses.masked],
    );

    for (var transaction in transactions) {
      String initialMessage = transaction['initialMessage'] ?? '';
      String? unmaskedReply = unmaskNumberInMessage(number, initialMessage);

      if (unmaskedReply != null) {
        int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
        if (newTxId != null) {
          await purgeAndMerge(newTxId, transaction['id']);
        }
        return;
      }
    }

    // unmaskNumberInMessage(number, message)
  }

  Future<UssdCode> getUssdCodeForAmount(int amount) async {
    List response = await _sqliteService.queryCustom(
      'ussdCodes',
      'amount = ?',
      [amount],
    );

    if (response.isEmpty) {
      // Return a default UssdCode
      return UssdCode(
        id: -1,
        code: '',
        amount: 0,
        fromSim: -1,
        canRetry: false,
        isAdvanced: false,
        enabled: false,
      );
    }

    final ussdId = response.first['id'];
    final variantCode = await _getActiveVariantCode(ussdId);

    return UssdCode(
      id: response.first['id'],
      code: variantCode,
      amount: response.first['amount'] ?? 0,
      fromSim: response.first['fromSim'],
      canRetry: response.first['canRetry'] != 0,
      isAdvanced: response.first['isAdvanced'] != 0,
      enabled: response.first['enabled'] != 0,
    );
  }

  // check if sms message has "please call" and if it does,
  // extract the number from the address and look for a transaction
  // that is TransactionStatuses.paused with that hashed number in the message
  // and unmask the message and return it
  Future<String?> sortClientText(SmsMessage message) async {
    if (message.body != null
        // &&
        //     RegExp(r'please call|tried to|tried calling', caseSensitive: false)
        //         .hasMatch(message.body!)
        ) {
      int number = extract9DigitNumber(message.address ?? "");
      int numberInText = extract9DigitNumber(message.body ?? "");

      // remove leading 254 if present
      if (number.toString().startsWith('254')) {
        number = int.parse(number.toString().substring(3));
      }

      List<Map<String, dynamic>> pausedTransactions = await _sqliteService
          .queryCustom('transactions', 'status = ? OR status = ?',
              [TransactionStatuses.masked, TransactionStatuses.paused]);

      if (pausedTransactions.isNotEmpty) {
        for (var transaction in pausedTransactions) {
          String initialMessage = transaction['initialMessage'] ?? '';
          String? unmaskedReply =
              unmaskNumberInMessage('0$number', initialMessage);

          if (unmaskedReply != null) {
            int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
            if (newTxId != null) {
              await purgeAndMerge(newTxId, transaction['id']);
            }
            return unmaskedReply;
          }

          unmaskedReply =
              unmaskNumberInMessage('0$numberInText', initialMessage);
          if (unmaskedReply != null) {
            int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
            if (newTxId != null) {
              await purgeAndMerge(newTxId, transaction['id']);
            }
            return unmaskedReply;
          }
        }
      }

      // check message content for a valid phone number(s) using extract9DigitNumber
      sortMessageContent(message);
    }
    return null;
  }

  Future<String?> sortMessageContent(SmsMessage smsMessage) async {
    // reply might contain phone number.
    int number = extract9DigitNumber(smsMessage.body ?? "");

    String mpesaCode = getMpesaCode(smsMessage.body ?? "");

    if (number == 0) return null;

    Map<String, dynamic>? transaction = (await _sqliteService.queryCustom(
      'transactions',
      '(status = ? OR status = ?) AND transactionId = ?',
      [TransactionStatuses.masked, TransactionStatuses.paused, mpesaCode],
    ))
        .firstOrNull;

    if (transaction == null) return null;

    // for (var transaction in transactions) {
    String initialMessage = transaction['initialMessage'] ?? '';
    String? unmaskedReply = unmaskNumberInMessage('0$number', initialMessage);

    if (unmaskedReply != null) {
      // new client
      Client client = Client.fromMpesaMessage(unmaskedReply);

      await recordClientPurchase(
          client.phoneNumber, "${client.firstName} ${client.lastName}");

      int? newTxId = await makeTransactionGivenSmsBody(unmaskedReply);
      if (newTxId != null) {
        await purgeAndMerge(newTxId, transaction['id']);
      }
      return unmaskedReply;
    }

    return null;
  }

  String normalizeIncomingCallNumber(String? number) {
    if (number == null || number.trim().isEmpty) {
      return '';
    }

    String normalized = number.replaceAll(RegExp(r'[^0-9+]'), '');

    if (normalized.startsWith('+254')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('254')) {
      normalized = '0${normalized.substring(3)}';
    }

    if (normalized.length < 7) {
      return '';
    }

    return normalized;
  }

  // autoScheduleFailedRecommendations
  Future<void> autoScheduleFailedRecommendations() async {
    int timestamp24HoursAgo = DateTime.now().millisecondsSinceEpoch -
        Duration(hours: 24).inMilliseconds;

    List<Map<String, dynamic>> failedRecommendations = await _sqliteService
        .queryCustom('transactions', 'status = ? AND timestamp > ?',
            [TransactionStatuses.secondAttempt, timestamp24HoursAgo]);

    for (var recommendation in failedRecommendations) {
      String? initialMessage = recommendation['initialMessage'];

      if (initialMessage != null) {
        initialMessage = "Yesterday's transaction redone: $initialMessage";

        int? newTxId = await makeTransactionGivenSmsBody(initialMessage);
        if (newTxId != null) {
          await purgeAndMerge(newTxId, recommendation['id']);
        }
      }
    }
  }

  /// Batch upload clients to server at midnight ±50 minutes.
  /// Max 1000 clients per day. Sends 50 clients per request.
  /// Tracks last uploaded client ID to resume from where it left off.
  Future<void> uploadClientsToBatchServer() async {
    try {
      const int maxClientsPerDay = 1000;
      const int clientsPerRequest = 50;
      final BackendService backendService = BackendService();

      // Check if we've already uploaded today
      String? lastUploadDate = await getClientBatchUploadDate();
      String todayDate = DateTime.now().toIso8601String().split('T')[0];

      int uploadedToday = 0;

      // Reset counter if it's a new day
      if (lastUploadDate != todayDate) {
        uploadedToday = 0;
        await setClientBatchUploadDate(todayDate);
        await setClientBatchUploadCount(0);
      } else {
        uploadedToday = await getClientBatchUploadCount();
      }

      // Check if we've exceeded daily limit
      if (uploadedToday >= maxClientsPerDay) {
        debugPrint(
            'Client batch upload: Daily limit ($maxClientsPerDay) reached');
        return;
      }

      // Get the last uploaded client ID
      int? lastUploadedId = await getLastUploadedClientId();
      lastUploadedId ??= 0;

      // Query all clients ordered by ID, starting after the last uploaded ID
      List<Map<String, dynamic>> allClients = await _sqliteService.queryAll(
        'clients',
        where: 'id > ?',
        whereArgs: [lastUploadedId],
        orderBy: 'id ASC',
      );

      if (allClients.isEmpty) {
        debugPrint('Client batch upload: No new clients to upload');
        return;
      }

      // Calculate how many clients we can upload today
      int remainingQuota = maxClientsPerDay - uploadedToday;
      int clientsToUpload = min(allClients.length, remainingQuota);

      // Split into batches of 50
      for (int i = 0; i < clientsToUpload; i += clientsPerRequest) {
        int end = min(i + clientsPerRequest, clientsToUpload);
        List<Map<String, dynamic>> batch = allClients.sublist(i, end);

        // Convert batch to Map<int, Map>
        Map<int, Map<String, dynamic>> batchMap = {};
        int lastIdInBatch = 0;

        for (var client in batch) {
          int clientId = client['id'] as int;
          batchMap[clientId] = client;
          lastIdInBatch = clientId;
        }

        try {
          // Send batch to server
          final response = await backendService.post(
            '/api/clients/batch-upload',
            body: {
              'clients': batchMap,
            },
          );

          if (response['success'] == true) {
            // Update last uploaded client ID
            await setLastUploadedClientId(lastIdInBatch);

            // Increment upload count
            int newCount = await getClientBatchUploadCount();
            await setClientBatchUploadCount(newCount + batch.length);

            debugPrint(
                'Client batch upload: Uploaded ${batch.length} clients (total: ${newCount + batch.length}/$maxClientsPerDay)');
          } else {
            debugPrint(
                'Client batch upload failed: ${response['message'] ?? 'Unknown error'}');
            // Don't break, try next batch
          }
        } catch (e) {
          debugPrint('Client batch upload request error: $e');
          // Don't break, try next batch
        }

        // Check if we've reached daily limit
        int totalUploaded = await getClientBatchUploadCount();
        if (totalUploaded >= maxClientsPerDay) {
          debugPrint(
              'Client batch upload: Reached daily limit ($maxClientsPerDay)');
          break;
        }
      }
    } catch (e) {
      debugPrint('Client batch upload error: $e');
    }
  }

  Future<void> purgeAndMerge(int toPurgeId, int toMergeId) async {
    print("PUEREGGEGEGEG");

    // Read the original transaction before deleting it.
    final originalTransaction =
        await _sqliteService.queryOne('transactions', toMergeId);

    // Read the newly created transaction.
    final purgeTransaction = MyTransaction.fromMap(
      await _sqliteService.queryOne('transactions', toPurgeId),
    );

    // The original transaction may contain the forwardingJobId.
    // Preserve it when replacing the original transaction with
    // the newly processed transaction.
    // The original transaction may contain forwarding context.
// Preserve it when replacing the original transaction with
// the newly processed transaction.
    final originalForwardingJobId =
        originalTransaction['forwardingJobId']?.toString();

    final originalForwardingSenderDeviceName =
        originalTransaction['forwardingSenderDeviceName']?.toString();

    if (originalForwardingJobId != null && originalForwardingJobId.isNotEmpty) {
      purgeTransaction.forwardingJobId = originalForwardingJobId;

      debugPrint(
        'PURGE/MERGE: Preserved forwardingJobId=$originalForwardingJobId',
      );
    }

    if (originalForwardingSenderDeviceName != null &&
        originalForwardingSenderDeviceName.isNotEmpty) {
      purgeTransaction.forwardingSenderDeviceName =
          originalForwardingSenderDeviceName;

      debugPrint(
        'PURGE/MERGE: Preserved '
        'forwardingSenderDeviceName=$originalForwardingSenderDeviceName',
      );
    }

    final mergedTransaction = purgeTransaction.toMap();
    for (final field in const [
      'parentTransactionId',
      'awaitingTopUp',
      'requiredTopUp',
      'targetAmount',
      'targetOfferId',
      'topUpTransactionId',
    ]) {
      if (originalTransaction.containsKey(field)) {
        mergedTransaction[field] = originalTransaction[field];
      }
    }

    await _sqliteService.deleteStuff(toMergeId, 'transactions');
    await _sqliteService.deleteStuff(toPurgeId, 'transactions');

    purgeTransaction.id = toMergeId;
    mergedTransaction['id'] = toMergeId;

    await _sqliteService.insertStuff(
      mergedTransaction,
      'transactions',
    );
  }
}
