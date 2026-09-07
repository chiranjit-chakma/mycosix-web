import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/repositories/wishlist_store.dart';
import 'package:mycosix/router/routes.dart';
import 'package:mycosix/state/cart_sync_controller.dart';
import 'package:mycosix/state/wishlist_controller.dart';
import 'package:mycosix/widgets/wishlist_heart.dart';
import 'package:provider/provider.dart';

class _FakeAuth extends ChangeNotifier implements CartSyncAuth {
  String? _uid;

  @override
  String? get uid => _uid;

  set uid(String? value) {
    _uid = value;
    notifyListeners();
  }
}

class _FakeStore implements WishlistStore {
  final _snapshots = StreamController<List<String>>.broadcast();

  @override
  Future<List<String>> fetch(String uid) async => [];

  @override
  Stream<List<String>> watch(String uid) => _snapshots.stream;

  @override
  Future<void> write(String uid, List<String> items) async {}
}

/// The Gen-Z heart: guests get the sign-in gate, signed-in taps save
/// instantly (with the elastic pop + one-shot burst), and another tap removes
/// the product again.
void main() {
  group('WishlistHeartButton', () {
    Widget pump(WidgetTester tester, WishlistController controller) {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider<WishlistController>.value(value: controller),
        ],
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(child: WishlistHeartButton(productId: 'p1')),
          ),
          // The sign-in gate pushes /profile; a placeholder keeps the test
          // from needing the full profile page.
          routes: {
            Routes.profile: (_) =>
                const Scaffold(body: SizedBox.expand()),
          },
        ),
      );
    }

    testWidgets('guest tap opens the sign-in gate', (tester) async {
      final controller = WishlistController(backendAvailable: true);
      addTearDown(controller.dispose);

      await tester.pumpWidget(pump(tester, controller));
      expect(controller.gate, WishlistGate.needsSignIn);

      await tester.tap(find.byType(WishlistHeartButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('Save products to your Wishlist'), findsOneWidget);
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Create account'), findsOneWidget);
      expect(controller.isFavorite('p1'), isFalse);
    });

    testWidgets('signed-in tap saves with the pop + burst, tap again removes',
        (tester) async {
      final controller = WishlistController(
        auth: _FakeAuth()..uid = 'u1',
        store: _FakeStore(),
        backendAvailable: true,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(pump(tester, controller));
      expect(controller.gate, WishlistGate.toggled);

      // Not saved yet.
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);

      await tester.tap(find.byType(WishlistHeartButton));
      await tester.pump(); // rebuild on the controller notification
      await tester.pump(const Duration(milliseconds: 400)); // icon pop done

      expect(controller.isFavorite('p1'), isTrue);
      expect(find.byIcon(Icons.favorite_rounded), findsOneWidget);
      expect(find.byIcon(Icons.favorite_border_rounded), findsNothing);
      // The one-shot burst fired (its first instance is keyed 1).
      expect(find.byKey(const ValueKey<int>(1)), findsOneWidget);

      // Let the burst finish and the 250 ms push-debounce drain.
      await tester.pump(const Duration(milliseconds: 800));

      // Tap again to unsave.
      await tester.tap(find.byType(WishlistHeartButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(controller.isFavorite('p1'), isFalse);
      expect(find.byIcon(Icons.favorite_border_rounded), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
    });
  });
}
