import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/widgets/sign_out_confirm.dart';

/// Locks the sign-out guard: the confirmation dialog appears before a
/// customer can log out, Cancel keeps the session, and only an explicit
/// "Log out" returns true (which is what signs the customer out).
void main() {
  Future<void> pumpDialog(WidgetTester tester, ValueChanged<bool> onDone) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: TextButton(
                onPressed: () async {
                  final ok = await showSignOutConfirm(context);
                  if (ok) onDone(ok);
                },
                child: const Text('GO'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('cancel keeps the session', (tester) async {
    var signedOut = false;
    await pumpDialog(tester, (_) => signedOut = true);

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    expect(find.text('Log out?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsNothing);
    expect(signedOut, isFalse);
  });

  testWidgets('confirming signs the customer out', (tester) async {
    var signedOut = false;
    await pumpDialog(tester, (_) => signedOut = true);

    await tester.tap(find.text('GO'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();

    expect(find.text('Log out?'), findsNothing);
    expect(signedOut, isTrue);
  });
}
