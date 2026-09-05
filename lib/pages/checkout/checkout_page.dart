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

/// Shared field validators — the form fields and the WhatsApp-button gating
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
  bool _opening = false;
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
    // Rebuild whenever a field changes so the WhatsApp CTA reflects live
    // validity (disabled until the order data is complete and valid).
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
    if (_opening) return;

    setState(() {
      _opening = true;
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
      // The backend refused the order (e.g. a product became unavailable).
      // Show the customer-safe reason; nothing was handed off or recorded.
      if (!mounted) return;
      setState(() {
        _opening = false;
        _orderError = e.message;
      });
      return;
    } on BackendUnavailable {
      // No trusted backend reachable (not deployed yet / offline): keep the
      // exact Part 1 flow. The WhatsApp message is prepared here with a local
      // id; nothing is claimed to be recorded server-side.
      order = _localFallbackOrder(cart, whatsapp, loc);
    }

    final url = whatsapp.openHandoff(order);
    UrlLauncher.open(url); // handoff only: the customer presses Send.

    if (!mounted) return;
    setState(() {
      _opening = false;
      _placed = order;
    });
  }

  /// Maps the authoritative stored order into a [CustomerOrder] whose values
  /// (order id, totals, line prices) all come from the backend, so the
  /// WhatsApp message always matches what was actually recorded.
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

  /// Part 1 fallback: WhatsApp handoff with a locally generated order id.
  CustomerOrder _localFallbackOrder(
    CartController cart,
    WhatsAppOrderService whatsapp,
    DeliveryLocation loc,
  ) {
    String? clean(String v) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return CustomerOrder(
      orderId: whatsapp.generateOrderId(),
      customerName: _name.text.trim(),
      phone: _phone.text.trim(),
      location: loc,
      items: cart.lines,
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
                  'No account needed. Tell us where to deliver and we will '
                  'confirm your order on WhatsApp.',
                  style: MxType.body(width),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (cart.isEmpty)
            _EmptyCheckout()
          else if (_placed != null)
            _SuccessPanel(order: _placed!)
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
                          _WhatsAppCard(
                            enabled: canSend,
                            opening: _opening,
                            hint: ctaHint,
                            onPlace: _placeOrder,
                          ),
                          const SizedBox(height: 14),
                          const _HandoffNote(),
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

class _WhatsAppCard extends StatelessWidget {
  const _WhatsAppCard({
    required this.enabled,
    required this.opening,
    required this.hint,
    required this.onPlace,
  });

  final bool enabled;
  final bool opening;
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
              const _WhatsAppIcon(),
              const SizedBox(width: 10),
              Text(
                'Place order on WhatsApp',
                style: MxType.h4(color: MxColors.charcoal),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'We open WhatsApp with your order ready to send — you review it '
            'there and press Send to confirm.',
            style: MxType.bodySm(color: MxColors.stone),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: enabled && !opening ? onPlace : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF128C4A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: MxColors.stoneLight.withValues(
                  alpha: 0.25,
                ),
                disabledForegroundColor: MxColors.stone,
              ),
              child: opening
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Continue on WhatsApp'),
            ),
          ),
          if (!enabled && !opening && hint != null) ...[
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

class _HandoffNote extends StatelessWidget {
  const _HandoffNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline_rounded, size: 15, color: MxColors.stone),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'MYCOSIX never sends WhatsApp messages from this website. Your '
            'order is prepared here and you send it yourself.',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
        ),
      ],
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

class _SuccessPanel extends StatelessWidget {
  const _SuccessPanel({required this.order});

  final CustomerOrder order;

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
            Text('Your order is ready in WhatsApp', style: MxType.h2(width)),
            const SizedBox(height: 10),
            Text(
              'Order ${order.orderId} · ${formatRupees(order.total)}',
              style: MxType.h4(color: MxColors.ok),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Text(
                'We opened WhatsApp with your full order — items, location pin '
                'and delivery details. Press Send there to place it, and we will '
                'confirm on WhatsApp. Your cart is kept as a copy in case you '
                'need to send it again.',
                textAlign: TextAlign.center,
                style: MxType.bodySm(color: MxColors.charcoalSoft),
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 17),
                  label: const Text('Continue shopping'),
                ),
                TextButton.icon(
                  onPressed: () => Navigator.of(context).pushNamed(Routes.cart),
                  icon: const Icon(Icons.shopping_bag_outlined, size: 17),
                  label: const Text('View cart'),
                ),
              ],
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

/// Simple WhatsApp glyph so the button reads clearly without an icon package.
class _WhatsAppIcon extends StatelessWidget {
  const _WhatsAppIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: const BoxDecoration(
        color: Color(0xFF128C4A),
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.chat_bubble_rounded,
        size: 18,
        color: Colors.white,
      ),
    );
  }
}
