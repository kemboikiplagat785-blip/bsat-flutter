import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

// measurements
const kPagePadding = 20.0;
const kAdDividerHeight = 16.0;
const kInputElementHeight = 48.0;
const kBorderRadius = 16.0;

const kPagePaddingInsets = EdgeInsets.all(kPagePadding);

// colors
// const kPrimaryColor = Color.fromARGB(255, 83, 235, 113);

const kDarkerGreen = Color.fromARGB(255, 0, 137, 0);
const kPrimaryColor = kDarkerGreen;

const kBgColor = Color(0xFFF3F3F3);
const kGrayColor = Color.fromARGB(55, 141, 146, 154);
const kGrayColorLight = Color.fromARGB(255, 242, 244, 245);
const kPurpleGrayColor = Color.fromARGB(255, 231, 234, 244);
const kIndigoColor = Color.fromARGB(255, 73, 89, 172);
const kLightBlueColor = Color.fromARGB(255, 89, 180, 254);
const kAquaColor = Color.fromARGB(255, 146, 250, 245);

const kPrimaryColorLight = Color.fromARGB(41, 117, 239, 131);
const kSecondaryColor = Color.fromARGB(255, 29, 29, 29);
const kLightColor = Color.fromARGB(255, 255, 255, 255);
const kWarningColor = Color.fromARGB(255, 228, 190, 2);
const kWarningColorLight = Color.fromARGB(128, 255, 216, 19);
const kErrorColor = Color.fromARGB(255, 202, 47, 47);
const kErrorColorLight = Color.fromARGB(72, 202, 47, 47);
const kDullColor = Color.fromARGB(116, 0, 0, 0);
const kDullColorLight = Color.fromARGB(68, 0, 0, 0);
// const kLightBlueColor = Color.fromARGB(255, 0, 187, 255);

const kBrownBackground = Color(0xFF3D1C0B);

// string constants
const interpunct = '·';
const sampleText =
    "SD456NE9M1 confirmed. Ksh50.00 sent to AIRTEL MONEY for account +254738804508 on 4/4/24 at 10:19 PM New M-PESA balance is Ksh125.87. Transaction cost, Ksh0.00.";
const String kSPCostAware = "cost-aware";

// Misc

TextStyle kTitleText = TextStyle(
  // color: Colors.black.withOpacity(0.8),
  fontWeight: FontWeight.bold,
  // fontSize: 22,
);

class TransactionStatuses {
  static const done = "transaction-done";
  static const error = "transaction-error";
  static const secondAttempt = "transaction-duplicate";
  static const unavailableOffer = "unavailable-offer";
  static const timedOut = "transaction-timed-out";
  static const blacklisted = "transaction-blacklisted";
  static const paused = "transaction-paused";
  static const advancedUssd = "transaction-advanced-ussd";
  static const hasOkoa = "transaction-has-okoa";
  static const advancedQueue = "transaction-advanced-queue";
  static const doneConfirmed = "transaction-confirmed";
  static const forwarded = "transaction-forwarded";
  static const forwardedPending = "transaction-forwarded-pending";
  static const forwardedConfirmed = "transaction-forwarded-confirmed";
  static const masked = "transaction-masked";
  static const forwardedOnline = "transaction-forwarded-online";
  static const alternativeExecuting = "transaction-alternative-executing";
  static const alternativeFailed = "transaction-alternative-failed";
  static const alternativeAmbiguous = "transaction-alternative-ambiguous";
  static const alternativeDeliveryPending =
      "transaction-alternative-delivery-pending";
  static const successfulPending = 'successful-pending';

  static const doneMap = {0: done};
  static const errorMap = {1: error};
  static const secondAttemptMap = {2: secondAttempt};
  static const unavailableOfferMap = {3: unavailableOffer};
  static const timedOutMap = {4: timedOut};
  static const blacklistedMap = {5: blacklisted};
  static const pausedMap = {6: paused};
  static const advancedUssdMap = {7: advancedUssd};
  static const hasOkoaMap = {8: hasOkoa};
  static const advancedQueueMap = {9: advancedQueue};
  static const doneConfirmedMap = {10: doneConfirmed};
  static const forwardedMap = {11: forwarded};
  static const forwardedPendingMap = {12: forwardedPending};
  static const forwardedConfirmedMap = {13: forwardedConfirmed};
  static const maskedMap = {14: masked};
  static const forwardedOnlineMap = {15: forwardedOnline};
  static const alternativeExecutingMap = {16: alternativeExecuting};
  static const alternativeFailedMap = {17: alternativeFailed};
  static const successfulPendingMap = {18: successfulPending};
  static const statuses = {
    0: done,
    1: error,
    2: secondAttempt,
    3: unavailableOffer,
    4: timedOut,
    5: blacklisted,
    6: paused,
    7: advancedUssd,
    8: hasOkoa,
    9: advancedQueue,
    10: doneConfirmed,
    11: forwarded,
    12: forwardedPending,
    13: forwardedConfirmed,
    14: masked,
    15: forwardedOnline,
    16: alternativeExecuting,
    17: alternativeFailed,
    18: successfulPending,
  };
}

class ForwardingJobStatuses {
  static const pending = 'forwarding-pending';
  static const delivered = 'forwarding-delivered';
  static const processing = 'forwarding-processing';
  static const confirmed = 'forwarding-confirmed';
  static const failed = 'forwarding-failed';
  static const timedOut = 'forwarding-timed-out';
}

List<Map<String, dynamic>> kSubscriptionTiers = [
  {
    "id": 0,
    "tier": "Free",
    "features": [
      "Forwarding MPesa texts (online and offline)",
      "Calculator (add up unprocessed amounts from a single client)",
    ],
    "plans": [
      {
        "plan_id": -1,
        "durationString": "Free Forever",
        "durationDays": 36500,
        "amount": 0
      },
    ],
    "color": kGrayColor,
  },
  {
    "id": 1,
    "tier": "Offline",
    "features": [
      "Everything in Free",
      "Process offline transactions",
      "Reply to customers",
      "Statistics dashboard",
      "Schedule tasks",
    ],
    "plans": [
      {"plan_id": 0, "durationString": "Day", "durationDays": 1, "amount": 10},
      {
        "plan_id": 1,
        "durationString": "5 Days",
        "durationDays": 5,
        "amount": 50
      },
      {
        "plan_id": 2,
        "durationString": "Month",
        "durationDays": 30,
        "amount": 300
      },
    ],
    "tokens": [
      {"token_id": 0, "amount": 100, "value": 15, "details": "10 tokens"},
      {"token_id": 1, "amount": 250, "value": 30, "details": "20 tokens"},
      {"token_id": 2, "amount": 800, "value": 90, "details": "50 tokens"}
    ],
    "color": kWarningColor,
  },
  {
    "id": 2,
    "tier": "Online",
    "features": [
      "Everything in Offline",
      "Process requests from online",
      "Link devices",
      "Online link to sell data",
    ],
    "plans": [
      {"plan_id": 3, "durationString": "Day", "durationDays": 1, "amount": 20},
      {
        "plan_id": 4,
        "durationString": "5 Days",
        "durationDays": 5,
        "amount": 100
      },
      {
        "plan_id": 5,
        "durationString": "Month",
        "durationDays": 30,
        "amount": 600
      },
    ],
    "tokens": [
      {"token_id": 3, "amount": 150, "value": 20, "details": "20 tokens"},
      {"token_id": 4, "amount": 500, "value": 75, "details": "50 tokens"},
      {"token_id": 5, "amount": 900, "value": 120, "details": "100 tokens"}
    ],
    "color": kIndigoColor,
  },
  {
    "id": 3,
    "tier": "Online +",
    "features": [
      "Everything in Online",
      "Control portal",
      "AI chat",
      "Whatsapp bot",
    ],
    "plans": [
      {"plan_id": 6, "durationString": "Day", "durationDays": 1, "amount": 25},
      {
        "plan_id": 7,
        "durationString": "5 Days",
        "durationDays": 5,
        "amount": 120
      },
      {
        "plan_id": 8,
        "durationString": "Month",
        "durationDays": 30,
        "amount": 700
      },
    ],
    "color": kPrimaryColor,
  },
];

List<Map<String, dynamic>> kTokens = [
  {
    "id": 0,
    "amount": 100,
    "value": 15,
    "details": "10 tokens",
  },
  {
    "id": 1,
    "amount": 250,
    "value": 30,
    "details": "20 tokens",
  },
  {
    "id": 2,
    "amount": 800,
    "value": 90,
    "details": "50 tokens",
  }
];

List<Map<String, dynamic>> kInitialCodes = [
  {'code': '*180*5*2*n*6*1#', 'amount': 55},
  {'code': '*180*5*2*n*6*1#', 'amount': 58},
  {'code': '*180*5*2*n*6*1#', 'amount': 60},
  {'code': '*180*5*2*n*5*1#', 'amount': 99},
  {'code': '*180*5*2*n*5*1#', 'amount': 100},
  {'code': '*180*5*2*n*2*1#', 'amount': 20},
  {'code': '*180*5*2*n*2*1#', 'amount': 25},
  {'code': '*180*5*2*n*1*1#', 'amount': 19},
  {'code': '*180*5*2*n*4*1#', 'amount': 49},
];

List<Map<String, dynamic>> kNoAutoretryCodes = [
  {'code': '*544*13*1*n*1*1#', 'amount': 130},
  {'code': '*544*13*1*n*1*1#', 'amount': 120},
  {'code': '*544*5*8*n*00*1*0*1*1#', 'amount': 23},
  {'code': '*544*5*8*n*00*1*0*1*1#', 'amount': 21},
  {'code': '*544*5*8*n*00*1*0*4*1#', 'amount': 53},
  {'code': '*544*5*8*n*00*14*8*2*1#', 'amount': 50},
  {'code': '*544*6*8*n*00*14*8*2*1#', 'amount': 51},
  {'code': '*544*6*8*n*00*14*8*2*1#', 'amount': 52},
  {'code': '*188*8*2*2*n*1*2#', 'amount': 30},
  {'code': '*188*8*1*2*n*1*2#', 'amount': 10},
  {'code': '*188*8*1*1*n*1*2#', 'amount': 5},
  {'code': '*544*6*8*n*00*14*8*1*1#', 'amount': 22},
  {'code': '*544*1*1*6*n*2*1#', 'amount': 54},
];

List<Color> colors = [
  kPrimaryColor,
  kIndigoColor,
  kWarningColor,
  kErrorColor,
  kDullColor,
  kPrimaryColor,
  kErrorColor,
];

List<Color> kSectionColors = [
  kPrimaryColor,
  kIndigoColor,
  kWarningColor,
  kErrorColor,
  kDullColor,
  kPrimaryColor.withValues(alpha: 0.7),
  kIndigoColor.withValues(alpha: 0.7),
  kWarningColor.withValues(alpha: 0.7),
  kErrorColor.withValues(alpha: 0.7),
  kDullColor.withValues(alpha: 0.7),
];

Future<String> getAppVersion() async {
  PackageInfo packageInfo = await PackageInfo.fromPlatform();
  // //print(packageInfo.version);
  return packageInfo.version;
}
