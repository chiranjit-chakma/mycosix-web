import '../models/order_status.dart';
import '../models/order_status_update.dart';
import '../models/store_order.dart';

/// Sales analytics computed from stored orders.
///
/// Money rules (mirror the trusted backend): revenue and best-sellers are
/// counted ONLY from orders the shop actually delivered; cancelled orders are
/// never counted as sales and never appear in revenue. Nothing here writes or
/// invents data  -  it only aggregates real order documents that an admin read
/// out of Firestore for the chosen date range.

/// One row of the per-status breakdown.
class StatusCount {
  const StatusCount({required this.status, required this.count});

  final OrderStatus status;
  final int count;
}

/// One best-selling product (by delivered quantity).
class BestSeller {
  const BestSeller({
    required this.productName,
    required this.quantity,
    required this.revenue,
  });

  final String productName;
  final int quantity;
  final double revenue;
}

/// Aggregated sales figures for a date range.
class SalesMetrics {
  const SalesMetrics({
    required this.ordersCount,
    required this.deliveredCount,
    required this.cancelledCount,
    required this.revenue,
    required this.averageOrderValue,
    required this.quantitySold,
    required this.breakdown,
    required this.bestSellers,
  });

  /// All stored orders that fell inside the range (every status).
  final int ordersCount;

  final int deliveredCount;
  final int cancelledCount;

  /// Sum of Delivered order totals only. Cancelled and other statuses are not
  /// revenue.
  final double revenue;

  /// revenue / deliveredCount (0 when nothing delivered yet).
  final double averageOrderValue;

  /// Units sold across Delivered line items.
  final int quantitySold;

  /// Count per status, in canonical status order, including zeros.
  final List<StatusCount> breakdown;

  /// Delivered line items grouped by product name, best first.
  final List<BestSeller> bestSellers;
}

/// Aggregates [orders] (already narrowed to the date range by the caller).
/// Pure: returns real figures and never fabricates rows, so an empty range
/// yields an empty, zeroed [SalesMetrics].
SalesMetrics computeSalesMetrics(List<StoreOrder> orders) {
  final delivered =
      orders.where((o) => o.status == OrderStatus.delivered).toList();
  final cancelled =
      orders.where((o) => o.status == OrderStatus.cancelled).toList();

  var revenue = 0.0;
  var quantitySold = 0;
  final byName = <String, _ProductAcc>{};
  for (final order in delivered) {
    revenue += order.total;
    for (final line in order.items) {
      quantitySold += line.quantity;
      final acc = byName.putIfAbsent(line.productName, _ProductAcc.new);
      acc.quantity += line.quantity;
      acc.revenue += line.lineTotal;
    }
  }

  final best = byName.entries
      .map(
        (e) => BestSeller(
          productName: e.key,
          quantity: e.value.quantity,
          revenue: e.value.revenue,
        ),
      )
      .toList()
    ..sort((a, b) {
      final byQty = b.quantity.compareTo(a.quantity);
      if (byQty != 0) return byQty;
      final byRev = b.revenue.compareTo(a.revenue);
      if (byRev != 0) return byRev;
      return a.productName.compareTo(b.productName);
    });

  // Per-status counts in canonical order, so the admin table never reorders.
  final breakdown = <StatusCount>[];
  for (final label in orderStatusLabels) {
    final s = OrderStatus.fromLabel(label);
    final count = orders.where((o) => o.status == s).length;
    breakdown.add(StatusCount(status: s, count: count));
  }

  final deliveredCount = delivered.length;
  return SalesMetrics(
    ordersCount: orders.length,
    deliveredCount: deliveredCount,
    cancelledCount: cancelled.length,
    revenue: revenue,
    averageOrderValue:
        deliveredCount == 0 ? 0 : revenue / deliveredCount,
    quantitySold: quantitySold,
    breakdown: breakdown,
    bestSellers: best.length > 8 ? best.sublist(0, 8) : best,
  );
}

class _ProductAcc {
  int quantity = 0;
  double revenue = 0;
}
