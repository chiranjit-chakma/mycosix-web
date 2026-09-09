import 'package:flutter/widgets.dart';

/// The app's single [Navigator], created in [MxRoot].
///
/// Some triggers are context-free (an order-alert snackbar action, the admin
/// entry) and navigate through this key instead of a widget's local
/// `Navigator.of(context)`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
