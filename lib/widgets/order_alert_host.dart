import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/order_notice.dart';
import '../router/app_navigator.dart';
import '../router/routes.dart';
import '../state/admin_reveal.dart';
import '../state/order_alert_controller.dart';

/// Shows foreground order alerts as a floating snackbar on whatever page the
/// user is on. Mounted through `MaterialApp.builder` so it sits above the
/// Navigator (and therefore every route, in the browser site and the installed
/// app) without changing any page's layout.
///
/// The messenger it drives is the app's own [ScaffoldMessenger], so the alert
/// appears above the current page's bottom bar/dock exactly like a standard
/// notification and never overlaps an app bar or the PWA dock.
///
/// Clicking the action routes the user to a page they are authorised for:
///  - customer status alert -> My Orders (only the customer's own orders are
///    ever queryable there);
///  - admin new-order alert -> the admin area (the gate only lets an
///    authorised administrator through).
class OrderAlertHost extends StatefulWidget {
  const OrderAlertHost({super.key, required this.child});

  final Widget child;

  @override
  State<OrderAlertHost> createState() => _OrderAlertHostState();
}

class _OrderAlertHostState extends State<OrderAlertHost> {
  OrderAlert? _handled;

  @override
  Widget build(BuildContext context) {
    final alerts = context.watch<OrderAlertController>();
    final alert = alerts.alert;
    if (alert != _handled) {
      _handled = alert;
      WidgetsBinding.instance.addPostFrameCallback((_) => _sync(alerts));
    }
    return widget.child;
  }

  void _sync(OrderAlertController alerts) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final a = alerts.alert;
    messenger.removeCurrentSnackBar();
    if (a == null) return;
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        duration: const Duration(seconds: 6),
        content: _OrderAlertRow(alert: a),
        action: SnackBarAction(
          label: a.actionLabel,
          onPressed: () {
            alerts.dismiss();
            _route(a);
          },
        ),
      ),
    );
  }

  static void _route(OrderAlert a) {
    switch (a.kind) {
      case OrderAlertKind.customerStatus:
        appNavigatorKey.currentState?.pushNamed(Routes.myOrders);
      case OrderAlertKind.adminNewOrder:
        // Arms the admin entry and navigates unless /admin is already on top
        // (AdminReveal's guard) — so "Review" never stacks a second admin page.
        AdminReveal.shared.openAdmin();
    }
  }
}

class _OrderAlertRow extends StatelessWidget {
  const _OrderAlertRow({required this.alert});

  final OrderAlert alert;

  @override
  Widget build(BuildContext context) {
    final icon = switch (alert.kind) {
      OrderAlertKind.customerStatus => Icons.verified_rounded,
      OrderAlertKind.adminNewOrder => Icons.notifications_active_outlined,
    };
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                alert.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if (alert.body.isNotEmpty) ...[
                const SizedBox(height: 1),
                Text(alert.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              ],
            ],
          ),
        ),
      ],
    );
  }
}
