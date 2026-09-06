import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/order_status.dart';
import '../../../models/store_order.dart';
import '../admin_widgets.dart';
import '../order_detail.dart';

/// Orders management: every order created by customers through the trusted
/// Cloud Function, with full detail and status control (admin-gated writes).
class OrdersSection extends StatefulWidget {
  const OrdersSection({super.key});

  @override
  State<OrdersSection> createState() => _OrdersSectionState();
}

class _OrdersSectionState extends State<OrdersSection> {
  OrderStatus? _filter;

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Orders',
            subtitle:
                'Created by the trusted backend, or captured money-free while '
                'it is unavailable - browser totals can never reach Firestore.',
          ),
          const SizedBox(height: 14),
          _filterBar(),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Fb.orders
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
                return const LoadingNote(label: 'Loading orders...');
              }
              final orders = [for (final d in snap.data!.docs) orderFromDoc(d)];
              final shown = _filter == null
                  ? orders
                  : orders.where((o) => o.status == _filter).toList();
              if (shown.isEmpty) {
                return const StateNote(
                  icon: Icons.receipt_long_outlined,
                  text: 'No orders to show.',
                  detail:
                      'Try a different filter, or check back once customers '
                      'place orders.',
                );
              }
              return Column(
                children: [
                  for (final o in shown)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _OrderRow(order: o),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _filterBar() {
    Widget chip(String label, OrderStatus? value) {
      final on = _filter == value;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => setState(() => _filter = value),
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

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('All', null),
          for (final s in OrderStatus.values) chip(s.label, s),
        ],
      ),
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Material(
      color: MxColors.creamSoft,
      borderRadius: BorderRadius.circular(MxRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(MxRadius.md),
        onTap: () => showOrderDetail(context, o),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                      '${o.orderId}  |  ${o.customerName}',
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${o.phone}  |  ${orderMoneyLabel(o)}  |  ${shortWhen(o.createdAt)}',
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
    );
  }
}
