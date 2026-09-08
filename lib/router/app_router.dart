import 'package:flutter/material.dart';

import '../pages/cart/cart_page.dart';
import '../pages/checkout/checkout_page.dart';
import '../pages/contact/contact_page.dart';
import '../pages/farm/farm_page.dart';
import '../pages/admin/admin_gate.dart';
import '../pages/home/home_page.dart';
import '../pages/journey/journey_page.dart';
import '../pages/legal/privacy_page.dart';
import '../pages/pwa/pwa_root.dart';
import '../pages/legal/terms_page.dart';
import '../pages/product/product_page.dart';
import '../pages/profile/my_orders_page.dart';
import '../pages/profile/profile_page.dart';
import '../pages/profile/wishlist_page.dart';
import '../pages/shop/shop_page.dart';
import '../pages/team/team_page.dart';
import '../services/display_mode.dart';
import 'routes.dart';

/// Route table + transitions.
class AppRouter {
  AppRouter._();

  static Route<dynamic> generateRoute(RouteSettings settings) {
    final name = settings.name ?? Routes.home;

    // Shared page transition — subtle fade + slide up.
    Route<T> fadeRoute<T>(Widget page) {
      return PageRouteBuilder<T>(
        settings: settings,
        transitionDuration: const Duration(milliseconds: 380),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        pageBuilder: (context, animation, secondary) => page,
        transitionsBuilder: (context, animation, secondary, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.015),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      );
    }

    // Installed *phone-size* PWA: the five primary sections live in a
    // paging shell with the carousel dock, so a primary route becomes the
    // shell at that section instead of a full page. A desktop installed PWA
    // is a wide window, so it stays on the ordinary website pages — same UI
    // as the desktop browser, no app-style bottom bar. Profile reached WITH
    // arguments is a real page (the wishlist-heart return flow), not a
    // pager section, and keeps its ordinary route. A browser tab never
    // takes this branch.
    if (isStandaloneMobile()) {
      final idx = primarySectionIndex(name);
      if (idx >= 0 && !(name == Routes.profile && settings.arguments != null)) {
        return fadeRoute(MxPwaRoot(initialIndex: idx));
      }
    }

    switch (name) {
      case Routes.home:
        return fadeRoute(const HomePage());
      case Routes.shop:
        return fadeRoute(const ShopPage());
      case Routes.farm:
        return fadeRoute(const FarmPage());
      case Routes.journey:
        return fadeRoute(const JourneyPage());
      case Routes.team:
        return fadeRoute(const TeamPage());
      case Routes.contact:
        return fadeRoute(const ContactPage());
      case Routes.privacy:
        return fadeRoute(const PrivacyPage());
      case Routes.terms:
        return fadeRoute(const TermsPage());
      case Routes.cart:
        return fadeRoute(const CartPage());
      case Routes.checkout:
        return fadeRoute(const CheckoutPage());
      case Routes.product:
        final id = settings.arguments as String? ?? '';
        return fadeRoute(ProductPage(productId: id));
      case Routes.profile:
        // [arguments] is either a bare returnRoute (String) or a
        // [ProfileRouteRequest] (returnRoute + which tab to open). Both come
        // only from our own pages — never from a raw URL.
        final arg = settings.arguments;
        final request = arg is ProfileRouteRequest
            ? arg
            : ProfileRouteRequest(returnRoute: arg as String?);
        return fadeRoute(
          ProfilePage(
            returnRoute: request.returnRoute,
            initialMode: request.startMode,
          ),
        );
      case Routes.wishlist:
        return fadeRoute(const WishlistPage());
      case Routes.myOrders:
        return fadeRoute(const MyOrdersPage());
      case Routes.admin:
        return fadeRoute(const AdminGate());
      default:
        // A shared real-path product URL (/product/<id>) arrives with the whole
        // path as the route name and no arguments, so it would fall through to
        // home. Recover the id here so deep links open the product page.
        final path = (settings.name ?? '').trim();
        if (path.startsWith('${Routes.product}/')) {
          final id = path.substring('${Routes.product}/'.length);
          return fadeRoute(ProductPage(productId: id));
        }
        return fadeRoute(const HomePage());
    }
  }
}
