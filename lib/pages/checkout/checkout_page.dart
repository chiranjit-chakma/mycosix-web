import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../models/cart_item.dart';
import '../../models/customer_order.dart';
import '../../models/delivery_location.dart';
import '../../models/order_draft.dart';
import '../../models/product.dart';
import '../../models/store_order.dart';
import '../../repositories/order_repository.dart';
import '../../router/routes.dart';
import '../../services/order_receipt_pdf.dart';
import '../../services/pdf_browser.dart';
import '../../services/url_launcher.dart';
import '../../services/whatsapp_order_service.dart';
import '../../state/cart_controller.dart';
import '../../state/location_controller.dart';
import '../../utils/money.dart';
import '../../utils/phone.dart';
import '../../utils/validators.dart';
import '../../widgets/location/location_selector.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

/// Shared field validators — the form fields and the place-order button
/// use exactly the same rules so they can never disagree.
String? _validatePhone(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return 'Please enter your phone number';
  final digits = v.replaceAll(RegExp(r'\D'), '');
  if (!isValidIndianPhone(digits)) {
    return 'Enter a valid 10-digit Indian mobile number';
  }
  return null;
}

String? _validateEmail(String? value) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  final ok = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v);
  return ok ? null : 'Enter a valid email address';
}

String? _validateLen(String? value, int min) {
  final v = value?.trim() ?? '';
  if (v.isEmpty) return null;
  return v.length >= min ? null : 'Looks too short';
}

String? _validateBuilding(String? value) => _validateLen(value, 3);

String? _validateApartment(String? value) => _validateLen(value, 2);

String? _validateLandmark(String? value) => _validateLen(value, 3);

class CheckoutPage extends StatefulWidget {
  const CheckoutPage({super.key});

  @override
  State<CheckoutPage> createState() => _CheckoutPageState();
}

class _CheckoutPageState extends State<CheckoutPage> {
  final _formKey = GlobalKey<FormState>();

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _building = TextEditingController();
  final _apartment = TextEditingController();
  final _landmark = TextEditingController();
  final _instructions = TextEditingController();

  bool _submitted = false;
  CustomerOrder? _placed;
  bool _placing = false;
  String? _orderError;

  List<TextEditingController> get _fieldControllers => [
    _name,
    _phone,
    _email,
    _building,
    _apartment,
    _landmark,
    _instructions,
  ];

  @override
  void initState() {
    super.initState();
    // Rebuild whenever a field changes so the place-order CTA reflects
    // live validity (disabled until the order data is complete and valid).
    for (final c in _fieldControllers) {
      c.addListener(_fieldsChanged);
    }
  }

  void _fieldsChanged() {
    if (mounted) setState(() {});
  }

  /// True only when name/phone/email and the optional delivery details are all
  /// valid (optional fields are valid when empty).
  bool _detailsValid() {
    return FormValidators.name(_name.text) == null &&
        _validatePhone(_phone.text) == null &&
        _validateEmail(_email.text) == null &&
        _validateBuilding(_building.text) == null &&
        _validateApartment(_apartment.text) == null &&
        _validateLandmark(_landmark.text) == null;
  }

  String? _firstFieldHint() {
    if (FormValidators.name(_name.text) != null) {
      return 'Add your name to continue';
    }
    if (_validatePhone(_phone.text) != null) {
      return 'Add a valid 10-digit mobile number to continue';
    }
    if (_validateEmail(_email.text) != null) {
      return 'That email address does not look right';
    }
    if (_validateBuilding(_building.text) != null ||
        _validateApartment(_apartment.text) != null ||
        _validateLandmark(_landmark.text) != null) {
      return 'One of the delivery details looks too short';
    }
    return null;
  }

  @override
  void dispose() {
    for (final c in _fieldControllers) {
      c.removeListener(_fieldsChanged);
    }
    _name.dispose();
    _phone.dispose();
    _email.dispose();
    _building.dispose();
    _apartment.dispose();
    _landmark.dispose();
    _instructions.dispose();
    super.dispose();
  }

  /// Places the order: the trusted backend validates and writes it; if that
  /// backend is unreachable, checkout records a strictly money-free capture so
  /// the order still reaches the admin workflow. The confirmation is always
  /// shown on screen — WhatsApp is never opened with the order data itself.
  Future<void> _placeOrder() async {
    final cart = context.read<CartController>();
    final location = context.read<LocationController>();
    final whatsapp = context.read<WhatsAppOrderService>();
    final orderRepo = context.read<OrderRepository>();

    final loc = location.location;
    final canSend =
        !cart.isEmpty &&
        loc != null &&
        loc.confirmed &&
        loc.mapsUrl.trim().isNotEmpty;

    setState(() => _submitted = true);

    if (!(_formKey.currentState?.validate() ?? false) || !canSend) return;
    if (_placing) return;

    setState(() {
      _placing = true;
      _orderError = null;
    });

    final draft = OrderDraft(
      customerName: _name.text.trim(),
      phone: _phone.text.trim(),
      email: _email.text.trim().isEmpty ? null : _email.text.trim(),
      latitude: loc.latitude,
      longitude: loc.longitude,
      mapsUrl: loc.mapsUrl,
      building: _building.text.trim().isEmpty ? null : _building.text.trim(),
      apartment: _apartment.text.trim().isEmpty ? null : _apartment.text.trim(),
      landmark: _landmark.text.trim().isEmpty ? null : _landmark.text.trim(),
      instructions: _instructions.text.trim().isEmpty
          ? null
          : _instructions.text.trim(),
      lines: [
        for (final line in cart.lines)
          OrderDraftLine(productId: line.product.id, quantity: line.quantity),
      ],
    );

    CustomerOrder order;
    try {
      // Trusted backend: validates the draft and writes the order itself.
      final stored = await orderRepo.createOrder(draft);
      order = _orderFromStored(stored);
    } on OrderRejected catch (e) {
      // The backend refused the order (e.g. a product became unavailable or is
      // out of stock). Show the customer-safe reason; nothing was recorded and
      // nothing was handed off.
      if (!mounted) return;
      setState(() {
        _placing = false;
        _orderError = e.message;
      });
      return;
    } on BackendUnavailable {
      // No trusted backend reachable (not deployed yet / offline): record a
      // money-free capture so the shop still sees the order, then confirm on
      // screen. No WhatsApp auto-open with the order data — ever.
      final orderId = whatsapp.generateOrderId();
      try {
        await orderRepo.captureNewOrder(
          CapturedOrderData(
            orderId: orderId,
            customerName: draft.customerName,
            phone: draft.phone,
            email: draft.email,
            latitude: loc.latitude,
            longitude: loc.longitude,
            mapsUrl: loc.mapsUrl,
            building: draft.building,
            apartment: draft.apartment,
            landmark: draft.landmark,
            instructions: draft.instructions,
            lines: [
              for (final line in cart.lines)
                CapturedOrderLine(
                  productId: line.product.id,
                  productName: line.product.name,
                  quantity: line.quantity,
                  variant: line.product.variant,
                  weight: line.product.weight,
                ),
            ],
          ),
        );
      } catch (_) {
        // The capture failed too, so the order was not recorded anywhere
        // server-side. Tell the customer honestly and keep the cart so they
        // can retry.
        if (!mounted) return;
        setState(() {
          _placing = false;
          _orderError =
              'We could not record your order right now. Please check your '
              'connection and try again. Nothing has been charged.';
        });
        return;
      }
      order = _capturedFallbackOrder(cart, loc, orderId);
    }

    if (!mounted) return;
    setState(() {
      _placing = false;
      _placed = order;
    });

    // The cart has been turned into an order — empty it so the next order
    // starts fresh. The success panel keeps showing because it keys on
    // _placed, not on the cart contents.
    try {
      await cart.clear();
    } catch (_) {
      // Best-effort: a persistence failure must not undo an accepted order.
    }
  }

  /// Maps the authoritative stored order into a [CustomerOrder] whose values
  /// (order id, totals, line prices) all come from the backend, so the
  /// on-screen confirmation and the PDF receipt always match what was actually
  /// recorded.
  CustomerOrder _orderFromStored(StoreOrder stored) {
    return CustomerOrder(
      orderId: stored.orderId,
      customerName: stored.customerName,
      phone: stored.phone,
      email: stored.email,
      location: DeliveryLocation(
        latitude: stored.latitude,
        longitude: stored.longitude,
        mapsUrl: stored.mapsUrl,
        confirmed: true,
      ),
      items: [
        for (final l in stored.items)
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
      subtotal: stored.subtotal,
      deliveryFee: stored.deliveryFee,
      total: stored.total,
      building: stored.building,
      apartment: stored.apartment,
      landmark: stored.landmark,
      instructions: stored.instructions,
      createdAt: stored.createdAt ?? DateTime.now(),
    );
  }

  /// Receipt copy for a captured order: built locally from the cart with the
  /// SAME id that was recorded money-free, so the on-screen confirmation and
  /// the PDF receipt match the order in the admin list. No WhatsApp is opened.
  CustomerOrder _capturedFallbackOrder(
    CartController cart,
    DeliveryLocation loc,
    String orderId,
  ) {
    String? clean(String v) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return CustomerOrder(
      orderId: orderId,
      customerName: _name.text.trim(),
      phone: _phone.text.trim(),
      location: loc,
      items: List.of(cart.lines), // copy: the cart is cleared after placement
      subtotal: cart.subtotal,
      deliveryFee: cart.deliveryFee,
      total: cart.total,
      email: clean(_email.text),
      building: clean(_building.text),
      apartment: clean(_apartment.text),
      landmark: clean(_landmark.text),
      instructions: clean(_instructions.text),
      createdAt: DateTime.now(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cart = context.watch<CartController>();
    final location = context.watch<LocationController>().location;
    final locationReady =
        location != null &&
        location.confirmed &&
        location.mapsUrl.trim().isNotEmpty;
    final detailsValid = _detailsValid();
    final canSend = !cart.isEmpty && detailsValid && locationReady;

    // A short line under the CTA explaining why it is disabled.
    final String? ctaHint;
    if (!detailsValid) {
      ctaHint = _firstFieldHint();
    } else if (location == null) {
      ctaHint = 'Set and confirm your delivery location on the map';
    } else if (!locationReady) {
      ctaHint = 'Confirm the delivery location pin on the map';
    } else {
      ctaHint = null;
    }
    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CHECKOUT'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 12),
                Text('Almost there', style: MxType.h1(width)),
                const SizedBox(height: 14),
                Text(
                  'No account needed. Pay cash on delivery when your order '
                  'arrives - we confirm every order by a quick call or '
                  'WhatsApp message before we deliver.',
                  style: MxType.body(width),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // _placed must win over cart.isEmpty: a placed order clears the cart
          // but still needs to show its success panel.
          if (_placed != null)
            _SuccessPanel(order: _placed!)
          else if (cart.isEmpty)
            _EmptyCheckout()
          else
            MxPage(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_orderError != null) ...[
                    _OrderErrorBanner(message: _orderError!),
                    const SizedBox(height: 20),
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final desktop = constraints.maxWidth >= 960;
                      final form = _CheckoutForm(
                        formKey: _formKey,
                        submitted: _submitted,
                        name: _name,
                        phone: _phone,
                        email: _email,
                        building: _building,
                        apartment: _apartment,
                        landmark: _landmark,
                        instructions: _instructions,
                      );
                      final aside = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SummaryCard(),
                          const SizedBox(height: 20),
                          _PlaceOrderCard(
                            enabled: canSend,
                            placing: _placing,
                            hint: ctaHint,
                            onPlace: _placeOrder,
                          ),
                        ],
                      );
                      return desktop
                          ? Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(flex: 7, child: form),
                                const SizedBox(width: 40),
                                Expanded(flex: 5, child: aside),
                              ],
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                form,
                                const SizedBox(height: 28),
                                aside,
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}

/// Right-rail order summary (shared with the cart page styling).
class _SummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: MxType.h3(color: MxColors.charcoal)),
          const SizedBox(height: 16),
          for (final line in cart.lines) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${line.product.name} (${line.product.weight})',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: MxType.bodySm(color: MxColors.charcoalSoft),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  '× ${line.quantity}',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
          ],
          const Divider(color: MxColors.line, height: 24),
          _Row(label: 'Subtotal', value: formatRupees(cart.subtotal)),
          const SizedBox(height: 8),
          _Row(
            label: 'Delivery',
            value: cart.deliveryFee > 0
                ? formatRupees(cart.deliveryFee)
                : 'Free',
          ),
          const Divider(color: MxColors.line, height: 24),
          _Row(label: 'Total', value: formatRupees(cart.total), bold: true),
          const SizedBox(height: 4),
          Text(
            '${cart.totalQuantity} item${cart.totalQuantity == 1 ? '' : 's'} in this order',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: MxType.bodySm(
            color: MxColors.charcoalSoft,
            weight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: MxType.bodySm(
            color: MxColors.forest,
            weight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Form fields: name + phone required, the rest optional.
class _CheckoutForm extends StatelessWidget {
  const _CheckoutForm({
    required this.formKey,
    required this.submitted,
    required this.name,
    required this.phone,
    required this.email,
    required this.building,
    required this.apartment,
    required this.landmark,
    required this.instructions,
  });

  final GlobalKey<FormState> formKey;
  final bool submitted;
  final TextEditingController name;
  final TextEditingController phone;
  final TextEditingController email;
  final TextEditingController building;
  final TextEditingController apartment;
  final TextEditingController landmark;
  final TextEditingController instructions;

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your details', style: MxType.h3(color: MxColors.charcoal)),
          const SizedBox(height: 18),
          TextFormField(
            controller: name,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Full name *',
              hintText: 'What should we call you?',
              prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
            ),
            validator: FormValidators.name,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: phone,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.phone,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Phone / WhatsApp *',
              hintText: '10-digit mobile number',
              prefixIcon: Icon(Icons.phone_outlined, size: 20),
            ),
            validator: _validatePhone,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: email,
            textInputAction: TextInputAction.next,
            keyboardType: TextInputType.emailAddress,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Email (optional)',
              hintText: 'you@example.com',
              prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 28),
          Text('Delivery details', style: MxType.h3(color: MxColors.charcoal)),
          const SizedBox(height: 6),
          Text(
            'These are optional, but they help our rider find you.',
            style: MxType.bodySm(color: MxColors.stone),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: building,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Building / House',
              hintText: 'House number, street or building name',
              prefixIcon: Icon(Icons.home_outlined, size: 20),
            ),
            validator: _validateBuilding,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: apartment,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Apartment / Unit',
              hintText: 'Flat / door number, tower, floor',
              prefixIcon: Icon(Icons.apartment_rounded, size: 20),
            ),
            validator: _validateApartment,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: landmark,
            textInputAction: TextInputAction.next,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Landmark',
              hintText: 'Near a well-known place?',
              prefixIcon: Icon(Icons.place_outlined, size: 20),
            ),
            validator: _validateLandmark,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: instructions,
            textInputAction: TextInputAction.newline,
            maxLines: 2,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'Delivery instructions (optional)',
              hintText: 'Ring the bell twice, leave at the gate, etc.',
              prefixIcon: Icon(Icons.notes_rounded, size: 20),
            ),
          ),
          const SizedBox(height: 28),
          Text('Delivery location', style: MxType.h3(color: MxColors.charcoal)),
          const SizedBox(height: 14),
          const LocationSelector(),
          if (submitted)
            Builder(
              builder: (context) {
                final location = context.watch<LocationController>().location;
                final confirmed = location != null && location.confirmed;
                if (confirmed) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 16,
                        color: MxColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          location == null
                              ? 'Please set and confirm your delivery location.'
                              : 'Please confirm the delivery location pin.',
                          style: MxType.bodySm(
                            color: MxColors.danger,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

/// Place-order card: records the order (trusted backend, or a money-free
/// capture) and shows the confirmation on screen. The order data itself is
/// never sent over WhatsApp — the confirmation screen and stored record are
/// what confirm the order.
class _PlaceOrderCard extends StatelessWidget {
  const _PlaceOrderCard({
    required this.enabled,
    required this.placing,
    required this.hint,
    required this.onPlace,
  });

  final bool enabled;
  final bool placing;
  final String? hint;
  final VoidCallback onPlace;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Container(
      padding: EdgeInsets.all(width >= 480 ? 22 : 18),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: MxColors.moss,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.payments,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Place your order',
                style: MxType.h4(color: MxColors.charcoal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Pay cash on delivery — no online payment. Your order is confirmed '
            'on this screen, and we follow up with a call or WhatsApp message '
            'before we deliver.',
            style: MxType.bodySm(color: MxColors.stone),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: enabled && !placing ? onPlace : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: MxColors.forest,
                foregroundColor: Colors.white,
                disabledBackgroundColor: MxColors.stoneLight.withValues(
                  alpha: 0.25,
                ),
                disabledForegroundColor: MxColors.stone,
              ),
              child: placing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Place order - cash on delivery'),
            ),
          ),
          if (!enabled && !placing && hint != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: MxColors.stone,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    hint!,
                    style: MxType.bodyXs(color: MxColors.stone),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OrderErrorBanner extends StatelessWidget {
  const _OrderErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MxColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            size: 17,
            color: MxColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: MxType.bodySm(
                color: MxColors.danger,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Confirmation panel. Shows ONLY the confirmed state and the order id — no
/// items and no amounts on screen. The full receipt is available locally as a
/// branded PDF the customer can view or download, and WhatsApp offers only a
/// short, non-authoritative notice (never the order data).
class _SuccessPanel extends StatefulWidget {
  const _SuccessPanel({required this.order});

  final CustomerOrder order;

  @override
  State<_SuccessPanel> createState() => _SuccessPanelState();
}

class _SuccessPanelState extends State<_SuccessPanel> {
  ReceiptAssets? _assets;
  bool _pdfBusy = false;
  String? _pdfError;

  CustomerOrder get order => widget.order;

  Future<void> _pdfAction({required bool download}) async {
    if (_pdfBusy) return;
    setState(() {
      _pdfBusy = true;
      _pdfError = null;
    });
    try {
      final assets = _assets ??= await ReceiptAssets.fromAssets();
      final bytes = await buildOrderReceiptPdf(order, assets: assets);
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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return MxPage(
      child: Container(
        padding: EdgeInsets.all(width >= 768 ? 48 : 28),
        decoration: BoxDecoration(
          color: MxColors.okSoft,
          borderRadius: BorderRadius.circular(MxRadius.lg),
          border: Border.all(color: MxColors.ok.withValues(alpha: 0.4)),
        ),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: const BoxDecoration(
                color: MxColors.ok,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 22),
            Text('Order confirmed', style: MxType.h2(width)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: MxColors.creamSoft,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: MxColors.ok.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                order.orderId,
                style: MxType.h4(color: MxColors.forest),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                'Your order has been received. Pay cash on delivery — we will '
                'confirm it with a quick call or WhatsApp message before we '
                'deliver. Keep your receipt below for the full order details; '
                'we will never ask you to send your order over WhatsApp.',
                textAlign: TextAlign.center,
                style: MxType.bodySm(color: MxColors.charcoalSoft),
              ),
            ),
            if (_pdfError != null) ...[
              const SizedBox(height: 12),
              Text(_pdfError!, style: MxType.bodyXs(color: MxColors.danger)),
            ],
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: _pdfBusy ? null : () => _pdfAction(download: false),
                  icon: _pdfBusy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('View receipt'),
                ),
                OutlinedButton.icon(
                  onPressed: _pdfBusy ? null : () => _pdfAction(download: true),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Download receipt'),
                ),
                OutlinedButton.icon(
                  onPressed: _whatsappHandoff,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('Notify on WhatsApp'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                  label: const Text('Continue shopping'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                'The WhatsApp button only sends MYCOSIX a short notice that '
                'your order is confirmed — it never sends your order details.',
                textAlign: TextAlign.center,
                style: MxType.bodyXs(color: MxColors.stone),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyCheckout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return MxPage(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            const Icon(
              Icons.shopping_bag_outlined,
              size: 44,
              color: MxColors.stoneLight,
            ),
            const SizedBox(height: 16),
            Text('Nothing to check out yet', style: MxType.h2(width)),
            const SizedBox(height: 10),
            Text(
              'Add some fresh mushrooms to your cart first.',
              style: MxType.bodySm(color: MxColors.stone),
            ),
            const SizedBox(height: 26),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Browse the shop'),
            ),
          ],
        ),
      ),
    );
  }
}
