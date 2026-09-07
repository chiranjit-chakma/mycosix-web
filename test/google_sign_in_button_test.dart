import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/widgets/google_sign_in_button.dart';

/// The Continue-with-Google button: visible, tappable, and honest about being
/// busy (disabled + spinner while a sign-in is in flight).
void main() {
  testWidgets('shows the label and fires the callback on tap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: GoogleSignInButton(onPressed: () => tapped = true),
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('google-sign-in-button')), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);

    await tester.tap(find.byKey(const Key('google-sign-in-button')));
    await tester.pump();
    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('busy state disables the button and shows a spinner',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: Center(
            child: GoogleSignInButton(
              onPressed: () => tapped = true,
              busy: true,
            ),
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const Key('google-sign-in-button')),
      warnIfMissed: false,
    );
    await tester.pump();
    expect(tapped, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
