import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/models/site_settings.dart';
import 'package:mycosix/pages/cart/cart_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/repositories/remote_cart_store.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/cart_sync_controller.dart';
import 'package:mycosix/state/site_config_controller.dart';

/// The saved-items banner on the cart page: it must be MOUNTED (it sits right
/// under the delivery-pause notice), appear only when the signed-in account
/// holds items that differ from this cart, and only ever change the cart when
/// the customer taps Load - "Not now" and a matching account never move
/// anything.
void main() {
  setUpAll(() async {
    await _loadFont('Manrope', 'assets/fonts/Manrope-Variable.ttf');
    await _loadFont('Fraunces', 'assets/fonts/Fraunces-Variable.ttf');
  });

  testWidgets('offers saved items when the account differs - Load combines them',
      (tester) async {
    final ctx = await _seed(accountHolds: {'remote-only': 2}, localQty: 0);
    await _pump(tester, ctx);

    // The offer is visible and names the count.
    expect(find.byKey(const Key('saved-cart-banner')), findsOneWidget);
    expect(find.textContaining('2 items saved'), findsOneWidget);

    // Nothing was pushed by the sign-in read alone.
    expect(ctx.store.pushed, isEmpty);

    // Tapping Load combines the account items into this cart...
    await tester.tap(find.byKey(const Key('saved-cart-load')));
    await tester.pump();
    expect(ctx.cart.totalQuantity, 2);

    // ...and once the cart and the account match, the offer disappears.
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.byKey(const Key('saved-cart-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Not now hides the offer and never touches the cart',
      (tester) async {
    final ctx = await _seed(accountHolds: {'remote-only': 2}, localQty: 0);
    await _pump(tester, ctx);
    expect(find.byKey(const Key('saved-cart-banner')), findsOneWidget);

    await tester.tap(find.byKey(const Key('saved-cart-dismiss')));
    await tester.pump();

    expect(find.byKey(const Key('saved-cart-banner')), findsNothing);
    expect(ctx.cart.isEmpty, isTrue, reason: 'dismissing never adds items');
    expect(ctx.store.pushed, isEmpty, reason: 'dismissing never writes');
    expect(tester.takeException(), isNull);
  });

  testWidgets('no offer when the account cart matches this cart',
      (tester) async {
    final ctx = await _seed(accountHolds: {'remote-only': 2}, localQty: 2);
    await _pump(tester, ctx);
    expect(find.byKey(const Key('saved-cart-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakeAuth extends ChangeNotifier implements CartSyncAuth {
  _FakeAuth(this._uid);

  final String? _uid;

  @override
  String? get uid => _uid;
}

class _FakeStore implements RemoteCartStore {
  _FakeStore(this.cart);

  Map<String, int> cart;
  final List<Map<String, int>> pushed = [];

  @override
  Future<Map<String, int>> fetch(String uid) async => Map.of(cart);

  @override
  Stream<Map<String, int>> watch(String uid) => const Stream.empty();

  @override
  Future<void> push(String uid, Map<String, int> items) async {
    pushed.add(Map.of(items));
    cart = Map.of(items);
  }
}

/// Local cart empty (or holding [localQty] of the first product) while the
/// account holds a different line entirely.
Future<_Ctx> _seed({
  required Map<String, int> accountHolds,
  required int localQty,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final productsRepo = LocalProductRepository();
  final cartRepo = CartRepository(prefs, productsRepo);
  await cartRepo.load();
  final firstId = (await productsRepo.fetchAll()).first.id;

  final local = CartController(cartRepo, siteDeliveryFee: MxConfig.deliveryFee);
  if (localQty > 0) {
    await cartRepo.add(firstId, localQty);
  }

  final remote = <String, int>{
    for (final e in accountHolds.entries)
      e.key == 'remote-only' ? firstId : e.key: e.value,
  };
  final store = _FakeStore(remote);
  final auth = _FakeAuth('u1');
  final sync = CartSyncController(
    repository: cartRepo,
    cart: local,
    auth: auth,
    store: store,
    backendAvailable: true,
  )..start();

  final config = SiteConfigController(initial: const SiteSettings());
  addTearDown(sync.dispose);
  return _Ctx(
    cart: local,
    store: store,
    sync: sync,
    app: MultiProvider(
      providers: [
        ChangeNotifierProvider<CartController>.value(value: local),
        ChangeNotifierProvider<CartSyncController>.value(value: sync),
        ChangeNotifierProvider<SiteConfigController>.value(value: config),
      ],
      child: MaterialApp(debugShowCheckedModeBanner: false, home: const CartPage()),
    ),
  );
}

Future<void> _pump(WidgetTester tester, _Ctx ctx) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ctx.app);
  // Sign-in fetch + banner rebuild.
  await tester.pump(const Duration(milliseconds: 100));
}

class _Ctx {
  _Ctx({
    required this.cart,
    required this.store,
    required this.sync,
    required this.app,
  });

  final CartController cart;
  final _FakeStore store;
  final CartSyncController sync;
  final Widget app;
}

/// Loads the real bundled fonts so text metrics match production.
Future<void> _loadFont(String family, String asset) async {
  final bytes = File(asset).readAsBytesSync();
  final loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
  await loader.load();
}
