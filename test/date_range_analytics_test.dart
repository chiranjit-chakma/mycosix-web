import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/analytics/date_range.dart';

void main() {
  // A fixed local reference moment: 6 Sep 2026 14:30.
  final now = DateTime(2026, 9, 6, 14, 30);
  DateTime midnight(DateTime t) => DateTime(t.year, t.month, t.day);

  group('dateRangeFor', () {
    test('Today is this local day only', () {
      final r = dateRangeFor(DateRangeKey.today, nowLocal: now);
      expect(r.startLocal, DateTime(2026, 9, 6));
      expect(r.endLocal, DateTime(2026, 9, 7));
    });

    test('Last 7 days ends today and covers seven calendar days', () {
      final r = dateRangeFor(DateRangeKey.last7Days, nowLocal: now);
      // 31 Aug .. 6 Sep inclusive == 7 days; end exclusive = 7 Sep.
      expect(r.startLocal, DateTime(2026, 8, 31));
      expect(r.endLocal, DateTime(2026, 9, 7));
      expect(r.endLocal.difference(r.startLocal).inDays, 7);
    });

    test('This month spans the calendar month', () {
      final r = dateRangeFor(DateRangeKey.thisMonth, nowLocal: now);
      expect(r.startLocal, DateTime(2026, 9, 1));
      expect(r.endLocal, DateTime(2026, 10, 1));
    });

    test('Last month spans the previous calendar month', () {
      final r = dateRangeFor(DateRangeKey.lastMonth, nowLocal: now);
      expect(r.startLocal, DateTime(2026, 8, 1));
      expect(r.endLocal, DateTime(2026, 9, 1));
    });

    test('Last month works across a year boundary', () {
      final jan = DateTime(2026, 1, 6, 10);
      final r = dateRangeFor(DateRangeKey.lastMonth, nowLocal: jan);
      expect(r.startLocal, DateTime(2025, 12, 1));
      expect(r.endLocal, DateTime(2026, 1, 1));
    });

    test('Custom honours the picked dates (date-only, midnight local)', () {
      final r = dateRangeFor(
        DateRangeKey.custom,
        nowLocal: now,
        customFrom: DateTime(2026, 9, 3, 9),
        customTo: DateTime(2026, 9, 5, 21),
      );
      expect(r.startLocal, DateTime(2026, 9, 3));
      expect(r.endLocal, DateTime(2026, 9, 6)); // to-day + 1
    });

    test('Swapped custom dates are normalised to the earlier span', () {
      final r = dateRangeFor(
        DateRangeKey.custom,
        nowLocal: now,
        customFrom: DateTime(2026, 9, 10),
        customTo: DateTime(2026, 9, 2),
      );
      expect(r.startLocal, DateTime(2026, 9, 2));
      expect(r.endLocal, DateTime(2026, 9, 11));
    });
  });

  group('boundary semantics', () {
    test('includesLocal is start-inclusive, end-exclusive', () {
      final today = dateRangeFor(DateRangeKey.today, nowLocal: now);
      expect(today.includesLocal(DateTime(2026, 9, 6, 0, 0, 0, 0)), isTrue);
      expect(today.includesLocal(DateTime(2026, 9, 6, 23, 59, 59)), isTrue);
      expect(today.includesLocal(DateTime(2026, 9, 5, 23, 59, 59)), isFalse);
      expect(today.includesLocal(DateTime(2026, 9, 7, 0, 0, 0, 0)), isFalse);
    });

    test('UTC boundaries match the local instants for Firestore', () {
      final today = dateRangeFor(DateRangeKey.today, nowLocal: now);
      expect(today.startUtc, midnight(today.startLocal).toUtc());
      expect(today.endUtc, midnight(today.endLocal).toUtc());
      expect(today.startUtc.isBefore(today.endUtc), isTrue);
      expect(today.endUtc.difference(today.startUtc).inHours, 24);
    });
  });

  group('dateRangeHuman', () {
    test('a single day prints just that day', () {
      final today = dateRangeFor(DateRangeKey.today, nowLocal: now);
      expect(dateRangeHuman(today), '6 Sep 2026');
    });

    test('a span prints a short range', () {
      final week = dateRangeFor(DateRangeKey.last7Days, nowLocal: now);
      expect(dateRangeHuman(week), '31 Aug-6 Sep 2026');
    });
  });

  test('key labels are the admin-facing names', () {
    expect(DateRangeKey.today.label, 'Today');
    expect(DateRangeKey.last7Days.label, 'Last 7 days');
    expect(DateRangeKey.thisMonth.label, 'This month');
    expect(DateRangeKey.lastMonth.label, 'Last month');
    expect(DateRangeKey.custom.label, 'Custom');
  });
}
