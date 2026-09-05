import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'config/mx_theme.dart';
import 'firebase/fb.dart';
import 'firebase/firebase_options.dart';
import 'repositories/cart_repository.dart';
import 'repositories/config_repository.dart';
import 'repositories/firestore_config_repository.dart';
import 'repositories/firestore_order_repository.dart';
import 'repositories/firestore_product_repository.dart';
import 'repositories/order_repository.dart';
import 'repositories/product_repository.dart';
import 'router/app_router.dart';
import 'router/routes.dart';
import 'state/auth_controller.dart';
import 'services/geo_location_service.dart';
import 'services/whatsapp_order_service.dart';
import 'state/cart_controller.dart';
import 'state/location_controller.dart';
import 'state/products_controller.dart';

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

  runApp(
    MxApp(
      cartRepository: cartRepository,
      productsRepository: productsRepository,
      configRepository: configRepository,
      orderRepository: orderRepository,
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
  });

  final CartRepository cartRepository;
  final ProductRepository productsRepository;
  final ConfigRepository configRepository;
  final OrderRepository orderRepository;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => ProductsController(productsRepository),
        ),
        ChangeNotifierProvider(create: (_) => CartController(cartRepository)),
        ChangeNotifierProvider(
          create: (_) =>
              LocationController(cartRepository, BrowserGeoLocationService()),
        ),
        Provider<ConfigRepository>(create: (_) => configRepository),
        Provider<OrderRepository>(create: (_) => orderRepository),
        Provider<WhatsAppOrderService>(
          create: (context) {
            final config = context.read<ConfigRepository>();
            return WhatsAppOrderService(
              whatsappNumber: config.whatsappNumber,
              deliveryFee: config.deliveryFee,
            );
          },
        ),
        // Admin auth + authorisation (drives the /admin gate).
        ChangeNotifierProvider(create: (_) => AuthController()),
      ],
      child: const MxRoot(),
    );
  }
}

class MxRoot extends StatelessWidget {
  const MxRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MYCOSIX MUSHROOMS — Grown Different',
      debugShowCheckedModeBanner: false,
      theme: MxTheme.light,
      initialRoute: Routes.home,
      onGenerateRoute: AppRouter.generateRoute,
    );
  }
}
