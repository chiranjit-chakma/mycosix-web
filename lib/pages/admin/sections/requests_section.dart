import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/order_request.dart';
import '../../../models/order_status.dart';
import '../../../models/order_status_update.dart';
import '../../../models/store_order.dart';
import '../../../state/auth_controller.dart';
import '../admin_widgets.dart';
import '../order_detail.dart';

/// Customer requests workflow (zero-budget foundation).
///
/// Requests reach the farm over WhatsApp/phone/email and an admin records them
/// here linked to the order involved. There is no paid inbound-messaging or AI
/// service yet, so nothing here is automatic: a decision on a request only
/// changes the request's own status and always shows the admin the exact manual
/// step to take on the real order. When a trusted backend exists later it can
/// create requests in exactly this shape.
class RequestsSection extends StatefulWidget {
  const RequestsSection({super.key});

  @override
  State<RequestsSection> createState() => _RequestsSectionState();
}

class _RequestsSectionState extends State<RequestsSection> {
  OrderRequestStatus? _filter;
  List<OrderRequest> _requests = const [];
  final Map<String, StoreOrder> _byOrderId = {};
  Object? _requestsError;
  Object? _ordersError;
  bool _loading = true;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _reqSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSub;

  @override
  void initState() {
    super.initState();
    _reqSub = Fb.orderRequests
        .orderBy('recordedAt', descending: true)
        .limit(200)
        .snapshots()
        .listen(_onRequests, onError: (Object e) {
      if (!mounted) return;
      setState(() {
        _requestsError = e;
        _loading = false;
      });
    });
    _ordersSub = Fb.orders
        .orderBy('createdAt', descending: true)
        .limit(400)
        .snapshots()
        .listen(_onOrders, onError: (Object e) {
      if (!mounted) return;
      setState(() => _ordersError = e);
    });
  }

  void _onRequests(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final list = <OrderRequest>[];
    for (final d in snap.docs) {
      final m = d.data();
      list.add(
        OrderRequest.fromMap(
          m,
          id: d.id,
          orderCreatedAt: fireTs(m['orderCreatedAt']),
          recordedAt: fireTs(m['recordedAt']),
          decisionAt: fireTs(m['decisionAt']),
        ),
      );
    }
    setState(() {
      _requests = list;
      _requestsError = null;
      _loading = false;
    });
  }

  void _onOrders(QuerySnapshot<Map<String, dynamic>> snap) {
    if (!mounted) return;
    final map = <String, StoreOrder>{};
    for (final d in snap.docs) {
      final o = orderFromDoc(d);
      map[o.orderId] = o;
    }
    setState(() {
      _byOrderId
        ..clear()
        ..addAll(map);
      _ordersError = null;
    });
  }

  @override
  void dispose() {
    _reqSub?.cancel();
    _ordersSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Customer requests',
            subtitle:
                'Recorded here from WhatsApp/phone by the team. Decisions are '
                'manual and always show the exact step to take on the order.',
            trailing: FilledButton.icon(
              onPressed: _openNewRequest,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New request'),
            ),
          ),
          const SizedBox(height: 12),
          _filters(),
          const SizedBox(height: 12),
          if (_ordersError != null) ...[
            StateNote(
              icon: Icons.warning_amber_rounded,
              text: 'Linked orders could not be loaded.',
              detail:
                  'Request rows may show less order detail until the Orders '
                  'connection recovers.',
              tone: StateTone.warn,
            ),
            const SizedBox(height: 10),
          ],
          if (_requestsError != null)
            StateNote(
              icon: Icons.error_outline_rounded,
              text: 'Requests could not be loaded.',
              detail: Fb.friendlyMessage(_requestsError!),
              tone: StateTone.danger,
            )
          else if (_loading)
            const LoadingNote(label: 'Loading requests...')
          else if (_requests.isEmpty)
            const StateNote(
              icon: Icons.forum_outlined,
              text: 'No customer requests yet.',
              detail:
                  'When a customer asks to change or cancel an order (by '
                  'WhatsApp, phone or email), record it here with "New request".',
            )
          else
            for (final r in _requests)
              if (_filter == null || r.status == _filter)
                _RequestCard(
                  key: ObjectKey(r.id),
                  request: r,
                  order: _byOrderId[r.orderId],
                  onDecide: _decide,
                  onResolve: () => _decide(r, null),
                ),
        ],
      ),
    );
  }

  Widget _filters() {
    Widget chip(String label, OrderRequestStatus? value) {
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
          for (final s in OrderRequestStatus.values) chip(s.label, s),
        ],
      ),
    );
  }

  Future<void> _openNewRequest() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => NewRequestDialog(orders: _byOrderId.values.toList()),
    );
    if (created == true && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Request recorded.')),
        );
    }
  }

  Future<void> _decide(OrderRequest request, bool? approved) async {
    final note = approved == null
        ? null
        : await _noteDialog(approved ? 'Approve request' : 'Reject request');
    if (approved != null && note == null) return; // cancelled by admin
    if (!mounted) return;
    final actor = context.read<AuthController>().user?.email;
    final next = approved == null
        ? OrderRequestStatus.resolved
        : approved
            ? OrderRequestStatus.approved
            : OrderRequestStatus.rejected;
    try {
      await Fb.orderRequests.doc(request.id).update(
            request.decisionFields(
              next,
              timestamp: FieldValue.serverTimestamp(),
              decidedByEmail: actor,
              decisionNote: note,
            ),
          );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Fb.friendlyMessage(e))));
    }
  }

  Future<String?> _noteDialog(String title) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'Note for the customer / team (optional)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return note;
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({
    super.key,
    required this.request,
    required this.order,
    required this.onDecide,
    required this.onResolve,
  });

  final OrderRequest request;
  final StoreOrder? order;
  final void Function(OrderRequest, bool?) onDecide;
  final VoidCallback onResolve;

  @override
  Widget build(BuildContext context) {
    final type = request.requestType;
    final cancellation = type == OrderRequestType.cancellation;
    final withinWindow = cancellation &&
        order?.createdAt != null &&
        isWithinCancelWindow(order!.createdAt!);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(
          color: request.open
              ? MxColors.warn.withValues(alpha: 0.5)
              : MxColors.line,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypePill(type: type),
              const SizedBox(width: 8),
              _StatusPill(status: request.status),
              if (cancellation && order?.createdAt != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: (withinWindow ? MxColors.ok : MxColors.danger)
                        .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    withinWindow
                        ? 'Inside 15-min window'
                        : 'Past 15-min window',
                    style: MxType.bodyXs(
                      color: withinWindow ? MxColors.ok : MxColors.danger,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Text(
                'Recorded ${shortWhen(request.recordedAt)}',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            request.requestDetail,
            style: MxType.bodySm(color: MxColors.charcoal),
          ),
          const SizedBox(height: 8),
          _orderLine(context),
          const SizedBox(height: 10),
          if (request.decisionNote != null ||
              request.decidedByEmail != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: MxColors.cream,
                borderRadius: BorderRadius.circular(MxRadius.sm),
                border: Border.all(color: MxColors.line),
              ),
              child: Text(
                'Decision by ${request.decidedByEmail ?? 'admin'}'
                '${request.decisionNote == null || request.decisionNote!.isEmpty ? '' : ' - ${request.decisionNote}'}'
                '${request.decisionAt == null ? '' : ' at ${shortWhen(request.decisionAt)}'}',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
            ),
            const SizedBox(height: 8),
          ],
          if (request.status == OrderRequestStatus.approved) ...[
            _manualBox(context),
            const SizedBox(height: 8),
          ],
          if (request.status == OrderRequestStatus.pending)
            Row(
              children: [
                const Spacer(),
                OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: MxColors.danger,
                    side: const BorderSide(color: MxColors.danger),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => onDecide(request, false),
                  child: const Text('Reject'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: MxColors.ok,
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () => onDecide(request, true),
                  child: const Text('Approve'),
                ),
              ],
            )
          else if (request.status == OrderRequestStatus.approved)
            Row(
              children: [
                if (order != null && request.requestType == OrderRequestType.cancellation)
                  OutlinedButton.icon(
                    onPressed: () => _cancelOrder(context, order!),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel linked order now'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: MxColors.danger,
                      side: const BorderSide(color: MxColors.danger),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: onResolve,
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: const Text('Mark resolved'),
                  style: FilledButton.styleFrom(
                    backgroundColor: MxColors.forest,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _orderLine(BuildContext context) {
    final o = order;
    if (o == null) {
      final hasLink = request.orderId != null;
      return Row(
        children: [
          Icon(
            Icons.link_off_rounded,
            size: 15,
            color: hasLink ? MxColors.warn : MxColors.stone,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hasLink
                  ? 'Linked order ${request.orderId} is not in the recent order list - open Orders to check.'
                  : 'No order linked (general request).',
              style: MxType.bodyXs(color: MxColors.stone),
            ),
          ),
        ],
      );
    }
    return Row(
      children: [
        const Icon(Icons.receipt_long_outlined, size: 15, color: MxColors.forest),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '${o.orderId} | ${o.customerName} | placed ${shortWhen(o.createdAt)}',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
        ),
        const SizedBox(width: 8),
        StatusPill(status: o.status),
        const SizedBox(width: 6),
        InkWell(
          onTap: () => showOrderDetail(context, o),
          child: Text(
            'Open order',
            style: MxType.bodyXs(
              color: MxColors.forest,
              weight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }

  bool get cancellation =>
      request.requestType == OrderRequestType.cancellation;

  Widget _manualBox(BuildContext context) {
    final o = order;
    final canOpen = o != null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: MxColors.warnSoft,
        borderRadius: BorderRadius.circular(MxRadius.sm),
        border: Border.all(color: MxColors.warn.withValues(alpha: 0.45)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.construction_rounded, size: 17, color: MxColors.warn),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Manual step needed',
                  style: MxType.bodyXs(
                    color: MxColors.warn,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  manualStepFor(request.requestType),
                  style: MxType.bodyXs(color: MxColors.charcoalSoft),
                ),
                if (canOpen && cancellation) ...[
                  const SizedBox(height: 2),
                  Text(
                    'Tip: use "Cancel linked order now" above, then mark '
                    'resolved.',
                    style: MxType.bodyXs(color: MxColors.charcoalSoft),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancelOrder(BuildContext context, StoreOrder o) async {
    if (o.id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel this order?'),
        content: Text(
          'Move ${o.orderId} to Cancelled (${o.customerName}, ${rupees(o.total)})? '
          'Firestore rules only allow this while the order is still cancellable.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep order'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MxColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancel order'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await Fb.orders.doc(o.id).update(
        orderStatusUpdateFields(
          OrderStatus.cancelled,
          FieldValue.serverTimestamp(),
        ),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('${o.orderId} is now Cancelled.')),
        );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Fb.friendlyMessage(e))));
    }
  }
}

class _TypePill extends StatelessWidget {
  const _TypePill({required this.type});

  final OrderRequestType type;

  @override
  Widget build(BuildContext context) {
    final c = switch (type) {
      OrderRequestType.cancellation => MxColors.danger,
      OrderRequestType.quantityChange => MxColors.earth,
      OrderRequestType.productChange => MxColors.warn,
      OrderRequestType.deliveryCorrection => MxColors.moss,
      OrderRequestType.assistance => MxColors.stone,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        type.label,
        style: MxType.bodyXs(color: c, weight: FontWeight.w700),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final OrderRequestStatus status;

  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      OrderRequestStatus.pending => MxColors.warn,
      OrderRequestStatus.approved => MxColors.moss,
      OrderRequestStatus.rejected => MxColors.danger,
      OrderRequestStatus.resolved => MxColors.ok,
      OrderRequestStatus.expired => MxColors.stone,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.label,
        style: MxType.bodyXs(color: c, weight: FontWeight.w700),
      ),
    );
  }
}

/// Form used by an admin to record a request that reached them over
/// WhatsApp/phone/email. Requires a type and the customer's request; the linked
/// order is optional (general assistance needs no order).
class NewRequestDialog extends StatefulWidget {
  const NewRequestDialog({super.key, required this.orders});

  final List<StoreOrder> orders;

  @override
  State<NewRequestDialog> createState() => _NewRequestDialogState();
}

class _NewRequestDialogState extends State<NewRequestDialog> {
  OrderRequestType? _type;
  String? _orderId;
  final _detail = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _detail.dispose();
    super.dispose();
  }

  StoreOrder? get _order {
    if (_orderId == null) return null;
    for (final o in widget.orders) {
      if (o.orderId == _orderId) return o;
    }
    return null;
  }

  Future<void> _save() async {
    if (_busy) return;
    if (_type == null) {
      setState(() => _error = 'Choose what kind of request this is.');
      return;
    }
    final detail = _detail.text.trim();
    if (detail.isEmpty) {
      setState(() => _error = 'Write what the customer asked.');
      return;
    }
    final linked = _order;
    final actor = context.read<AuthController>().user?.email;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final request = OrderRequest(
        id: '',
        requestType: _type!,
        requestDetail: detail,
        status: OrderRequestStatus.pending,
        orderId: linked?.orderId,
        orderStatusLabel: linked?.status.label,
        customerName: linked?.customerName,
        phone: linked?.phone,
        recordedByEmail: actor,
      );
      final map = request.toMap();
      map['recordedAt'] = FieldValue.serverTimestamp();
      await Fb.orderRequests.add(map);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = Fb.friendlyMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final orders = widget.orders;
    return AlertDialog(
      title: const Text('Record a customer request'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'A customer contacted you by WhatsApp/phone/email. Record the '
                'request here; you decide it manually later.',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
              const SizedBox(height: 12),
              Text('Type of request', style: MxType.bodyXs(
                color: MxColors.charcoal,
                weight: FontWeight.w700,
              )),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final t in OrderRequestType.values)
                    ChoiceChip(
                      label: Text(t.label),
                      selected: _type == t,
                      showCheckmark: false,
                      onSelected: (_) => setState(() => _type = t),
                      selectedColor: MxColors.mossSoft,
                      labelStyle: MxType.bodyXs(
                        color: _type == t
                            ? MxColors.forest
                            : MxColors.charcoalSoft,
                        weight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _orderId,
                decoration: const InputDecoration(
                  labelText: 'Linked order (optional)',
                ),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('No order - general request'),
                  ),
                  for (final o in orders)
                    DropdownMenuItem(
                      value: o.orderId,
                      child: Text(
                        '${o.orderId} | ${o.customerName} | ${o.status.label}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _orderId = v),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _detail,
                maxLines: 3,
                maxLength: 600,
                decoration: const InputDecoration(
                  labelText: 'What did the customer ask? *',
                  hintText:
                      'e.g. "Please cancel my order, my plans changed" or '
                      '"Can I change the delivery address?"',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    _error!,
                    style: MxType.bodyXs(
                      color: MxColors.danger,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Recording...' : 'Record request'),
        ),
      ],
    );
  }
}
