import 'constants.dart';
import 'package:intl/intl.dart';

String getNormalDate(DateTime dateTime) {
  String day = dateTime.day.toString().padLeft(2, '0');
  String month = dateTime.month.toString().padLeft(2, '0');
  String year = dateTime.year.toString().padLeft(2, '0');
  return "$day/$month/$year";
}

String getNormalTime(DateTime dateTime) {
  String hour = dateTime.hour.toString().padLeft(2, '0');
  String minute = dateTime.minute.toString().padLeft(2, '0');
  String second = dateTime.second.toString().padLeft(2, '0');
  return "$hour:$minute:$second";
}

String getRoughTime(DateTime dateTime) {
  String hour = dateTime.hour.toString().padLeft(2, '0');
  String minute = dateTime.minute.toString().padLeft(2, '0');
  String second = dateTime.second.toString().padLeft(2, '0');
  return "$hour:$minute:$second";
}

DateTime toDateTime(String date, String time, {String? delim}) {
  String seperator = delim ?? interpunct;
  String dateFormat = 'dd${seperator}MM${seperator}yyyy';
  String timeFormat = 'HH:mm:ss';
  String formattedDateTimeString = '$date $time';
  // DateTime dateTime = DateTime(2020);
  return DateFormat('$dateFormat $timeFormat').parse(formattedDateTimeString);
  // return dateTime;
}

String getDateString(String dateTime) {
  return dateTime;
}

String getTimeString(String dateTime) {
  return dateTime;
}

int getLastSundayMidnightMillis() {
  DateTime now = DateTime.now();
  int weekday = now.weekday;

  if (weekday == 7) {
    weekday = 0;
  }

  // print("WeeekDay: $weekday");
  DateTime lastSunday = now.subtract(Duration(days: weekday));
  DateTime lastSundayMidnight =
      DateTime(lastSunday.year, lastSunday.month, lastSunday.day);
  // lastSundayMidnight = lastSundayMidnight.subtract(Duration(hours: 3));
  return lastSundayMidnight.millisecondsSinceEpoch;
}

int getTodayMidnightMillis() {
  DateTime now = DateTime.now();
  DateTime todayMidnight = DateTime(now.year, now.month, now.day);
  return todayMidnight.millisecondsSinceEpoch;
}

String getGreeting({bool withEmoji = false}) {
  final hour = DateTime.now().hour;

  if (hour >= 5 && hour < 12) {
    return 'Good morning ${withEmoji ? '🌅' : ''}';
  } else if (hour >= 12 && hour < 17) {
    return 'Good afternoon ${withEmoji ? '🌞' : ''}';
  } else {
    return 'Good evening ${withEmoji ? '🌙' : ''}';
  }
}

String getDayOfWeek(DateTime dateTime) {
  switch (dateTime.weekday) {
    case DateTime.monday:
      return 'Monday';
    case DateTime.tuesday:
      return 'Tuesday';
    case DateTime.wednesday:
      return 'Wednesday';
    case DateTime.thursday:
      return 'Thursday';
    case DateTime.friday:
      return 'Friday';
    case DateTime.saturday:
      return 'Saturday';
    case DateTime.sunday:
      return 'Sunday';
    default:
      return '';
  }
}
