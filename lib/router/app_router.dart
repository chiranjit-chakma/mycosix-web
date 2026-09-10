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
import 'initial_routes.dart';
import 'routes.dart';

/// Route table + transitions.
class AppRouter {
  AppRouter._();

  /// The page an inner route opens on, as an animated route.
  static Route<dynamic> generateRoute(RouteSettings settings) =>
      _build(settings, laterArrival);

  /// The routes a cold start begins with (see [initialRouteNames]).
  ///
  /// Same stack Navigator would have built on its own, with one difference:
  /// the route the visitor is actually opening is rendered in its very first
  /// frame instead of fading in from fully transparent (see [launchArrival]).
  /// That fade ran on the initial route too, so the splash handed over to a
  /// beat of blank cream before the page arrived — the flash on open. Anything
  /// stacked underneath keeps the ordinary transition.
  static List<Route<dynamic>> generateInitialRoutes(String initialRouteName) {
    final names = initialRouteNames(initialRouteName);
    return <Route<dynamic>>[
      for (var i = 0; i < names.length; i++)
        _build(
          RouteSettings(name: names[i]),
          launchArrival(i, names.length),
        ),
    ];
  }

  static Route<dynamic> _build(RouteSettings settings, RouteArrival arrival) {
    final page = _pageFor(settings);
    return PageRouteBuilder<dynamic>(
      settings: settings,
      transitionDuration: arrival.forward,
      reverseTransitionDuration: arrival.reverse,
      pageBuilder: (context, animation, secondary) => page,
      transitionsBuilder: (context, animation, secondary, child) {
        if (!arrival.animated) return child;
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

  /// The page for [settings]: the installed-app shell, a named route, or the
  /// recovery of a shared real-path deep link.
  static Widget _pageFor(RouteSettings settings) {
    final name = settings.name ?? Routes.home;

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
        return MxPwaRoot(initialIndex: idx);
      }
    }

    switch (name) {
      case Routes.home:
        return const HomePage();
      case Routes.shop:
        return const ShopPage();
      case Routes.farm:
        return const FarmPage();
      case Routes.journey:
        return const JourneyPage();
      case Routes.team:
        return const TeamPage();
      case Routes.contact:
        return const ContactPage();
      case Routes.privacy:
        return const PrivacyPage();
      case Routes.terms:
        return const TermsPage();
      case Routes.cart:
        return const CartPage();
      case Routes.checkout:
        return const CheckoutPage();
      case Routes.product:
        final id = settings.arguments as String? ?? '';
        return ProductPage(productId: id);
      case Routes.profile:
        // [arguments] is either a bare returnRoute (String) or a
        // [ProfileRouteRequest] (returnRoute + which tab to open). Both come
        // only from our own pages — never from a raw URL.
        final arg = settings.arguments;
        final request = arg is ProfileRouteRequest
            ? arg
            : ProfileRouteRequest(returnRoute: arg as String?);
        return ProfilePage(
          returnRoute: request.returnRoute,
          initialMode: request.startMode,
        );
      case Routes.wishlist:
        return const WishlistPage();
      case Routes.myOrders:
        // In-app navigation may pass a highlight (the Firestore order doc id)
        // straight through; the page only ever shows the signed-in customer's
        // own orders, so this is a display hint, never authorisation.
        final highlight = settings.arguments as String?;
        return MyOrdersPage(highlightOrderId: highlight);
      case Routes.admin:
        return const AdminGate();
      default:
        // A shared real-path product URL (/product/<id>) arrives with the whole
        // path as the route name and no arguments, so it would fall through to
        // home. Recover the id here so deep links open the product page.
        final path = (settings.name ?? '').trim();
        if (path.startsWith('${Routes.product}/')) {
          final id = path.substring('${Routes.product}/'.length);
          return ProductPage(productId: id);
        }
        // A shared push-deep-link for My Orders (/my-orders/<docId>): the id is
        // passed to the page as a highlight only - the orders list itself stays
        // filtered to the signed-in customer's own orders by the rules, so an
        // id for someone else's order simply never matches.
        final myOrdersPrefix = '${Routes.myOrders}/';
        if (path.startsWith(myOrdersPrefix)) {
          final id = path.substring(myOrdersPrefix.length);
          return MyOrdersPage(highlightOrderId: id);
        }
        return const HomePage();
    }
  }
}
