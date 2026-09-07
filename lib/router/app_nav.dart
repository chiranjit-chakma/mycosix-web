import 'package:flutter/widgets.dart';

import '../pages/pwa/pwa_registry.dart';

/// Pager-aware navigation.
///
/// In the installed PWA the five primary sections (Home / Shop / Farm /
/// Journey / Profile) live in a horizontal paging shell, not as navigator
/// routes. [go] checks that shell first: if it is live and [route] is one of
/// the five primary sections, it switches the pager to that section (and
/// closes any secondary page stacked above it, like a bottom-tab app) instead
/// of pushing a second paging shell.
///
/// In a normal browser tab — or for any secondary route (cart, checkout,
/// product, team, contact, legal, admin, ...) — this is an ordinary
/// `pushNamed`, byte-for-byte the behavior the browser website has today.
class AppNav {
  AppNav._();

  static bool go(BuildContext context, String route) {
    if (PwaRegistry.switchSection(route)) return true;
    Navigator.of(context).pushNamed(route);
    return false;
  }
}
