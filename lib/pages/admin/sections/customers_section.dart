import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/order_status.dart';
import '../../../models/store_order.dart';
import '../admin_widgets.dart';
import '../order_detail.dart';

/// Customer accounts: everyone who created an account on the site.
///
/// Read from the admin-visible `customers` collection (rules grant admins
/// read on every customer document). Order figures are grouped from the same
/// trusted orders collection the Orders section reads — never invented. A
/// customer's own account document is still private to them and their admin:
/// no passwords, no tokens, no one-time codes are ever read or shown here.
///
/// The account status flag is the one thing an admin may change on a customer
/// document (security rules allow exactly `status` + `updatedAt`). Status is a
/// shop-side flag — it does not revoke the customer's sign-in session.
class CustomersSection extends StatefulWidget {
  const CustomersSection({super.key});

  @override
  State<CustomersSection> createState() => _CustomersSectionState();
}

class _CustomersSectionState extends State<CustomersSection> {
  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Customers',
            subtitle:
                'Accounts created on the site, with their orders. The status '
                'flag is a shop-side record you control — it does not revoke '
                'a customer’s sign-in session.',
          ),
          const SizedBox(height: 14),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Fb.customers.snapshots(),
            builder: (context, custSnap) {
              if (custSnap.hasError) {
                return StateNote(
                  icon: Icons.error_outline_rounded,
                  text: 'Customers could not be loaded.',
                  detail: Fb.friendlyMessage(custSnap.error!),
                  tone: StateTone.danger,
                );
              }
              if (!custSnap.hasData) {
                return const LoadingNote(label: 'Loading customers...');
              }
              return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: Fb.orders
                    .orderBy('createdAt', descending: true)
                    .limit(400)
                    .snapshots(),
                builder: (context, ordSnap) {
                  if (ordSnap.hasError) {
                    return StateNote(
                      icon: Icons.error_outline_rounded,
                      text: 'Orders could not be loaded.',
                      detail: Fb.friendlyMessage(ordSnap.error!),
                      tone: StateTone.danger,
                    );
                  }
                  if (!ordSnap.hasData) {
                    return const LoadingNote(label: 'Loading customers...');
                  }

                  final customers = [
                    for (final d in custSnap.data!.docs)
                      CustomerRow(
                        uid: d.id,
                        doc: d.data(),
                      ),
                  ]..sort((a, b) {
                      final at = a.joined;
                      final bt = b.joined;
                      if (at == null) return 1;
                      if (bt == null) return -1;
                      return bt.compareTo(at);
                    });

                  final ordersByCustomer = <String, List<StoreOrder>>{};
                  var unlinked = 0;
                  for (final d in ordSnap.data!.docs) {
                    final cid = (d.data()['customerId'] ?? '') as String?;
                    if (cid == null || cid.isEmpty) {
                      unlinked++;
                      continue;
                    }
                    ordersByCustomer
                        .putIfAbsent(cid, () => <StoreOrder>[])
                        .add(orderFromDoc(d));
                  }

                  final active = customers
                      .where((c) => c.status == 'active')
                      .length;

                  if (customers.isEmpty) {
                    return StateNote(
                      icon: Icons.people_outline_rounded,
                      text: 'No customer accounts yet.',
                      detail:
                          'Accounts appear here once customers create them.',
                    );
                  }

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SummaryStrip(
                        total: customers.length,
                        active: active,
                        disabled: customers.length - active,
                        unlinkedOrders: unlinked,
                      ),
                      const SizedBox(height: 14),
                      for (final c in customers)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _CustomerTile(
                            customer: c,
                            orders: ordersByCustomer[c.uid] ?? const [],
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}

/// One customer, as read from `customers/{uid}` (email/displayName are the
/// values the customer registered with; timestamps are server-side).
class CustomerRow {
  const CustomerRow({required this.uid, required this.doc});

  final String uid;
  final Map<String, dynamic> doc;

  String get email => (doc['email'] ?? '') as String;

  String get displayName => (doc['displayName'] ?? '') as String;

  String get status => (doc['status'] ?? 'active') as String;

  DateTime? get joined => fireTs(doc['createdAt']);

  /// What the admin list shows when there is no display name: the local part
  /// of their own email (clearly theirs), not a fabricated name.
  String get label {
    final name = displayName.trim();
    if (name.isNotEmpty) return name;
    final local = email.split('@').first.trim();
    if (local.isEmpty) return 'Customer';
    return local[0].toUpperCase() + local.substring(1);
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({
    required this.total,
    required this.active,
    required this.disabled,
    required this.unlinkedOrders,
  });

  final int total;
  final int active;
  final int disabled;
  final int unlinkedOrders;

  @override
  Widget build(BuildContext context) {
    Widget stat(String label, String value) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: MxColors.creamSoft,
            borderRadius: BorderRadius.circular(MxRadius.md),
            border: Border.all(color: MxColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: MxType.h4(color: MxColors.forest),
              ),
              const SizedBox(height: 1),
              Text(label, style: MxType.label(color: MxColors.stone)),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            stat('Accounts', '$total'),
            const SizedBox(width: 8),
            stat('Active', '$active'),
            const SizedBox(width: 8),
            stat('Disabled', '$disabled'),
          ],
        ),
        if (unlinkedOrders > 0) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: MxColors.warnSoft,
              borderRadius: BorderRadius.circular(MxRadius.sm),
            ),
            child: Text(
              '$unlinkedOrders '
              '${unlinkedOrders == 1 ? 'order' : 'orders'} not linked to an '
              'account (placed as a guest, or before accounts existed).',
              style: MxType.bodyXs(
                color: MxColors.warn,
                weight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _CustomerTile extends StatelessWidget {
  const _CustomerTile({required this.customer, required this.orders});

  final CustomerRow customer;
  final List<StoreOrder> orders;

  @override
  Widget build(BuildContext context) {
    final c = customer;
    final delivered = orders
        .where((o) => o.status == OrderStatus.delivered)
        .fold<double>(0, (acc, o) => acc + o.total);

    return Material(
      color: MxColors.creamSoft,
      borderRadius: BorderRadius.circular(MxRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(MxRadius.md),
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => _CustomerDetailDialog(
            customer: c,
            orders: orders,
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MxRadius.md),
            border: Border.all(color: MxColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: c.status == 'active'
                      ? MxColors.mossTint
                      : MxColors.stoneLight.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Icon(
                    Icons.person_outline_rounded,
                    size: 21,
                    color:
                        c.status == 'active' ? MxColors.moss : MxColors.stone,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      c.email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: MxType.bodyXs(color: MxColors.stone),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${orders.length} '
                      '${orders.length == 1 ? 'order' : 'orders'}'
                      '${delivered > 0 ? '  ·  ${rupees(delivered)} delivered' : ''}'
                      '${c.joined != null ? '  ·  joined ${shortWhen(c.joined!)}' : ''}',
                      style: MxType.bodyXs(color: MxColors.charcoalSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusChip(active: c.status == 'active'),
              const SizedBox(width: 4),
              const Icon(
                Icons.chevron_right_rounded,
                size: 20,
                color: MxColors.stone,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final c = active ? MxColors.ok : MxColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        active ? 'Active' : 'Disabled',
        style: MxType.bodyXs(color: c, weight: FontWeight.w700),
      ),
    );
  }
}

/// One customer, in full: their orders and the admin-only status control.
/// Never shows passwords, reset tokens or anything else credential-like.
class _CustomerDetailDialog extends StatefulWidget {
  const _CustomerDetailDialog({required this.customer, required this.orders});

  final CustomerRow customer;
  final List<StoreOrder> orders;

  @override
  State<_CustomerDetailDialog> createState() => _CustomerDetailDialogState();
}

class _CustomerDetailDialogState extends State<_CustomerDetailDialog> {
  bool _saving = false;
  String? _saveError;

  Future<void> _setStatus(String next) async {
    if (next == widget.customer.status || _saving) return;
    if (next == 'disabled') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Disable this account?'),
          content: const Text(
            'This flags the account as disabled here in the shop. It does not '
            'force the customer out of their sign-in session. You can '
            're-enable the account at any time.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(
                backgroundColor: MxColors.danger,
                foregroundColor: Colors.white,
              ),
              child: const Text('Disable account'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      // The security rules allow exactly this: an admin changing the status
      // (plus a server timestamp) and nothing else on a customer document.
      await Fb.customers.doc(widget.customer.uid).update({
        'status': next,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              next == 'active'
                  ? '${widget.customer.label} re-enabled.'
                  : '${widget.customer.label} marked as disabled.',
            ),
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
    final c = widget.customer;
    final active = c.status == 'active';
    return Dialog(
      backgroundColor: MxColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.label,
                                style: MxType.h3(color: MxColors.charcoal),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                c.email,
                                style: MxType.bodyXs(color: MxColors.stone),
                              ),
                            ],
                          ),
                        ),
                        _StatusChip(active: active),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _saveError != null
                              ? Text(
                                  _saveError!,
                                  style: MxType.bodyXs(
                                    color: MxColors.danger,
                                    weight: FontWeight.w700,
                                  ),
                                )
                              : const SizedBox.shrink(),
                        ),
                        if (active)
                          OutlinedButton.icon(
                            onPressed: _saving ? null : () => _setStatus('disabled'),
                            icon: _saving
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.block_rounded, size: 17),
                            label: const Text('Disable account'),
                          )
                        else
                          FilledButton.icon(
                            onPressed: _saving ? null : () => _setStatus('active'),
                            icon: _saving
                                ? const SizedBox(
                                    width: 15,
                                    height: 15,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.check_rounded, size: 17),
                            style: FilledButton.styleFrom(
                              backgroundColor: MxColors.ok,
                              foregroundColor: Colors.white,
                            ),
                            label: const Text('Re-enable account'),
                          ),
                      ],
                    ),
                    const Divider(color: MxColors.line, height: 30),
                    Text(
                      'Orders',
                      style: MxType.label(color: MxColors.forest),
                    ),
                    const SizedBox(height: 8),
                    if (widget.orders.isEmpty)
                      Text(
                        'No orders yet.',
                        style: MxType.bodySm(color: MxColors.stone),
                      )
                    else
                      for (final o in widget.orders)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: _CustomerOrderRow(order: o),
                        ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerOrderRow extends StatelessWidget {
  const _CustomerOrderRow({required this.order});

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
                      o.orderId,
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      '${shortWhen(o.createdAt)}  ·  ${o.totalQuantity} '
                      '${o.totalQuantity == 1 ? 'item' : 'items'}  ·  '
                      '${orderMoneyLabel(o)}',
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
