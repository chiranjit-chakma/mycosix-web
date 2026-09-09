import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../firebase/fb.dart';
import '../firebase/fb_admin.dart';
import '../models/order_notice.dart';
import '../models/order_status.dart';

/// Foreground (app-open) alerts for order events, shown as a small banner on
/// any page while the site is open. Firestore-driven — no FCM, no permission,
/// works on the free plan — and gated by the same server rules as every other
/// read:
///  - the customer watcher subscribes to the signed-in customer's OWN orders
///    (`orders` filtered by `customerId`, which the rules allow only for that
///    customer), so nobody can ever observe someone else's status changes;
///  - the admin watcher runs only when the admin app has a signed-in user
///    whose `admins/{uid}` grant exists — the same server-side check the gate
///    and every admin write use.
///
/// The controller is an app-lifetime singleton created in `main()` (and
/// provided to the widget tree). It stays fully inert when Firebase is
/// unavailable, and unit tests that never initialise Firebase simply never
/// trigger a subscription.
class OrderAlertController extends ChangeNotifier {
  OrderAlertController() {
    if (Fb.enabled) _watchCustomer();
    if (FbAdmin.enabled) _watchAdmin();
  }

  /// Customer watchers.
  StreamSubscription<Object?>? _customerAuthSub;
  StreamSubscription<Object?>? _customerOrdersSub;
  final Map<String, String> _customerStatus = {}; // orderId -> stored label
  bool _customerSeeded = false;

  /// Admin watchers.
  StreamSubscription<Object?>? _adminAuthSub;
  StreamSubscription<Object?>? _adminGrantSub;
  StreamSubscription<Object?>? _adminOrdersSub;
  final Set<String> _adminEverNew = {}; // every New order id seen this session
  bool _adminSeeded = false;

  OrderAlert? _alert;
  Timer? _autoDismiss;

  /// The alert currently on screen, or null when nothing is showing.
  OrderAlert? get alert => _alert;

  /// Dismisses the current alert (and stops its auto-dismiss timer).
  void dismiss() {
    _autoDismiss?.cancel();
    _autoDismiss = null;
    if (_alert == null) return;
    _alert = null;
    notifyListeners();
  }

  /// Puts an alert on screen and auto-dismisses it after a short while.
  /// Latest-wins: a newer event replaces the one showing rather than queueing.
  @visibleForTesting
  void present(OrderAlert alert) {
    _autoDismiss?.cancel();
    _alert = alert;
    _autoDismiss = Timer(const Duration(seconds: 7), dismiss);
    notifyListeners();
  }

  /// Events presented within the dedupe window, keyed by [pushEventKey]. The
  /// same order event arrives through two channels - the Firestore watcher and
  /// (once enabled) the FCM foreground listener - racing each other; the
  /// shared key keeps them to a single banner. The set is cleared on a 10s
  /// roll so it never grows without bound.
  final Set<String> _freshEvents = {};
  DateTime? _freshSince;

  /// Presents [alert] unless [eventKey] was already presented within the last
  /// 10 seconds. Returns true when the alert was shown. Called by both the
  /// Firestore watchers in this file and the FCM foreground listener in
  /// [FcmRegistrationKeeper], which share [pushEventKey].
  bool presentIfFresh(OrderAlert alert, {required String eventKey}) {
    final now = DateTime.now();
    if (_freshSince == null ||
        now.difference(_freshSince!) > const Duration(seconds: 10)) {
      _freshEvents.clear();
      _freshSince = now;
    }
    if (!_freshEvents.add(eventKey)) return false;
    present(alert);
    return true;
  }

  void _watchCustomer() {
    _customerAuthSub = Fb.auth.authStateChanges().listen((user) {
      _teardownCustomer();
      final uid = user?.uid;
      if (uid == null) return;
      _customerOrdersSub = Fb.orders
          .where('customerId', isEqualTo: uid)
          .snapshots()
          .listen(_onCustomerOrders, onError: (_) {});
    });
  }

  void _onCustomerOrders(QuerySnapshot<Map<String, dynamic>> snap) {
    final rows = <OrderStatusRow>[for (final d in snap.docs) _rowFor(d)];
    final alerts = customerAlertsForSnapshot(
      known: _customerStatus,
      rows: rows,
      seeded: _customerSeeded,
    );
    _customerSeeded = true;
    // Key the dedupe on the Firestore doc id + status (the same identity the
    // FCM foreground listener uses), so a status event delivered by both
    // channels never shows as two banners.
    final byCode = {for (final r in rows) r.code: r};
    for (final alert in alerts) {
      final row = byCode[alert.orderId];
      presentIfFresh(
        alert,
        eventKey: pushEventKey(
          kind: 'order-status',
          orderDocId: row?.id ?? '',
          statusLabel: row?.status.label ?? '',
        ),
      );
    }
  }

  /// Builds one [OrderStatusRow] from an orders document: the Firestore doc id
  /// is the stable identity; the human `orderId` field (the code My Orders and
  /// WhatsApp show) is what the customer sees, falling back to the doc id when
  /// a legacy order has no code.
  static OrderStatusRow _rowFor(DocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    final raw = m == null ? null : m['orderId'];
    final code = raw is String && raw.trim().isNotEmpty ? raw.trim() : d.id;
    return (
      id: d.id,
      code: code,
      status: OrderStatus.fromLabel(
        (m == null ? null : m['status'] as String?) ??
            OrderStatus.newOrder.label,
      ),
    );
  }

  void _watchAdmin() {
    _adminAuthSub = FbAdmin.auth.authStateChanges().listen((user) {
      _teardownAdmin();
      final uid = user?.uid;
      if (uid == null) return;
      // Only a user with an admins/{uid} grant is an administrator (rules).
      _adminGrantSub = FbAdmin.admins.doc(uid).snapshots().listen((grant) {
        _teardownAdminOrders();
        if (!grant.exists) return;
        _adminOrdersSub = FbAdmin.orders
            .where('status', isEqualTo: OrderStatus.newOrder.label)
            .snapshots()
            .listen(_onAdminNewOrders, onError: (_) {});
      });
    });
  }

  void _onAdminNewOrders(QuerySnapshot<Map<String, dynamic>> snap) {
    for (final d in snap.docs) {
      if (adminNewOrderWorthy(
        everNew: _adminEverNew,
        id: d.id,
        seeded: _adminSeeded,
      )) {
        final m = d.data(); // snapshots docs always exist: data() is non-null
        final raw = m['orderId'];
        final code = raw is String && raw.trim().isNotEmpty ? raw.trim() : d.id;
        presentIfFresh(
          OrderAlert(
            kind: OrderAlertKind.adminNewOrder,
            orderId: code,
            title: 'New order $code',
            body: 'An order just arrived - review it when you are ready.',
            actionLabel: 'Review',
          ),
          eventKey: pushEventKey(
            kind: 'admin-new-order',
            orderDocId: d.id,
            statusLabel: '',
          ),
        );
      }
    }
    _adminSeeded = true;
  }

  void _teardownCustomer() {
    _customerOrdersSub?.cancel();
    _customerOrdersSub = null;
    _customerStatus.clear();
    _customerSeeded = false;
  }

  void _teardownAdmin() {
    _adminGrantSub?.cancel();
    _adminGrantSub = null;
    _teardownAdminOrders();
  }

  void _teardownAdminOrders() {
    _adminOrdersSub?.cancel();
    _adminOrdersSub = null;
    _adminEverNew.clear();
    _adminSeeded = false;
  }

  @override
  void dispose() {
    dismiss();
    _customerAuthSub?.cancel();
    _adminAuthSub?.cancel();
    _teardownCustomer();
    _teardownAdmin();
    super.dispose();
  }
}
