int? _minuteOfDay(Object? raw) {
  final value = raw?.toString().trim() ?? '';
  if (value.isEmpty) return null;
  final match = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(value);
  if (match == null) return -1;
  final hour = int.tryParse(match.group(1)!);
  final minute = int.tryParse(match.group(2)!);
  if (hour == null || minute == null || hour > 23 || minute > 59) return -1;
  return hour * 60 + minute;
}

/// Uses local time and the Offers convention: start inclusive, end exclusive.
/// Empty or invalid windows retain the legacy fallback behavior.
bool isOfferWindowOpen(
  List<Map<String, dynamic>> variants, {
  DateTime? now,
}) {
  if (variants.isEmpty) return true;
  final current = now ?? DateTime.now();
  final currentMinute = current.hour * 60 + current.minute;
  var sawInvalidWindow = false;

  for (final variant in variants) {
    final startRaw = variant['startTime'];
    final endRaw = variant['endTime'];
    final start = _minuteOfDay(startRaw);
    final end = _minuteOfDay(endRaw);
    if ((startRaw == null || startRaw.toString().trim().isEmpty) &&
        (endRaw == null || endRaw.toString().trim().isEmpty)) {
      return true;
    }
    if (start == -1 || end == -1) {
      sawInvalidWindow = true;
      continue;
    }
    if (start == null) {
      if (currentMinute < end!) return true;
      continue;
    }
    if (end == null) {
      if (currentMinute >= start) return true;
      continue;
    }
    if (start <= end) {
      if (currentMinute >= start && currentMinute < end) return true;
    } else if (currentMinute >= start || currentMinute < end) {
      return true;
    }
  }
  return sawInvalidWindow;
}

String formatOfferTimeWindow(Object? startRaw, Object? endRaw) {
  final start = _minuteOfDay(startRaw);
  final end = _minuteOfDay(endRaw);
  if (start == null || end == null || start < 0 || end < 0) return '';
  String format(int minutes) {
    final hour = minutes ~/ 60;
    final hour12 = hour % 12 == 0 ? 12 : hour % 12;
    final period = hour < 12 ? 'AM' : 'PM';
    return '${hour12.toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')} $period';
  }

  return '${format(start)} – ${format(end)}';
}

String formatTaskOfferLabel({
  required Object? amount,
  required Object? code,
  required Object? startTime,
  required Object? endTime,
}) {
  final safeAmount = amount?.toString().trim() ?? '';
  final safeCode = code?.toString().trim() ?? '';
  if (safeAmount.isEmpty || safeCode.isEmpty) return '';
  final window = formatOfferTimeWindow(startTime, endTime);
  return '$safeAmount ($safeCode)${window.isEmpty ? '' : ' $window'}';
}
