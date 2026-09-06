import '../models/batch.dart';
import '../models/store_order.dart';

/// Month-by-month production vs. shop-sales figures for the admin analytics.
///
/// "Production" comes from grow batches (produced/waste/sold quantities the
/// team recorded, attributed to the calendar month the batch was produced).
/// "Shop sales" come from stored orders the shop actually delivered, attributed
/// to the calendar month of the delivery ([deliveredAt], with [createdAt] as
/// the fallback when a delivery was never stamped). Both sides are real records
/// only  -  a month with no batches and no deliveries simply does not appear.

/// One calendar month of production and delivered-sales totals.
class MonthlyRow {
  const MonthlyRow({
    required this.year,
    required this.month,
    required this.producedQty,
    required this.wasteQty,
    required this.batchSoldQty,
    required this.deliveredOrderCount,
    required this.revenue,
    required this.unitsSold,
  });

  final int year;

  /// 1-12.
  final int month;

  /// Units produced across batches started this month.
  final int producedQty;

  /// Units written off as waste across batches started this month.
  final int wasteQty;

  /// Units the farm team recorded as sold from batches started this month.
  final int batchSoldQty;

  /// Stored orders delivered this calendar month.
  final int deliveredOrderCount;

  /// Delivered-order revenue this calendar month.
  final double revenue;

  /// Line units delivered this calendar month.
  final int unitsSold;

  String get monthLabel => '${_shortMonth(month)} $year';
  String get monthKey =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}';
}

/// Builds the production-vs-sales table for [batches] and [deliveredOrders]
/// (the caller narrows delivered orders to whatever range the admin chose).
/// Months ascend; empty input yields an empty table (never invented rows).
List<MonthlyRow> buildMonthlyRows({
  required List<Batch> batches,
  required List<StoreOrder> deliveredOrders,
}) {
  final acc = <String, _MonthAcc>{};
  DateTime? earliest;
  DateTime? latest;

  void touch(DateTime d) {
    if (earliest == null || d.isBefore(earliest!)) earliest = d;
    if (latest == null || d.isAfter(latest!)) latest = d;
  }

  for (final batch in batches) {
    final produced = parseYmd(batch.productionDate);
    if (produced == null) continue; // unparseable record -> ignored, not guessed
    touch(produced);
    final key = _key(produced);
    final a = acc.putIfAbsent(key, () => _MonthAcc(produced.year, produced.month));
    a.producedQty += batch.producedQty;
    a.wasteQty += batch.wasteQty;
    a.batchSoldQty += batch.soldQty;
  }

  for (final order in deliveredOrders) {
    // Attribute a delivery to the month it was delivered (money-recognition),
    // falling back to creation time only when a delivery was never stamped.
    final at = order.deliveredAt ?? order.createdAt;
    if (at == null) continue; // no timestamp -> cannot be placed
    touch(at);
    final key = _key(at);
    final a = acc.putIfAbsent(key, () => _MonthAcc(at.year, at.month));
    a.deliveredOrderCount += 1;
    a.revenue += order.total;
    a.unitsSold += order.totalQuantity;
  }

  if (earliest == null || latest == null) return const <MonthlyRow>[];

  final rows = <MonthlyRow>[];
  var cursor = DateTime(earliest!.year, earliest!.month, 1);
  final end = DateTime(latest!.year, latest!.month + 1, 1);
  while (cursor.isBefore(end)) {
    final a = acc[_key(cursor)];
    if (a != null) {
      rows.add(
        MonthlyRow(
          year: a.year,
          month: a.month,
          producedQty: a.producedQty,
          wasteQty: a.wasteQty,
          batchSoldQty: a.batchSoldQty,
          deliveredOrderCount: a.deliveredOrderCount,
          revenue: a.revenue,
          unitsSold: a.unitsSold,
        ),
      );
    }
    cursor = DateTime(cursor.year, cursor.month + 1, 1);
  }
  return rows;
}

String _key(DateTime local) =>
    '${local.year.toString().padLeft(4, '0')}-${local.month.toString().padLeft(2, '0')}';

String _shortMonth(int m) {
  const names = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return names[m - 1];
}

class _MonthAcc {
  _MonthAcc(this.year, this.month);

  final int year;
  final int month;
  int producedQty = 0;
  int wasteQty = 0;
  int batchSoldQty = 0;
  int deliveredOrderCount = 0;
  double revenue = 0;
  int unitsSold = 0;
}
