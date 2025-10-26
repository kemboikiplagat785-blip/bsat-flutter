// import 'package:flutter/services.dart';

// class UssdService {
//   static const platform = MethodChannel('com.bsat.app');
//   static bool isRunning = false;

//   static Future<String?> sendUssdSequence(String fullCode, int subscriptionId) async {
//     isRunning = true;
//     //print("UssdSession(fl): sendUssdSequence: $fullCode, $subscriptionId");
//     try {
//       final result = await platform.invokeMethod(
//         'runUssdSequence',
//         {"sequence": fullCode, "subscriptionId": subscriptionId},
//       );
//       //print("UssdSession(fl): Result: $result");
//       return result;
//     } finally {
//       isRunning = false;
//     }
//   }
// }
