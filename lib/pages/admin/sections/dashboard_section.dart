import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/order_status.dart';
import '../../../utils/money.dart';
import '../admin_widgets.dart';
import '../order_detail.dart';

/// Overview: real counts and recent records, read live from Firestore.
class DashboardSection extends StatelessWidget {
  const DashboardSection({super.key});

  @override
  Widget build(BuildContext context) {
    return _Area(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Overview',
            subtitle: 'Live from Firestore - the real records, nothing mocked.',
          ),
          const SizedBox(height: 18),
          const _OrderStats(),
          const SizedBox(height: 14),
          const _ProductStats(),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Recent orders'),
          const SizedBox(height: 10),
          const _RecentOrders(),
          const SizedBox(height: 26),
          const SectionHeader(title: 'Low stock'),
          const SizedBox(height: 10),
          const _LowStock(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _Area extends StatelessWidget {
  const _Area({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: child,
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MxRadius.sm),
            ),
            child: Icon(icon, size: 19, color: c),
          ),
          const SizedBox(width: 12),
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

class _OrderStats extends StatelessWidget {
  const _OrderStats();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.orders
          .orderBy('createdAt', descending: true)
          .limit(300)
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
        if (!snap.hasData) return const LoadingNote(label: 'Loading orders...');
        final orders = [for (final d in snap.data!.docs) orderFromDoc(d)];
        final open = orders.where(orderOpen).length;
        final attention = orders.where(orderNeedsAttention).length;
        final delivered = orders.where(
          (o) => o.status == OrderStatus.delivered,
        );
        final revenue = delivered.fold<double>(0, (acc, o) => acc + o.total);
        return _grid([
          _StatCard(
            label: 'Open orders',
            value: '$open',
            icon: Icons.inbox_outlined,
            accent: MxColors.earth,
          ),
          _StatCard(
            label: 'Need attention',
            value: '$attention',
            icon: Icons.notifications_active_outlined,
            accent: MxColors.warn,
          ),
          _StatCard(
            label: 'Delivered (recent 300)',
            value: '${delivered.length}',
            icon: Icons.check_circle_outline,
            accent: MxColors.ok,
          ),
          _StatCard(
            label: 'Delivered value',
            value: formatRupees(revenue),
            icon: Icons.payments_outlined,
            accent: MxColors.moss,
          ),
        ]);
      },
    );
  }
}

class _ProductStats extends StatelessWidget {
  const _ProductStats();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.products.orderBy('sortKey').snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return StateNote(
            icon: Icons.error_outline_rounded,
            text: 'Products could not be loaded.',
            detail: Fb.friendlyMessage(snap.error!),
            tone: StateTone.danger,
          );
        }
        if (!snap.hasData) {
          return const LoadingNote(label: 'Loading products...');
        }
        final products = [for (final d in snap.data!.docs) productFromDoc(d)];
        final unavailable = products.where((p) => !p.available).length;
        final lowStock = products
            .where((p) => p.available && p.stock <= 3)
            .length;
        return _grid([
          _StatCard(
            label: 'Products in catalogue',
            value: '${products.length}',
            icon: Icons.inventory_2_outlined,
          ),
          _StatCard(
            label: 'Low stock (<= 3)',
            value: '$lowStock',
            icon: Icons.priority_high_rounded,
            accent: MxColors.warn,
          ),
          _StatCard(
            label: 'Unavailable',
            value: '$unavailable',
            icon: Icons.block_outlined,
            accent: MxColors.danger,
          ),
        ]);
      },
    );
  }
}

Widget _grid(List<Widget> cards) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w >= 980
          ? 4
          : w >= 560
          ? 2
          : 1;
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += cols) {
        final chunk = cards.sublist(i, (i + cols).clamp(0, cards.length));
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
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

class _RecentOrders extends StatelessWidget {
  const _RecentOrders();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.orders
          .orderBy('createdAt', descending: true)
          .limit(8)
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const LoadingNote(label: 'Loading orders...');
        final orders = [for (final d in snap.data!.docs) orderFromDoc(d)];
        if (orders.isEmpty) {
          return const StateNote(
            icon: Icons.receipt_long_outlined,
            text: 'No orders yet.',
            detail: 'Orders placed through the site appear here automatically.',
          );
        }
        return Column(
          children: [
            for (final o in orders)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: MxColors.creamSoft,
                  borderRadius: BorderRadius.circular(MxRadius.md),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(MxRadius.md),
                    onTap: () => showOrderDetail(context, o),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(MxRadius.md),
                        border: Border.all(color: MxColors.line),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${o.orderId} - ${o.customerName}',
                                  style: MxType.bodySm(
                                    color: MxColors.charcoal,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  '${o.phone} | ${formatRupees(o.total)} | ${shortWhen(o.createdAt)}',
                                  style: MxType.bodyXs(color: MxColors.stone),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(status: o.status),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _LowStock extends StatelessWidget {
  const _LowStock();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.products.orderBy('sortKey').snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const LoadingNote(label: 'Loading products...');
        }
        final products = [for (final d in snap.data!.docs) productFromDoc(d)];
        final low = products.where((p) => p.available && p.stock <= 3).toList()
          ..sort((a, b) => a.stock.compareTo(b.stock));
        if (low.isEmpty) {
          return const StateNote(
            icon: Icons.check_circle_outline,
            text: 'Nothing is running low.',
            detail: 'Every available product has more than 3 units in stock.',
            tone: StateTone.neutral,
          );
        }
        return Column(
          children: [
            for (final p in low)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: MxColors.warnSoft,
                  borderRadius: BorderRadius.circular(MxRadius.md),
                  border: Border.all(
                    color: MxColors.warn.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.priority_high_rounded,
                      size: 17,
                      color: MxColors.warn,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${p.name}${p.weight.isEmpty ? '' : ' (${p.weight})'}',
                        style: MxType.bodySm(
                          color: MxColors.charcoal,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      '${p.stock} left',
                      style: MxType.bodyXs(
                        color: MxColors.warn,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
