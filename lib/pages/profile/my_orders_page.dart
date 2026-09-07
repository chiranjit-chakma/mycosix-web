import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../firebase/fb.dart';
import '../../models/cart_item.dart';
import '../../models/customer_order.dart';
import '../../models/delivery_location.dart';
import '../../models/order_status.dart';
import '../../models/product.dart';
import '../../models/store_order.dart';
import '../../router/routes.dart';
import '../../services/order_receipt_pdf.dart';
import '../../services/pdf_browser.dart';
import '../../services/url_launcher.dart';
import '../../services/whatsapp_order_service.dart';
import '../../state/customer_auth_controller.dart';
import '../../utils/money.dart';
import '../../widgets/account_locked.dart';
import '../../widgets/delivery_progress.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

/// The signed-in customer's own orders.
///
/// Queries the shared orders collection filtered to this account
/// (`customerId == my uid` — an IDOR-safe, rules-enforced owner filter; the
/// page never trusts a URL or a passed-in id). Guests and offline sessions
/// see an honest locked state instead.
class MyOrdersPage extends StatelessWidget {
  const MyOrdersPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final auth = context.watch<CustomerAuthController>();

    if (!auth.backendAvailable || auth.user == null) {
      return LockedAccountPage(
        title: 'My Orders',
        icon: Icons.receipt_long_outlined,
        message:
            'Sign in to follow your orders — status updates, what you ordered '
            'and the amount you agreed at checkout.',
        returnRoute: Routes.myOrders,
      );
    }
    final uid = auth.uid!;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR ACCOUNT'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 12),
                Text('My Orders', style: MxType.h1(width)),
                const SizedBox(height: 10),
                Text(
                  'Orders you placed while signed in, in one place. For '
                  'anything else, call or message us and we will help.',
                  style: MxType.bodySm(color: MxColors.stone),
                ),
                const SizedBox(height: 28),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: Fb.orders
                      .where('customerId', isEqualTo: uid)
                      .orderBy('createdAt', descending: true)
                      .limit(200)
                      .snapshots(),
                  builder: (context, snap) {
                    if (snap.hasError) {
                      return _Note(
                        icon: Icons.error_outline_rounded,
                        text: 'Your orders could not be loaded right now.',
                        detail: Fb.friendlyMessage(snap.error!),
                      );
                    }
                    if (!snap.hasData) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 48),
                          child:
                              CircularProgressIndicator(color: MxColors.moss),
                        ),
                      );
                    }
                    final orders = [
                      for (final d in snap.data!.docs) _orderFromDoc(d),
                    ];
                    if (orders.isEmpty) {
                      return _Note(
                        icon: Icons.receipt_long_outlined,
                        text: 'No orders yet.',
                        detail:
                            'When you place an order while signed in, it will '
                            'appear here so you can follow it.',
                      );
                    }
                    return Column(
                      children: [
                        for (final o in orders)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _OrderCard(order: o),
                          ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static StoreOrder _orderFromDoc(
    DocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final m = d.data() ?? const <String, dynamic>{};
    return StoreOrder.fromMap(
      m,
      id: d.id,
      createdAt: _fireTs(m['createdAt']),
      updatedAt: _fireTs(m['updatedAt']),
      deliveredAt: _fireTs(m['deliveredAt']),
    );
  }

  static DateTime? _fireTs(Object? v) {
    if (v is DateTime) return v.toLocal();
    if (v != null) {
      try {
        return (v as dynamic).toDate().toLocal() as DateTime;
      } catch (_) {
        return null;
      }
    }
    return null;
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.text, this.detail});

  final IconData icon;
  final String text;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return MxPanel(
      child: Column(
        children: [
          Icon(icon, size: 34, color: MxColors.stone),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: MxType.bodySm(color: MxColors.charcoalSoft),
          ),
          if (detail != null) ...[
            const SizedBox(height: 6),
            Text(
              detail!,
              textAlign: TextAlign.center,
              style: MxType.bodyXs(color: MxColors.stone),
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order});

  final StoreOrder order;

  @override
  Widget build(BuildContext context) {
    final o = order;
    return Material(
      color: MxColors.creamSoft,
      borderRadius: BorderRadius.circular(MxRadius.md),
      child: InkWell(
        onTap: () => showDialog<void>(
          context: context,
          builder: (context) => _OrderDetail(order: o),
        ),
        borderRadius: BorderRadius.circular(MxRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MxRadius.md),
            border: Border.all(color: MxColors.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.orderId,
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                  _StatusPill(status: o.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '${_when(o.createdAt)}  ·  ${o.totalQuantity} '
                '${o.totalQuantity == 1 ? 'item' : 'items'}  ·  '
                '${formatRupees(o.total)}',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
              const SizedBox(height: 4),
              Text(
                o.items.map((l) => l.productName).join(', '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: MxType.bodyXs(color: MxColors.charcoalSoft),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderDetail extends StatefulWidget {
  const _OrderDetail({required this.order});

  final StoreOrder order;

  @override
  State<_OrderDetail> createState() => _OrderDetailState();
}

class _OrderDetailState extends State<_OrderDetail> {
  ReceiptAssets? _assets;
  bool _pdfBusy = false;
  String? _pdfError;

  StoreOrder get order => widget.order;

  Future<void> _pdfAction({required bool download}) async {
    if (_pdfBusy) return;
    setState(() {
      _pdfBusy = true;
      _pdfError = null;
    });
    try {
      final assets = _assets ??= await ReceiptAssets.fromAssets();
      final receipt = _receiptOrder(order);
      final bytes = await buildOrderReceiptPdf(receipt, assets: assets);
      if (download) {
        PdfBrowser.download(bytes, 'MYCOSIX-${order.orderId}.pdf');
      } else {
        PdfBrowser.view(bytes, 'MYCOSIX-${order.orderId}.pdf');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pdfError =
            'Your receipt could not be prepared right now. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _pdfBusy = false);
    }
  }

  void _whatsappHandoff() {
    final whatsapp = context.read<WhatsAppOrderService>();
    UrlLauncher.open(whatsapp.confirmationHandoffUrl(order.orderId));
  }

  /// Rebuilds the stored order into a [CustomerOrder] so the same receipt
  /// builder the checkout screen uses renders byte-for-byte the same document.
  /// Values all come from the stored order; legacy money-free captures render
  /// their stored amounts (₹0) honestly.
  static CustomerOrder _receiptOrder(StoreOrder o) {
    return CustomerOrder(
      orderId: o.orderId,
      customerName: o.customerName,
      phone: o.phone,
      email: o.email,
      location: DeliveryLocation(
        latitude: o.latitude,
        longitude: o.longitude,
        mapsUrl: o.mapsUrl,
        confirmed: true,
      ),
      items: [
        for (final l in o.items)
          CartItem(
            product: Product(
              id: l.productId,
              name: l.productName,
              description: '',
              category: '',
              image: '',
              variant: l.variant ?? '',
              weight: l.weight ?? '',
              price: l.unitPrice,
              stock: 0,
            ),
            quantity: l.quantity,
          ),
      ],
      subtotal: o.subtotal,
      deliveryFee: o.deliveryFee,
      total: o.total,
      building: o.building,
      apartment: o.apartment,
      landmark: o.landmark,
      instructions: o.instructions,
      createdAt: o.createdAt ?? DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = order;
    final address = [
      o.building,
      o.apartment,
      o.landmark,
    ].whereType<String>().where((s) => s.trim().isNotEmpty).join(', ');

    return Dialog(
      backgroundColor: MxColors.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      o.orderId,
                      style: MxType.h3(color: MxColors.charcoal),
                    ),
                  ),
                  _StatusPill(status: o.status),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Placed ${_when(o.createdAt)}',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
              const SizedBox(height: 14),
              // The line-filling tracker: live status from the admin's last
              // update, filling up as the order moves forward.
              DeliveryProgress(status: o.status),
              const SizedBox(height: 18),
              for (final l in o.items)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          '${l.quantity} × ${l.productName}',
                          style: MxType.bodySm(color: MxColors.charcoalSoft),
                        ),
                      ),
                      Text(
                        formatRupees(l.lineTotal),
                        style: MxType.bodySm(
                          color: MxColors.charcoal,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              const Divider(color: MxColors.line, height: 18),
              _amountRow('Subtotal', o.subtotal),
              _amountRow('Delivery fee', o.deliveryFee),
              const SizedBox(height: 4),
              _amountRow('Total', o.total, strong: true),
              if (!o.verified) ...[
                const SizedBox(height: 10),
                Text(
                  'Order value shown is what you agreed at checkout; we '
                  'confirm it with you by phone before packing.',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ],
              if (address.isNotEmpty) ...[
                const SizedBox(height: 18),
                Text('Deliver to', style: MxType.label(color: MxColors.forest)),
                const SizedBox(height: 4),
                Text(address, style: MxType.bodySm(color: MxColors.charcoalSoft)),
                const SizedBox(height: 2),
                Text(
                  o.mapsUrl,
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ],
              if (_pdfError != null) ...[
                const SizedBox(height: 12),
                Text(_pdfError!, style: MxType.bodyXs(color: MxColors.danger)),
              ],
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.tonalIcon(
                    onPressed:
                        _pdfBusy ? null : () => _pdfAction(download: false),
                    icon: _pdfBusy
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_outlined, size: 17),
                    label: const Text('View receipt'),
                  ),
                  OutlinedButton.icon(
                    onPressed:
                        _pdfBusy ? null : () => _pdfAction(download: true),
                    icon: const Icon(Icons.download_rounded, size: 17),
                    label: const Text('Download receipt'),
                  ),
                  FilledButton.icon(
                    onPressed: _whatsappHandoff,
                    style: FilledButton.styleFrom(
                      backgroundColor: MxColors.forest,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 17),
                    label: const Text('Message us on WhatsApp'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'The WhatsApp button sends MYCOSIX a short notice for this '
                'order so we can reply with the delivery time — it never '
                'sends your order details.',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Widget _amountRow(String label, double amount, {bool strong = false}) {
    final style = strong
        ? MxType.bodySm(color: MxColors.charcoal, weight: FontWeight.w800)
        : MxType.bodyXs(color: MxColors.charcoalSoft);
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(formatRupees(amount), style: style),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final c = switch (status) {
      OrderStatus.newOrder => MxColors.earth,
      OrderStatus.contacted => MxColors.stone,
      OrderStatus.confirmed => MxColors.moss,
      OrderStatus.preparing => MxColors.warn,
      OrderStatus.outForDelivery => MxColors.mossDeep,
      OrderStatus.delivered => MxColors.ok,
      OrderStatus.cancelled => MxColors.danger,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.customerLabel,
        style: MxType.bodyXs(color: c, weight: FontWeight.w700),
      ),
    );
  }
}

String _when(DateTime? t) {
  if (t == null) return '-';
  String two(int v) => v.toString().padLeft(2, '0');
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${two(t.day)} ${months[t.month - 1]} ${t.year}, '
      '${two(t.hour)}:${two(t.minute)}';
}
