import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../analytics/date_range.dart';
import '../../../analytics/monthly.dart';
import '../../../analytics/order_analytics.dart';
import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/batch.dart';
import '../../../models/order_status.dart';
import '../../../models/store_order.dart';
import '../admin_widgets.dart';

/// Analytics: real sales figures from stored orders over a chosen date range,
/// plus the monthly production-vs-sales picture from grow batches.
///
/// Money rules are enforced here exactly as in the trusted backend: revenue,
/// average order value, units sold and best-sellers count Delivered orders
/// only; Cancelled orders are never revenue. Ranges are local-calendar based.
class AnalyticsSection extends StatefulWidget {
  const AnalyticsSection({super.key});

  @override
  State<AnalyticsSection> createState() => _AnalyticsSectionState();
}

class _AnalyticsSectionState extends State<AnalyticsSection> {
  DateRangeKey _key = DateRangeKey.thisMonth;
  DateTime? _customFrom;
  DateTime? _customTo;

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Sales analytics',
            subtitle:
                'Computed from real stored orders. Revenue counts Delivered '
                'orders only - Cancelled orders are never counted as sales.',
          ),
          const SizedBox(height: 14),
          _rangeBar(),
          const SizedBox(height: 6),
          _salesBlock(),
          const SizedBox(height: 28),
          const _MonthlyBlock(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _rangeBar() {
    Widget chip(DateRangeKey key) {
      final on = _key == key;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(key.label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => setState(() {
            _key = key;
          }),
          labelStyle: MxType.bodyXs(
            color: on ? MxColors.forest : MxColors.charcoalSoft,
            weight: FontWeight.w700,
          ),
          selectedColor: MxColors.mossSoft,
          backgroundColor: MxColors.creamSoft,
          side: BorderSide(color: on ? MxColors.moss : MxColors.line),
        ),
      );
    }

    final now = DateTime.now();
    final range = dateRangeFor(
      _key,
      nowLocal: now,
      customFrom: _customFrom,
      customTo: _customTo,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final key in DateRangeKey.values) chip(key),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_key == DateRangeKey.custom)
          Row(
            children: [
              _dateField('From', _customFrom, (d) => _customFrom = d),
              const SizedBox(width: 10),
              _dateField('To', _customTo, (d) => _customTo = d),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Showing: ${dateRangeHuman(range)}',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ),
            ],
          )
        else
          Text(
            'Showing: ${dateRangeHuman(range)}',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
      ],
    );
  }

  Widget _dateField(String label, DateTime? value, ValueChanged<DateTime> set) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime.now(),
        );
        if (picked != null && context.mounted) {
          setState(() => set(DateTime(picked.year, picked.month, picked.day)));
        }
      },
      borderRadius: BorderRadius.circular(MxRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.sm),
          border: Border.all(color: MxColors.line),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 15, color: MxColors.stone),
            const SizedBox(width: 6),
            Text(
              '$label: ${value == null ? 'pick' : '${value.day}/${value.month}/${value.year}'}',
              style: MxType.bodyXs(
                color: value == null ? MxColors.stone : MxColors.forest,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _salesBlock() {
    final now = DateTime.now();
    final range = dateRangeFor(
      _key,
      nowLocal: now,
      customFrom: _customFrom,
      customTo: _customTo,
    );
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.orders
          .where('createdAt', isGreaterThanOrEqualTo: range.startUtc)
          .where('createdAt', isLessThan: range.endUtc)
          .orderBy('createdAt', descending: true)
          .limit(400)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return StateNote(
            icon: Icons.error_outline_rounded,
            text: 'Orders could not be loaded.',
            detail: Fb.friendlyMessage(snap.error!),
            tone: StateTone.danger,
          );
        }
        if (!snap.hasData) {
          return const LoadingNote(label: 'Loading analytics...');
        }
        final orders = [for (final d in snap.data!.docs) orderFromDoc(d)];
        final metrics = computeSalesMetrics(orders);
        final empty = metrics.ordersCount == 0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _grid([
              _MetricCard(
                label: 'Revenue (Delivered)',
                value: rupees(metrics.revenue),
                icon: Icons.payments_outlined,
                accent: MxColors.ok,
              ),
              _MetricCard(
                label: 'Orders',
                value: '${metrics.ordersCount}',
                icon: Icons.receipt_long_outlined,
              ),
              _MetricCard(
                label: 'Delivered',
                value: '${metrics.deliveredCount}',
                icon: Icons.check_circle_outline,
                accent: MxColors.moss,
              ),
              _MetricCard(
                label: 'Cancelled',
                value: '${metrics.cancelledCount}',
                icon: Icons.cancel_outlined,
                accent: MxColors.danger,
              ),
              _MetricCard(
                label: 'Average order value',
                value: rupees(metrics.averageOrderValue),
                icon: Icons.trending_up_rounded,
                accent: MxColors.earth,
              ),
              _MetricCard(
                label: 'Units sold (Delivered)',
                value: '${metrics.quantitySold}',
                icon: Icons.shopping_bag_outlined,
                accent: MxColors.warn,
              ),
            ]),
            const SizedBox(height: 14),
            _breakdown(metrics),
            const SizedBox(height: 8),
            if (empty)
              const StateNote(
                icon: Icons.inbox_outlined,
                text: 'No orders in this period.',
                detail:
                    'Figures are zero because there are no stored orders in '
                    'this date range - nothing is estimated.',
              )
            else
              _bestSellers(metrics),
          ],
        );
      },
    );
  }

  Widget _breakdown(SalesMetrics metrics) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('By status', style: MxType.bodyXs(
            color: MxColors.stone,
            weight: FontWeight.w700,
          )),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final row in metrics.breakdown)
                _StatusCountPill(status: row.status, count: row.count),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bestSellers(SalesMetrics metrics) {
    if (metrics.bestSellers.isEmpty) {
      return const StateNote(
        icon: Icons.emoji_food_beverage_outlined,
        text: 'No delivered products yet.',
        detail: 'Best sellers appear once an order is delivered.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Best sellers', style: MxType.h3()),
        const SizedBox(height: 10),
        for (var i = 0; i < metrics.bestSellers.length; i++)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: MxColors.creamSoft,
              borderRadius: BorderRadius.circular(MxRadius.md),
              border: Border.all(color: MxColors.line),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: MxColors.forest,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: MxType.bodyXs(
                      color: MxColors.cream,
                      weight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    metrics.bestSellers[i].productName,
                    style: MxType.bodySm(
                      color: MxColors.charcoal,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${metrics.bestSellers[i].quantity} sold',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                const SizedBox(width: 14),
                Text(
                  rupees(metrics.bestSellers[i].revenue),
                  style: MxType.bodySm(
                    color: MxColors.forest,
                    weight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _StatusCountPill extends StatelessWidget {
  const _StatusCountPill({required this.status, required this.count});

  final OrderStatus status;
  final int count;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            '${status.label} · $count',
            style: MxType.bodyXs(color: c, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final c = accent ?? MxColors.moss;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MxRadius.sm),
            ),
            child: Icon(icon, size: 18, color: c),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: MxType.h4(color: MxColors.charcoal)),
                Text(label, style: MxType.bodyXs(color: MxColors.stone)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _grid(List<_MetricCard> cards) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w >= 980 ? 3 : w >= 560 ? 2 : 1;
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += cols) {
        final chunk = cards.sublist(i, (i + cols).clamp(0, cards.length));
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (var j = 0; j < chunk.length; j++) ...[
                  Expanded(child: chunk[j]),
                  if (j != chunk.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        );
      }
      return Column(children: rows);
    },
  );
}

/// Monthly production vs. delivered-sales table from grow batches and stored
/// orders. Reads are bounded: batches (small) plus delivered orders of the
/// last 24 months, so no full-database scan happens on this screen.
class _MonthlyBlock extends StatelessWidget {
  const _MonthlyBlock();

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final cutoff = DateTime(now.year - 2, now.month, 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionHeader(
          title: 'Production vs sales by month',
          subtitle:
              'Produced/waste/sold quantities are the farm records from the '
              'Batches section; shop sales are orders actually delivered. '
              'Delivered revenue is shown for each month.',
        ),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: Fb.orders
              .where('deliveredAt', isGreaterThanOrEqualTo: cutoff.toUtc())
              .orderBy('deliveredAt', descending: true)
              .limit(400)
              .snapshots(),
          builder: (context, snap) {
            if (snap.hasError) {
              return StateNote(
                icon: Icons.error_outline_rounded,
                text: 'Delivered orders could not be loaded.',
                detail: Fb.friendlyMessage(snap.error!),
                tone: StateTone.danger,
              );
            }
            if (!snap.hasData) {
              return const LoadingNote(label: 'Loading deliveries...');
            }
            final delivered = <StoreOrder>[
              for (final d in snap.data!.docs)
                if (orderFromDoc(d).status == OrderStatus.delivered)
                  orderFromDoc(d),
            ];
            return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              future: Fb.batches.get(),
              builder: (context, batchSnap) {
                if (batchSnap.hasError) {
                  return StateNote(
                    icon: Icons.error_outline_rounded,
                    text: 'Batches could not be loaded.',
                    detail: Fb.friendlyMessage(batchSnap.error!),
                    tone: StateTone.danger,
                  );
                }
                if (!batchSnap.hasData) {
                  return const LoadingNote(label: 'Loading batches...');
                }
                final batches = <Batch>[];
                for (final d in batchSnap.data!.docs) {
                  final m = d.data();
                  batches.add(
                    Batch.fromMap(
                      m,
                      id: d.id,
                      createdAt: fireTs(m['createdAt']),
                      updatedAt: fireTs(m['updatedAt']),
                    ),
                  );
                }
                final rows = buildMonthlyRows(
                  batches: batches,
                  deliveredOrders: delivered,
                );
                if (rows.isEmpty) {
                  return const StateNote(
                    icon: Icons.calendar_month_outlined,
                    text: 'Nothing to chart yet.',
                    detail:
                        'Record grow batches in the Batches section; delivered '
                        'shop orders appear here automatically.',
                  );
                }
                return _MonthlyTable(rows: rows.reversed.toList());
              },
            );
          },
        ),
      ],
    );
  }
}

class _MonthlyTable extends StatelessWidget {
  const _MonthlyTable({required this.rows});

  /// Newest month first.
  final List<MonthlyRow> rows;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(MxColors.forestRaised),
          dataRowMinHeight: 40,
          dataRowMaxHeight: 52,
          columns: const [
            DataColumn(label: _Head('Month')),
            DataColumn(label: _Head('Produced')),
            DataColumn(label: _Head('Sold (farm)')),
            DataColumn(label: _Head('Waste')),
            DataColumn(label: _Head('Delivered orders')),
            DataColumn(label: _Head('Delivered value')),
            DataColumn(label: _Head('Units sold')),
          ],
          rows: [
            for (final r in rows)
              DataRow(
                cells: [
                  DataCell(
                    Text(
                      r.monthLabel,
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DataCell(_cell('${r.producedQty}')),
                  DataCell(_cell('${r.batchSoldQty}')),
                  DataCell(_cell('${r.wasteQty}')),
                  DataCell(_cell('${r.deliveredOrderCount}')),
                  DataCell(
                    Text(
                      rupees(r.revenue),
                      style: MxType.bodySm(
                        color: MxColors.forest,
                        weight: FontWeight.w800,
                      ),
                    ),
                  ),
                  DataCell(_cell('${r.unitsSold}')),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _cell(String v) => Text(
        v,
        style: MxType.bodySm(color: MxColors.charcoalSoft),
      );
}

class _Head extends StatelessWidget {
  const _Head(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: MxType.bodyXs(color: MxColors.cream, weight: FontWeight.w700),
    );
  }
}
