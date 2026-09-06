import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../firebase/fb.dart';
import '../../models/order_status.dart';
import '../../models/order_status_update.dart';
import '../../models/store_order.dart';
import '../../services/url_launcher.dart';
import '../../utils/money.dart';
import 'admin_widgets.dart';

/// Opens the full order sheet: customer, exact address, line items, totals and
/// the trusted status control. Status writes go straight to Firestore and are
/// authorised by security rules (admin only) - never through a client flag.
Future<void> showOrderDetail(BuildContext context, StoreOrder order) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OrderSheet(order: order),
  );
}

class _OrderSheet extends StatefulWidget {
  const _OrderSheet({required this.order});

  final StoreOrder order;

  @override
  State<_OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<_OrderSheet> {
  late OrderStatus _status = widget.order.status;
  bool _saving = false;
  String? _saveError;

  Future<void> _updateStatus(OrderStatus next) async {
    if (next == _status || widget.order.id == null) return;
    setState(() {
      _saving = true;
      _saveError = null;
      _status = next;
    });
    try {
      // status is stored as the canonical label (never the Dart enum name) and
      // Delivered additionally stamps a trusted deliveredAt. The write is
      // authorised by security rules and restricted to those fields.
      final patch = orderStatusUpdateFields(
        next,
        FieldValue.serverTimestamp(),
      );
      await Fb.orders.doc(widget.order.id).update(patch);
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${widget.order.orderId} marked ${next.label}.'),
          ),
        );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = Fb.friendlyMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return FractionallySizedBox(
      heightFactor: 0.92,
      child: Container(
        decoration: const BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: MxColors.line,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Order ${o.orderId}',
                          style: MxType.h3(color: MxColors.forest),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${o.customerName} | ${o.phone}'
                          '${o.email == null ? '' : '  |  ${o.email}'}',
                          style: MxType.bodySm(color: MxColors.stone),
                        ),
                      ],
                    ),
                  ),
                  StatusPill(status: _status),
                ],
              ),
              const SizedBox(height: 16),
              _Block(
                title: 'Address',
                rows: [
                  _row(
                    'Co-ordinates',
                    '${o.latitude.toStringAsFixed(5)}, ${o.longitude.toStringAsFixed(5)}',
                  ),
                  if (o.building != null) _row('Building / area', o.building!),
                  if (o.apartment != null)
                    _row('Flat / apartment', o.apartment!),
                  if (o.landmark != null) _row('Landmark', o.landmark!),
                  if (o.instructions != null)
                    _row('Delivery note', o.instructions!),
                ],
                trailing: TextButton.icon(
                  onPressed: () => UrlLauncher.open(o.mapsUrl),
                  icon: const Icon(Icons.map_outlined, size: 17),
                  label: const Text('Open in Maps'),
                ),
              ),
              const SizedBox(height: 12),
              _Block(
                title: 'Items',
                rows: [
                  for (final l in o.items)
                    if (o.verified)
                      _row(
                        '${l.productName}${l.weight == null ? '' : ' (${l.weight})'} × ${l.quantity}',
                        formatRupees(l.lineTotal),
                        secondary: '₹${l.unitPrice.toStringAsFixed(0)} each',
                      )
                    else
                      // Packing view: a captured order has no prices, so show
                      // exactly what needs packing (product x quantity).
                      _row(
                        '${l.productName}${l.weight == null ? '' : ' (${l.weight})'}',
                        '× ${l.quantity}',
                      ),
                ],
              ),
              const SizedBox(height: 12),
              if (o.verified)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MxColors.cream,
                    borderRadius: BorderRadius.circular(MxRadius.md),
                    border: Border.all(color: MxColors.line),
                  ),
                  child: Column(
                    children: [
                      _row('Subtotal', formatRupees(o.subtotal)),
                      _row('Delivery fee', formatRupees(o.deliveryFee)),
                      const Divider(color: MxColors.line, height: 22),
                      _row('Total', formatRupees(o.total), bold: true),
                    ],
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: MxColors.warn.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(MxRadius.md),
                    border: Border.all(
                      color: MxColors.warn.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: MxColors.warn,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Not yet priced - confirm the cash total on the call',
                              style: MxType.bodySm(
                                color: MxColors.charcoal,
                                weight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              'This order was captured money-free while the '
                              'secure order service was unavailable. The cash '
                              'total is agreed with the customer before '
                              'packing; it will not appear in sales analytics '
                              'until the trusted backend records a priced '
                              'total.',
                              style: MxType.bodyXs(
                                color: MxColors.charcoalSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              Text('Status', style: MxType.labelLg(color: MxColors.moss)),
              const SizedBox(height: 8),
              DropdownButtonFormField<OrderStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                items: [
                  for (final s in OrderStatus.values)
                    DropdownMenuItem(value: s, child: Text(s.label)),
                ],
                onChanged: _saving
                    ? null
                    : (s) => s == null ? null : _updateStatus(s),
              ),
              if (_status == OrderStatus.delivered ||
                  _status == OrderStatus.cancelled) ...[
                const SizedBox(height: 8),
                Text(
                  _status == OrderStatus.delivered
                      ? 'Delivered and Cancelled are final — this order cannot be '
                          'moved back to an earlier status.'
                      : 'Cancelled is final — this order cannot be reopened. '
                          'Restock any items manually in Inventory if needed.',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ],
              if (widget.order.deliveredAt != null) ...[
                const SizedBox(height: 8),
                Text(
                  'Delivered at ${_stamp(widget.order.deliveredAt!)}',
                  style: MxType.bodyXs(
                    color: MxColors.ok,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
              if (_saveError != null) ...[
                const SizedBox(height: 8),
                Text(_saveError!, style: MxType.bodyXs(color: MxColors.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Absolute local timestamp, e.g. "5 Sep 2026, 09:14".
String _stamp(DateTime t) {
  const months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  String two(int v) => v.toString().padLeft(2, '0');
  final l = t.toLocal();
  return '${l.day} ${months[l.month - 1]} ${l.year}, ${two(l.hour)}:${two(l.minute)}';
}

Widget _row(
  String label,
  String value, {
  bool bold = false,
  String? secondary,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: MxType.bodySm(
                  color: bold ? MxColors.charcoal : MxColors.charcoalSoft,
                  weight: bold ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
              if (secondary != null)
                Text(
                  secondary,
                  style: MxType.bodyXs(color: MxColors.stoneLight),
                ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: MxType.bodySm(
            color: bold ? MxColors.charcoal : MxColors.charcoal,
            weight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    ),
  );
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.rows, this.trailing});

  final String title;
  final List<Widget> rows;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.cream,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: MxType.labelLg(color: MxColors.moss)),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 8),
          for (final r in rows) r,
        ],
      ),
    );
  }
}
