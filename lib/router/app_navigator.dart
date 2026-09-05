import 'package:flutter/widgets.dart';

/// The app's single [Navigator], created in [MxRoot].
///
/// The covert admin summon is context-free (it can fire from a keyboard phrase
/// typed anywhere on the site), so those triggers navigate through this key
/// instead of a widget's local `Navigator.of(context)`.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
