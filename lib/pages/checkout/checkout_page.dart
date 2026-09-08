import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../firebase/fb.dart';
import '../../models/cart_item.dart';
import '../../models/customer_order.dart';
import '../../models/delivery_location.dart';
import '../../models/order_draft.dart';
import '../../models/product.dart';
import '../../models/store_order.dart';
import '../../repositories/order_repository.dart';
import '../../router/app_nav.dart';
import '../../router/routes.dart';
import '../../services/order_receipt_pdf.dart';
import '../../services/pdf_browser.dart';
import '../../services/url_launcher.dart';
import '../../services/whatsapp_order_service.dart';
import '../../services/whatsapp_otp.dart';
import '../../state/cart_controller.dart';
import '../../state/customer_auth_controller.dart';
import '../../state/location_controller.dart';
import '../../state/site_config_controller.dart';
import '../../utils/money.dart';
import '../../widgets/delivery_paused_notice.dart';
import 'checkout_verify_slot.dart';
import '../../utils/phone.dart';
import '../../utils/validators.dart';
import '../../widgets/location/location_selector.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

/// Shared field validators — the form fields and the place-order button
/// use exactly the same rules so they can never disagree.
String? _validatePhone(String? value) {
  switch (checkPhoneInput(value?.trim() ?? '')) {
    case PhoneInputCheck.empty:
      return 'Please enter your WhatsApp number.';
    case PhoneInputCheck.incomplete:
      return 'That number is incomplete - please enter the full 10-digit '
          'mobile number.';
    case PhoneInputCheck.badStart:
      return 'Indian mobile numbers start with 6, 7, 8 or 9.';
    case PhoneInputCheck.invalid:
      return 'That does not look like an Indian mobile number.';
    case PhoneInputCheck.valid:
      return null;
  }
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

  /// The checkout's own live Firebase auth session, captured in initState so
  /// cleanup can still sign out a throwaway session after the widget leaves
  /// the tree (dispose cannot use context).
  CustomerAuthController? _auth;

  /// Canonical '+91...' number already proven for this checkout - the
  /// signed-in account carries it (Firebase verified it when it was linked),
  /// an admin attested it on the customer profile, or it was verified here
  /// with a one-time code.
  String? _verifiedPhone;

  /// Whether the full verification panel is open. The slot decides what it
  /// renders, and it is ALWAYS visible next to the WhatsApp field whenever
  /// the field holds a valid number - the send-OTP option and the code entry
  /// are never hidden behind the place-order button.
  bool _verifyOpen = false;

  /// Canonical number the customer last closed the verification panel for.
  /// While the field holds this exact number the slot shows the compact
  /// 'Send OTP' offer instead of re-opening the panel on every rebuild.
  String? _dismissedFor;

  /// True right after the customer asked to send a code from the compact
  /// offer: the next fresh panel mount auto-starts the request. Cleared as
  /// soon as the panel is dismissed or reopened from the place-order CTA.
  bool _autoRequest = false;

  /// Canonical phone attested by an admin on this customer's own profile
  /// (customers/{uid}.phone with phoneVerified == true - fields only an
  /// admin may write, enforced by the rules). Loaded once per checkout,
  /// lazily; null until known.
  String? _attestedPhone;
  bool _attestationLoaded = false;

  /// Anchor on the verification slot inside the details form, right under
  /// the WhatsApp field. When the place-order CTA opens the panel, the
  /// checkout glides the slot into view through this key.
  final _verifyAnchor = GlobalKey();

  /// Frozen copy of everything the customer agreed at the moment the CTA
  /// passed validation; placing later always uses this snapshot.
  _FrozenOrder? _pending;
  String? _pendingPhone;

  /// True once a throwaway phone sign-in session was created by the
  /// verification step (guest checkout). The page signs that session back out
  /// once the order is placed - or when the checkout is abandoned.
  bool _sessionFresh = false;

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
    // A signed-in customer's name and email come pre-filled from their own
    // account (both stay editable — they may be ordering for someone else).
    // Phone and delivery details are never stored on the account, so those
    // fields always start empty.
    _auth = context.read<CustomerAuthController>();
    final auth = _auth!;
    if (auth.backendAvailable && auth.user != null) {
      final name = auth.displayName?.trim();
      if (name != null && name.isNotEmpty) _name.text = name;
      final email = auth.email?.trim();
      if (email != null && email.isNotEmpty) _email.text = email;
    }
    // Rebuild whenever a field changes so the place-order CTA reflects
    // live validity (disabled until the order data is complete and valid).
    for (final c in _fieldControllers) {
      c.addListener(_fieldsChanged);
    }
    // Pre-fetch an admin attestation of the signed-in customer's own phone
    // (customers/{uid}) so a proven number renders as verified instead of
    // flashing the OTP panel. Best-effort: a failure just means the
    // customer verifies with a one-time code - the rules never trust this
    // client read, they re-check the attestation server-side at order time.
    if (_auth!.backendAvailable && _auth!.user != null) {
      unawaited(_loadAttestation());
    }
  }

  void _fieldsChanged() {
    if (mounted) setState(() {});
    // The verification slot keys off the canonical number the field holds
    // right now: editing the number simply swaps what the slot shows (a
    // different number is a different proof flow), so no explicit close is
    // needed here.
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
      return 'Add your WhatsApp number to continue';
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
    // A verification session created for a guest checkout that never placed
    // its order: sign it back out so no throwaway account lingers signed in.
    if (_sessionFresh && _placed == null) {
      _signOutFreshSession();
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

  /// The signed-in account uid (null for guests). Stamped on a captured order
  /// so it links to the customer; the trusted backend stamps its own copies
  /// from the auth token server-side, and the security rules pin the field to
  /// exactly the signed-in uid — a guest can never claim someone else's order.
  String? _signedInUid() {
    final auth = context.read<CustomerAuthController>();
    if (!auth.backendAvailable || auth.user == null) return null;
    return auth.uid;
  }

  /// Reads the admin attestation on this customer's own profile once:
  /// `phone` (canonical) is treated as proven only when the document says
  /// `phoneVerified == true`. Anything unreadable or missing falls back to
  /// the one-time-code flow.
  Future<void> _loadAttestation() async {
    if (_attestationLoaded) return;
    final auth = _auth;
    final uid = (auth != null && auth.backendAvailable) ? auth.uid : null;
    if (uid == null) {
      _attestationLoaded = true;
      return;
    }
    try {
      final doc = await Fb.customers
          .doc(uid)
          .get()
          .timeout(const Duration(seconds: 6));
      final d = doc.data();
      final phone = (d != null && d['phoneVerified'] == true)
          ? d['phone'] as Object?
          : null;
      if (phone is String && canonicalWhatsAppPhone(phone) == phone) {
        _attestedPhone = phone;
      }
    } catch (_) {
      // Offline / rules not live yet: fall back to the one-time-code flow.
    } finally {
      _attestationLoaded = true;
      if (mounted) setState(() {});
    }
  }

  /// Whether [canonical] still needs a code: false when it was verified here
  /// with an OTP, is carried by the signed-in account itself (Firebase
  /// verified it when it was linked - every auth token since then carries
  /// the phone_number claim), or was attested by an admin on the profile.
  bool _provenNow(String? canonical) {
    if (canonical == null) return false;
    if (_verifiedPhone == canonical) return true;
    final auth = _auth;
    if (auth != null &&
        auth.backendAvailable &&
        auth.user != null &&
        auth.phoneNumber == canonical) {
      return true;
    }
    return _attestedPhone == canonical;
  }

  Future<bool> _attestationMatches(String canonical) async {
    await _loadAttestation();
    return _attestedPhone == canonical;
  }

  /// Place-order CTA. If the WhatsApp number is already proven for this
  /// session (the signed-in account carries it, or it was verified here
  /// earlier), the order is placed immediately. Otherwise the inline
  /// verification panel opens first - the order is NEVER created before the
  /// number is proven, and everything the customer agreed to is frozen at this
  /// point so the later steps (including a guest sign-in/out) cannot disturb
  /// it.
  Future<void> _placeOrder() async {
    if (_placing) return;

    // Delivery-pause gate (belt and braces behind the disabled button): a live
    // config update can pause delivery between two renders, so an order is
    // refused here too. Nothing is ever written while delivery is paused.
    final config = context.read<SiteConfigController>();
    if (!config.deliveryEnabled) {
      if (!mounted) return;
      setState(() {
        _submitted = true;
        _orderError =
            'Deliveries are paused right now, so orders are off. Please check '
            'back soon.';
      });
      return;
    }

    final cart = context.read<CartController>();
    final loc = context.read<LocationController>().location;
    final canSend =
        !cart.isEmpty &&
        loc != null &&
        loc.confirmed &&
        loc.mapsUrl.trim().isNotEmpty;

    setState(() {
      _submitted = true;
      _orderError = null;
    });

    if (!(_formKey.currentState?.validate() ?? false) || !canSend) return;

    final canonical = canonicalWhatsAppPhone(_phone.text);
    if (canonical == null) return; // the validator above already explains

    // Freeze the order exactly as agreed right now: canonical phone, the
    // cart lines and the amounts shown in the summary. Placing later (after
    // the verification panel) always uses this snapshot, so the recorded
    // order can never disagree with what the customer saw and agreed.
    if (_pendingPhone != canonical || _pending == null) {
      _pending = _FrozenOrder(
        draft: OrderDraft(
          customerName: _name.text.trim(),
          phone: canonical,
          email: _email.text.trim().isEmpty ? null : _email.text.trim(),
          latitude: loc.latitude,
          longitude: loc.longitude,
          mapsUrl: loc.mapsUrl,
          building: _building.text.trim().isEmpty
              ? null
              : _building.text.trim(),
          apartment: _apartment.text.trim().isEmpty
              ? null
              : _apartment.text.trim(),
          landmark: _landmark.text.trim().isEmpty
              ? null
              : _landmark.text.trim(),
          instructions: _instructions.text.trim().isEmpty
              ? null
              : _instructions.text.trim(),
          lines: [
            for (final line in cart.lines)
              OrderDraftLine(
                productId: line.product.id,
                quantity: line.quantity,
              ),
          ],
        ),
        items: List.of(cart.lines),
        subtotal: cart.subtotal,
        deliveryFee: cart.deliveryFee,
        total: cart.total,
      );
      _pendingPhone = canonical;
    }

    // Number proven in this session already? Place the order.
    if (_verifiedPhone == canonical) {
      await _createOrderNow();
      return;
    }
    // The signed-in account itself carries this exact number (Firebase
    // verified it when it was linked, and every auth token since then
    // carries the phone_number claim): no new code is needed.
    final auth = context.read<CustomerAuthController>();
    if (auth.backendAvailable &&
        auth.user != null &&
        auth.phoneNumber == canonical) {
      _verifiedPhone = canonical;
      await _createOrderNow();
      return;
    }
    // An admin attested this exact number on the customer's own profile
    // (customers/{uid}.phoneVerified - written only by an admin, and
    // re-checked by the rules server-side when the order is recorded):
    // no new code is needed either.
    if (await _attestationMatches(canonical)) {
      if (!mounted) return;
      setState(() => _verifiedPhone = canonical);
      await _createOrderNow();
      return;
    }
    // The number still needs proving. The verification slot is already
    // visible right under the WhatsApp field; make sure the full panel is
    // open, then glide it into the middle of the viewport so the customer
    // watches the code request land next to the number it was sent to.
    if (!mounted) return;
    setState(() {
      _verifyOpen = true;
      _dismissedFor = null;
      _autoRequest = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _verifyAnchor.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
        alignment: 0.5,
      );
    });
  }

  /// Records the frozen order: the trusted backend validates and writes it;
  /// if that backend is unreachable, checkout records a captured order (status
  /// 'New', verified false, phone marked verified - marked only after a proof
  /// step: a code Firebase itself verified, an admin attestation, or - while
  /// the owner's temporary-code flag is on - the published temporary code;
  /// the Firestore rules gate that marker server-side regardless, so it is
  /// never a bare client claim) carrying the exact amounts the customer was
  /// shown and agreed at checkout. The confirmation is always shown on
  /// screen - WhatsApp is never opened with the order data itself.
  Future<void> _createOrderNow() async {
    if (_placing) return;
    final run = _pending;
    if (run == null) return;

    // Belt and braces pause re-check: a live config update can pause delivery
    // while the verification panel was open. Nothing is written while paused.
    if (!context.read<SiteConfigController>().deliveryEnabled) {
      if (!mounted) return;
      setState(() {
        _orderError =
            'Deliveries are paused right now, so orders are off. Please check '
            'back soon.';
      });
      return;
    }

    final cart = context.read<CartController>();
    final whatsapp = context.read<WhatsAppOrderService>();
    final orderRepo = context.read<OrderRepository>();

    setState(() {
      _placing = true;
      _orderError = null;
    });

    CustomerOrder order;
    try {
      // Trusted backend: validates the draft and writes the order itself.
      final stored = await orderRepo.createOrder(run.draft);
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
      // capture so the shop still sees the order, then confirm on screen. The
      // capture stores the amounts this customer was shown and agreed at
      // checkout so a delivered order is a real, analysable sale — status
      // stays New and verified stays false (only an admin can change those).
      // phoneVerified is written true ONLY because the number was proven
      // before this point (a code Firebase itself verified on the caller's
      // token, an admin attestation, or - while the owner's temporary-code
      // flag is on - the published temporary code); the security rules gate
      // that marker server-side regardless. No WhatsApp auto-open with the
      // order data — ever.
      final orderId = whatsapp.generateOrderId();
      try {
        await orderRepo.captureNewOrder(
          CapturedOrderData(
            orderId: orderId,
            customerName: run.draft.customerName,
            phone: run.draft.phone,
            phoneVerified: true,
            email: run.draft.email,
            customerId: _signedInUid(),
            latitude: run.draft.latitude,
            longitude: run.draft.longitude,
            mapsUrl: run.draft.mapsUrl,
            building: run.draft.building,
            apartment: run.draft.apartment,
            landmark: run.draft.landmark,
            instructions: run.draft.instructions,
            lines: [
              for (final line in run.items)
                CapturedOrderLine(
                  productId: line.product.id,
                  productName: line.product.name,
                  quantity: line.quantity,
                  unitPrice: line.product.price,
                  lineTotal: line.lineTotal,
                  variant: line.product.variant,
                  weight: line.product.weight,
                ),
            ],
            subtotal: run.subtotal,
            deliveryFee: run.deliveryFee,
            total: run.total,
          ),
        );
      } catch (_) {
        // The capture failed too, so the order was not recorded anywhere
        // server-side. Tell the customer honestly and keep the cart so they
        // can retry. (The verified phone session stays signed in, so a retry
        // needs no new code.)
        if (!mounted) return;
        setState(() {
          _placing = false;
          _orderError =
              'We could not record your order right now. Please check your '
              'connection and try again. Nothing has been charged.';
        });
        return;
      }
      order = _capturedFallbackOrder(run, orderId);
    }

    if (!mounted) return;
    setState(() {
      _placing = false;
      _placed = order;
    });

    // The success panel replaces the form below the fold; glide back to the
    // top so the customer lands straight on "Order confirmed" and the
    // View/Download receipt actions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) MxShell.scrollToTop();
    });

    // The cart has been turned into an order — empty it so the next order
    // starts fresh. The success panel keeps showing because it keys on
    // _placed, not on the cart contents.
    try {
      await cart.clear();
    } catch (_) {
      // Best-effort: a persistence failure must not undo an accepted order.
    }

    // A throwaway phone session proved the number; its job is done.
    _signOutFreshSession();
  }

  /// Best-effort sign-out of a throwaway verification session (guest
  /// checkout, or an account session the guest number replaced). The order is
  /// already recorded at this point, so a failure here only leaves the phone
  /// number signed in - never blocks or retries anything.
  void _signOutFreshSession() {
    if (!_sessionFresh) return;
    _sessionFresh = false;
    final auth = _auth;
    if (auth == null) return;
    unawaited(auth.signOut());
  }

  /// Called by the verification panel once Firebase verified the code for
  /// [canonical]: mark the number proven (a fresh session is signed out again
  /// after the order) and place the frozen order.
  void _onNumberVerified(String canonical, {required bool fresh}) {
    if (!mounted) return;
    setState(() {
      _verifiedPhone = canonical;
      _verifyOpen = false;
      if (fresh) _sessionFresh = true;
    });
    unawaited(_createOrderNow());
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

  /// Receipt copy for a captured order: built from the FROZEN checkout run
  /// with the SAME id that was recorded at checkout, so the on-screen
  /// confirmation and the PDF receipt match the order in the admin list -
  /// even if the cart or fields changed while the number was being verified.
  /// No WhatsApp is opened.
  CustomerOrder _capturedFallbackOrder(_FrozenOrder run, String orderId) {
    return CustomerOrder(
      orderId: orderId,
      customerName: run.draft.customerName,
      phone: run.draft.phone,
      location: DeliveryLocation(
        latitude: run.draft.latitude,
        longitude: run.draft.longitude,
        mapsUrl: run.draft.mapsUrl,
        confirmed: true,
      ),
      items: List.of(run.items), // copy: the cart is cleared after placement
      subtotal: run.subtotal,
      deliveryFee: run.deliveryFee,
      total: run.total,
      email: run.draft.email,
      building: run.draft.building,
      apartment: run.draft.apartment,
      landmark: run.draft.landmark,
      instructions: run.draft.instructions,
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
    final config = context.watch<SiteConfigController>();
    final paused = !config.deliveryEnabled;

    // The canonical number the field currently holds, when it is complete
    // and valid. The verification slot below the field keys off it.
    final phoneCanonical = canonicalWhatsAppPhone(_phone.text);

    // A short line under the CTA. Most states disable the button; the
    // verification hint is the one case where the CTA stays enabled and the
    // hint points at the always-visible OTP slot next to the number.
    final String? ctaHint;
    if (paused) {
      ctaHint =
          'Deliveries are paused right now - orders are off until '
          'MYCOSIX resumes.';
    } else if (!detailsValid) {
      ctaHint = _firstFieldHint();
    } else if (location == null) {
      ctaHint = 'Set and confirm your delivery location on the map';
    } else if (!locationReady) {
      ctaHint = 'Confirm the delivery location pin on the map';
    } else if (phoneCanonical != null && !_provenNow(phoneCanonical)) {
      ctaHint = config.whatsappCodeFallback
          ? 'Verify your number under the field (temporary code 123456 is '
                'on for now) and your order goes through.'
          : 'Send the OTP and enter the 6-digit code next to your number to '
                'place your order.';
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
                const SizedBox(height: 22),
                // The banner appears only when an admin has paused delivery.
                const DeliveryPausedNotice(),
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
                      final auth = _auth;
                      // The live verification slot rides inside the details
                      // form, directly under the WhatsApp number it belongs
                      // to - never off in the right-rail summary, where a
                      // customer could miss it or lose it under a fold. It
                      // is present whenever the field holds a valid number:
                      // the full panel (send-OTP option + code entry), the
                      // compact offer after a close, or the green verified
                      // row once the number is proven.
                      final verifySlot = phoneCanonical == null
                          ? null
                          : CheckoutVerifySlot(
                              canonicalPhone: phoneCanonical,
                              proven: _provenNow(phoneCanonical),
                              showPanel:
                                  _verifyOpen ||
                                  _dismissedFor != phoneCanonical,
                              autoRequestCode: _autoRequest,
                              fallbackAvailable: config.whatsappCodeFallback,
                              service: context.read<WhatsAppOtpService>(),
                              sessionPhone: auth?.phoneNumber,
                              sessionEmail: auth?.email,
                              onVerified: ({required bool freshSession}) =>
                                  _onNumberVerified(
                                    phoneCanonical,
                                    fresh: freshSession,
                                  ),
                              onOpenPanel: () {
                                if (!mounted) return;
                                setState(() {
                                  _verifyOpen = true;
                                  _dismissedFor = null;
                                  _autoRequest = true;
                                });
                              },
                              onDismiss: () {
                                if (!mounted) return;
                                setState(() {
                                  _verifyOpen = false;
                                  _dismissedFor = phoneCanonical;
                                  _autoRequest = false;
                                });
                              },
                            );
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
                        verification: verifySlot,
                        verificationKey: _verifyAnchor,
                      );
                      final aside = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _SummaryCard(),
                          const SizedBox(height: 20),
                          _PlaceOrderCard(
                            enabled: canSend && !paused,
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
    this.verification,
    this.verificationKey,
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

  /// The live WhatsApp-verification panel, present only while a number is
  /// being proved. It renders directly beneath the phone field.
  final Widget? verification;

  /// Key on the verification slot, used by the checkout page to glide the
  /// panel into view the moment it opens.
  final GlobalKey? verificationKey;

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
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9+() -]')),
            ],
            autovalidateMode: AutovalidateMode.onUserInteraction,
            decoration: const InputDecoration(
              labelText: 'WhatsApp Number *',
              hintText: '10-digit mobile number',
              prefixIcon: Icon(Icons.phone_outlined, size: 20),
              suffixIcon: _PhoneInfoButton(),
              helperText:
                  'Please enter a working WhatsApp number. We will use this '
                  'number for important delivery updates and to contact you '
                  'regarding your order.',
            ),
            validator: _validatePhone,
          ),
          // The WhatsApp verification panel (code request, code entry,
          // status) belongs right here, next to the number it verifies.
          if (verification != null) ...[
            const SizedBox(height: 16),
            KeyedSubtree(key: verificationKey, child: verification!),
            const SizedBox(height: 14),
          ],
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

/// Place-order card: records the order (trusted backend, or a captured order
/// carrying the amounts the customer agreed at checkout) and shows the
/// confirmation on screen. The order data itself is never sent over WhatsApp —
/// the confirmation screen and stored record are what confirm the order.
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
          // The hint renders under the CTA whether the button is disabled
          // (missing details / location / paused) or enabled - the OTP hint
          // points at the verification slot while the CTA stays tappable.
          if (!placing && hint != null) ...[
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
                border: Border.all(color: MxColors.ok.withValues(alpha: 0.45)),
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
                  onPressed: _pdfBusy
                      ? null
                      : () => _pdfAction(download: false),
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
                // The one call-to-action the customer is most likely to want:
                // tell MYCOSIX the order is in, so we can reply on WhatsApp
                // with the delivery time.
                FilledButton.icon(
                  onPressed: _whatsappHandoff,
                  style: FilledButton.styleFrom(
                    backgroundColor: MxColors.forest,
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('Notify us on WhatsApp'),
                ),
                TextButton.icon(
                  onPressed: () => AppNav.go(context, Routes.shop),
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
                'your order is confirmed — nothing else. We will reply with '
                'your delivery time.',
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

/// Everything a checkout run agreed to, frozen the moment the CTA passed
/// validation: the draft (canonical '+91' phone, no prices - the backend and
/// rules never trust browser amounts) plus the exact cart lines and summary
/// amounts. Placing later - after the verification panel, possibly across a
/// guest sign-in/out - always uses this snapshot, so the recorded order can
/// never disagree with what the customer saw and agreed at checkout.
class _FrozenOrder {
  const _FrozenOrder({
    required this.draft,
    required this.items,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
  });

  final OrderDraft draft;

  /// Copy of the cart lines (the cart itself is cleared after placement).
  final List<CartItem> items;

  final double subtotal;
  final double deliveryFee;
  final double total;
}

/// The small red "why do we need this?" control beside the WhatsApp field. It
/// opens a tiny popover anchored at the field (never a page navigation, never
/// a modal) explaining why the number is asked for. It closes on tap anywhere
/// else, or with the close button; it is positioned inside the page overlay so
/// it is never clipped by the form.
class _PhoneInfoButton extends StatefulWidget {
  const _PhoneInfoButton();

  @override
  State<_PhoneInfoButton> createState() => _PhoneInfoButtonState();
}

class _PhoneInfoButtonState extends State<_PhoneInfoButton> {
  final _anchor = GlobalKey();
  OverlayEntry? _entry;

  bool get _open => _entry != null;

  @override
  void dispose() {
    _entry?.remove();
    super.dispose();
  }

  void _toggle() {
    if (_open) {
      _close();
    } else {
      _openPopup();
    }
  }

  void _close() {
    _entry?.remove();
    _entry = null;
    if (mounted) setState(() {});
  }

  void _openPopup() {
    final box = _anchor.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return;
    final overlay = Overlay.of(context);
    final origin = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    const side = 12.0;
    const width = 320.0;
    final w = math.min(width, screen.width - side * 2);
    final left = (origin.dx + 8 - w)
        .clamp(side, screen.width - w - side)
        .toDouble();
    const estCardHeight = 180.0;
    final below = origin.dy + box.size.height + 8;
    final top = below + estCardHeight < screen.height - side
        ? below
        : origin.dy - 8 - estCardHeight;

    _entry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          // Full-screen transparent barrier: tapping anywhere dismisses the
          // popover (and never leaks into the page underneath).
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _close,
            ),
          ),
          Positioned(
            key: const Key('phone-why-popover'),
            left: left,
            top: top.clamp(side, screen.height - estCardHeight - side),
            width: w,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MxColors.creamSoft,
                borderRadius: BorderRadius.circular(MxRadius.md),
                border: Border.all(color: MxColors.line),
                boxShadow: [
                  BoxShadow(
                    color: MxColors.forest.withValues(alpha: 0.10),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.info_outline_rounded,
                        size: 16,
                        color: MxColors.danger,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Why do we need this?',
                          style: MxType.bodySm(
                            color: MxColors.charcoal,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ),
                      InkWell(
                        onTap: _close,
                        borderRadius: BorderRadius.circular(999),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: MxColors.stone,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'We confirm your order and send delivery updates over '
                    'WhatsApp, so a quick message to this number is the '
                    'fastest, safest way to reach you. We never share your '
                    'number with anyone else.',
                    style: MxType.bodyXs(color: MxColors.charcoalSoft),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_entry!);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: _anchor,
      onPressed: _toggle,
      tooltip: 'Why do we need this?',
      visualDensity: VisualDensity.compact,
      icon: const Icon(
        Icons.info_outline_rounded,
        size: 19,
        color: MxColors.danger,
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
              onPressed: () => AppNav.go(context, Routes.shop),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Browse the shop'),
            ),
          ],
        ),
      ),
    );
  }
}
