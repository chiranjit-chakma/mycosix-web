import 'package:flutter/material.dart';

import '../pages/cart/cart_page.dart';
import '../pages/checkout/checkout_page.dart';
import '../pages/contact/contact_page.dart';
import '../pages/farm/farm_page.dart';
import '../pages/admin/admin_gate.dart';
import '../pages/home/home_page.dart';
import '../pages/journey/journey_page.dart';
import '../pages/legal/privacy_page.dart';
import '../pages/legal/terms_page.dart';
import '../pages/product/product_page.dart';
import '../pages/shop/shop_page.dart';
import '../pages/team/team_page.dart';
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
      case Routes.admin:
        return fadeRoute(const AdminGate());
      default:
        return fadeRoute(const HomePage());
    }
  }
}
