/// Local-time calendar ranges used to filter admin analytics.
///
/// Admin timestamps are read out of Firestore as LOCAL `DateTime`s
/// ([`fireTs`]/`toLocal()`), so every range below is computed in local time
/// against the midnight boundaries a person means. The same range exposes UTC
/// instants for the Firestore query itself (stored timestamps are instants).
library;

/// Named date ranges offered on the sales overview.
enum DateRangeKey {
  today('Today'),
  last7Days('Last 7 days'),
  thisMonth('This month'),
  lastMonth('Last month'),
  custom('Custom');

  const DateRangeKey(this.label);

  final String label;
}

/// An inclusive-start, exclusive-end range in local time.
class DateRange {
  const DateRange({required this.startLocal, required this.endLocal});

  final DateTime startLocal;
  final DateTime endLocal;

  bool get isNotEmpty => endLocal.isAfter(startLocal);

  bool includesLocal(DateTime local) =>
      !local.isBefore(startLocal) && local.isBefore(endLocal);

  /// Same boundaries as UTC instants, for Firestore `createdAt` queries.
  DateTime get startUtc => startLocal.toUtc();
  DateTime get endUtc => endLocal.toUtc();

  @override
  String toString() =>
      '${_d(startLocal)} -> ${_d(endLocal)} (${endLocal.difference(startLocal).inDays}d)';

  static String _d(DateTime t) =>
      '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
}

DateTime _localMidnight(DateTime t) => DateTime(t.year, t.month, t.day);

/// Builds the [DateRange] a [DateRangeKey] means, relative to [nowLocal].
///
/// All boundaries are local midnights. "Last 7 days" covers the 7 calendar
/// days ending today (today minus 6 through today inclusive). [custom] requires
/// [customFrom] and [customTo] (date-only, midnight normalised inside).
DateRange dateRangeFor(
  DateRangeKey key, {
  required DateTime nowLocal,
  DateTime? customFrom,
  DateTime? customTo,
}) {
  final today = _localMidnight(nowLocal);
  switch (key) {
    case DateRangeKey.today:
      return DateRange(startLocal: today, endLocal: today.add(const Duration(days: 1)));
    case DateRangeKey.last7Days:
      final start = today.subtract(const Duration(days: 6));
      return DateRange(startLocal: start, endLocal: today.add(const Duration(days: 1)));
    case DateRangeKey.thisMonth:
      final start = DateTime(nowLocal.year, nowLocal.month, 1);
      return DateRange(
        startLocal: start,
        endLocal: DateTime(nowLocal.year, nowLocal.month + 1, 1),
      );
    case DateRangeKey.lastMonth:
      final start = DateTime(nowLocal.year, nowLocal.month - 1, 1);
      return DateRange(
        startLocal: start,
        endLocal: DateTime(nowLocal.year, nowLocal.month, 1),
      );
    case DateRangeKey.custom:
      final from = customFrom == null ? today : _localMidnight(customFrom);
      final to = customTo == null ? today : _localMidnight(customTo);
      var start = from;
      var end = to.add(const Duration(days: 1));
      if (end.isBefore(start)) {
        // Swapped picks: honour the earlier pick as the start.
        start = to;
        end = from.add(const Duration(days: 1));
      }
      return DateRange(startLocal: start, endLocal: end);
  }
}

/// Short ASCII label for a range's human display, e.g. `6 Sep 2026` for Today,
/// `1-6 Sep 2026` for a same-month span or `31 Aug-6 Sep 2026` for a
/// cross-month span.
String dateRangeHuman(DateRange range) {
  String d(DateTime t) => '${t.day} ${_monthShort(t.month)} ${t.year}';
  final start = range.startLocal;
  final end = range.endLocal.subtract(const Duration(days: 1));
  if (start.year == end.year && start.month == end.month && start.day == end.day) {
    return d(start);
  }
  if (start.year == end.year && start.month == end.month) {
    return '${start.day}-${end.day} ${_monthShort(start.month)} ${start.year}';
  }
  if (start.year == end.year) {
    return '${start.day} ${_monthShort(start.month)}-${end.day} '
        '${_monthShort(end.month)} ${start.year}';
  }
  return '${d(start)}-${d(end)}';
}

String _monthShort(int m) {
  const names = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[m - 1];
}
