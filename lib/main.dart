import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/mx_theme.dart';
import 'firebase/fb.dart';
import 'firebase/fb_admin.dart';
import 'firebase/firebase_options.dart';
import 'repositories/cart_repository.dart';
import 'repositories/config_repository.dart';
import 'repositories/firestore_config_repository.dart';
import 'repositories/firestore_order_repository.dart';
import 'repositories/firestore_product_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/product_repository.dart';
import 'router/app_navigator.dart';
import 'router/app_router.dart';
import 'router/routes.dart';
import 'state/admin_reveal.dart';
import 'state/order_alert_controller.dart';
import 'state/auth_controller.dart';
import 'state/cart_sync_controller.dart';
import 'state/customer_auth_controller.dart';
import 'services/browser_geo_location_service.dart';
import 'services/whatsapp_order_service.dart';
import 'services/whatsapp_otp.dart';
import 'state/cart_controller.dart';
import 'state/location_controller.dart';
import 'state/saved_location_clear.dart';
import 'state/products_controller.dart';
import 'state/site_config_controller.dart';
import 'state/wishlist_controller.dart';
import 'widgets/order_alert_host.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clean, shareable URLs with real paths (PathUrlStrategy). Deep links like
  // /shop therefore need the host to fall back to index.html — the SPA server
  // in /tool does this for local preview.
  usePathUrlStrategy();

  // Optional Firebase bootstrap. The site must keep working exactly as before
  // when Firebase is unreachable or not configured, so a failure here only
  // disables the backend (Fb.enabled stays false) — it never blocks the UI.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 8));
    Fb.enabled = true;
    // The admin area runs on its own NAMED Firebase app (FbAdmin): the admin
    // sign-in and sign-out therefore live on an auth session that is fully
    // separate from the customer session of the default app. Signing in as
    // admin in one tab can never change or overwrite the customer account
    // of the normal site, and the two never merge. If the second app fails
    // to come up, only the admin area reports itself unavailable.
    try {
      final adminApp = await Firebase.initializeApp(
        name: FbAdmin.appName,
        options: DefaultFirebaseOptions.currentPlatform,
      ).timeout(const Duration(seconds: 8));
      FbAdmin.attach(adminApp);
    } catch (e) {
      debugPrint('MYCOSIX: admin Firebase unavailable ($e).');
    }
  } catch (e) {
    debugPrint('MYCOSIX: Firebase unavailable ($e) — running on local data.');
  }

  // Dependencies are assembled here, at the edge of the app. Repositories are
  // behind interfaces, so a Firebase-backed implementation can replace the
  // local ones without touching any widget or controller.
  final prefs = await SharedPreferences.getInstance();

  final ConfigRepository configRepository;
  final ProductRepository productsRepository;
  final OrderRepository orderRepository;
  if (Fb.enabled) {
    final firestoreConfig = FirestoreConfigRepository();
    await firestoreConfig.load(); // remote overrides; defaults on any failure
    configRepository = firestoreConfig;
    // Firestore first, bundled catalogue only as a genuine-failure fallback.
    productsRepository = ResilientProductRepository(
      FirestoreProductRepository(),
    );
    // Orders only through the trusted createOrder Cloud Function.
    orderRepository = FirestoreOrderRepository();
  } else {
    configRepository = LocalConfigRepository();
    productsRepository = LocalProductRepository();
    orderRepository = LocalOrderRepository();
  }

  final cartRepository = CartRepository(prefs, productsRepository);
  await cartRepository.load(); // restore cart + location from browser storage

  // Customer accounts + cart sync. Both stay fully dormant when the backend
  // is offline: the site behaves exactly as the guest-only site did.
  final customerAuth = CustomerAuthController();

  // Live site configuration and the delivery location controller. Both are
  // app-lifetime singletons created here (not inside the provider tree) so
  // the cart can listen to them: the delivery fee the customer sees reacts
  // live to an admin editing the shop point/tiers and to the customer moving
  // their pin. They are still provided to the tree below.
  final siteConfigController = SiteConfigController(
    initial: configRepository.settings,
  )..start();
  final locationController = LocationController(
    cartRepository,
    BrowserGeoLocationService(),
  );

  final cartController = CartController(
    cartRepository,
    siteDeliveryFee: configRepository.deliveryFee,
    siteConfig: siteConfigController,
    location: locationController,
  );
  final cartSync = CartSyncController(
    repository: cartRepository,
    cart: cartController,
    auth: customerAuth,
    backendAvailable: Fb.enabled,
  )..start();

  // Wishlist: the account's saved products, synced to `wishlists/{uid}`.
  // Dormant for guests (hearts prompt a sign-in) and fully inert when the
  // backend is offline.
  final wishlistController = WishlistController(
    auth: customerAuth,
    backendAvailable: Fb.enabled,
  )..start();

  // Foreground order alerts (app-open): live status nudges for the customer's
  // own orders and a "new order" alert for an authorised administrator. The
  // controller subscribes to Firestore only when its side of Firebase is up
  // and stays inert otherwise (tests / offline builds).
  final orderAlertController = OrderAlertController();

  runApp(
    MxApp(
      cartRepository: cartRepository,
      productsRepository: productsRepository,
      configRepository: configRepository,
      orderRepository: orderRepository,
      customerAuth: customerAuth,
      cartController: cartController,
      cartSync: cartSync,
      wishlistController: wishlistController,
      siteConfigController: siteConfigController,
      locationController: locationController,
      orderAlertController: orderAlertController,
    ),
  );
}

/// Root widget: provides state + services, then renders the router.
class MxApp extends StatelessWidget {
  const MxApp({
    super.key,
    required this.cartRepository,
    required this.productsRepository,
    required this.configRepository,
    required this.orderRepository,
    required this.customerAuth,
    required this.cartController,
    required this.cartSync,
    required this.wishlistController,
    required this.siteConfigController,
    required this.locationController,
    required this.orderAlertController,
  });

  final CartRepository cartRepository;
  final ProductRepository productsRepository;
  final ConfigRepository configRepository;
  final OrderRepository orderRepository;
  final CustomerAuthController customerAuth;
  final CartController cartController;
  final CartSyncController cartSync;
  final WishlistController wishlistController;
  final SiteConfigController siteConfigController;
  final LocationController locationController;
  final OrderAlertController orderAlertController;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProductsController(productsRepository),
        ),
        // App-lifetime singletons created in main() (they cross-reference
        // each other for cart sync), so they are provided by value.
        ChangeNotifierProvider<CartController>.value(value: cartController),
        ChangeNotifierProvider<CustomerAuthController>.value(
          value: customerAuth,
        ),
        ChangeNotifierProvider<CartSyncController>.value(value: cartSync),
        ChangeNotifierProvider<WishlistController>.value(
          value: wishlistController,
        ),
        ChangeNotifierProvider<LocationController>.value(
          value: locationController,
        ),
        // Same controller under the narrow sign-out contract, so the profile
        // page can clear the saved delivery point without importing web-only
        // services (widget tests compile on the VM test runner).
        ProxyProvider<LocationController, SavedLocationClear>(
          update: (_, controller, _) => controller,
        ),
        Provider<ConfigRepository>(create: (_) => configRepository),
        // Live site configuration: subscribes to siteConfig/public so an admin
        // toggling "Delivery enabled" off stops customer ordering immediately,
        // with no reload. Started at boot (in main) so the value is warm.
        ChangeNotifierProvider<SiteConfigController>.value(
          value: siteConfigController,
        ),
        Provider<OrderRepository>(create: (_) => orderRepository),
        // One-time-code WhatsApp verification for checkout (Firebase Phone
        // Auth). A plain value service: no state of its own.
        Provider<WhatsAppOtpService>(create: (_) => const WhatsAppOtpService()),
        Provider<WhatsAppOrderService>(
          create: (context) {
            final config = context.read<ConfigRepository>();
            return WhatsAppOrderService(whatsappNumber: config.whatsappNumber);
          },
        ),
        // Admin auth + authorisation (drives the /admin gate).
        ChangeNotifierProvider(create: (_) => AuthController()),
        // Foreground order alerts host reads this; inert when Firebase is off.
        ChangeNotifierProvider<OrderAlertController>.value(
          value: orderAlertController,
        ),
      ],
      child: const MxRoot(),
    );
  }
}

class MxRoot extends StatefulWidget {
  const MxRoot({super.key});

  @override
  State<MxRoot> createState() => _MxRootState();
}

class _MxRootState extends State<MxRoot> {
  @override
  void initState() {
    super.initState();
    AdminReveal.shared.goToAdmin = () =>
        appNavigatorKey.currentState?.pushNamed(Routes.admin);
  }

  @override
  void dispose() {
    AdminReveal.shared.goToAdmin = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MYCOSIX MUSHROOMS — Grown Different',
      debugShowCheckedModeBanner: false,
      theme: MxTheme.light,
      initialRoute: Routes.home,
      // Foreground order alerts ride on MaterialApp.builder: they sit above
      // the Navigator (every route, browser + installed app) yet the banner
      // itself is a normal SnackBar shown through the app's own messenger, so
      // it never overlaps an app bar or the PWA dock.
      builder: (context, child) =>
          OrderAlertHost(child: child ?? const SizedBox.shrink()),
      navigatorKey: appNavigatorKey,
      navigatorObservers: <NavigatorObserver>[AdminReveal.shared.routeObserver],
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
