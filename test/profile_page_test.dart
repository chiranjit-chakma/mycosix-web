import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/config/mx_config.dart';
import 'package:mycosix/config/mx_theme.dart';
import 'package:mycosix/pages/profile/profile_page.dart';
import 'package:mycosix/repositories/cart_repository.dart';
import 'package:mycosix/repositories/product_repository.dart';
import 'package:mycosix/state/cart_controller.dart';
import 'package:mycosix/state/customer_auth_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // With no Firebase in the test VM, Fb.enabled is false, so a real
  // CustomerAuthController reports an offline backend — exactly the state a
  // customer sees when Firebase cannot be reached.
  testWidgets('profile page renders the honest offline state', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final productsRepo = LocalProductRepository();
    final cartRepo = CartRepository(prefs, productsRepo);
    await cartRepo.load();
    final auth = CustomerAuthController();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CartController(
              cartRepo,
              siteDeliveryFee: MxConfig.deliveryFee,
            ),
          ),
          ChangeNotifierProvider<CustomerAuthController>.value(value: auth),
        ],
        child: MaterialApp(
          theme: MxTheme.light,
          home: const ProfilePage(),
        ),
      ),
    );
    // Pump a few fixed frames (the shell's entry animations are finite, but
    // pumpAndSettle is avoided per the repo's layout-test convention).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('YOUR ACCOUNT'), findsOneWidget);
    expect(find.textContaining('sign-in service'), findsOneWidget);
    // No fake success states: no forms, no "signed in" copy.
    expect(find.text('Sign in'), findsNothing);
    expect(find.text('Create account'), findsNothing);
  });
}
