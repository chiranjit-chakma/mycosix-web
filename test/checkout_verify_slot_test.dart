import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/pages/checkout/checkout_verify_slot.dart';
import 'package:mycosix/services/whatsapp_otp.dart';
import 'package:mycosix/widgets/whatsapp_verify_panel.dart';

/// The checkout's WhatsApp-verification slot, driven through a fake gateway
/// (the real one talks to Firebase Phone Auth - impossible in tests).
/// Covers: the slot stays empty without a complete number, opens the full
/// panel for an unproven number (send-OTP option + code entry), shows the
/// green verified row once proven, leaves a compact 'Send OTP' offer after a
/// close, and re-opening that offer really sends (the auto-request path).
class FakeOtpGateway extends WhatsAppOtpService {
  int sendCalls = 0;
  int verifyCalls = 0;

  @override
  Future<OtpRequest> requestCode(String canonicalPhone) async {
    sendCalls += 1;
    return const OtpRequest.ready('vid-1');
  }

  @override
  Future<OtpVerification> verifyCode({
    required String verificationId,
    required String code,
    required String canonicalPhone,
  }) async {
    verifyCalls += 1;
    return const OtpVerification.ok(freshSession: false);
  }
}

void main() {
  const canonical = '+919876543210';

  Future<FakeOtpGateway> pumpSlot(
    WidgetTester tester, {
    String? phone = canonical,
    bool proven = false,
    bool showPanel = false,
    bool autoRequestCode = false,
    FakeOtpGateway? gateway,
    void Function({required bool freshSession})? onVerified,
    VoidCallback? onOpenPanel,
    VoidCallback? onDismiss,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final gw = gateway ?? FakeOtpGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CheckoutVerifySlot(
                canonicalPhone: phone,
                proven: proven,
                showPanel: showPanel,
                autoRequestCode: autoRequestCode,
                service: gw,
                onVerified: onVerified ?? ({required bool freshSession}) {},
                onOpenPanel: onOpenPanel ?? () {},
                onDismiss: onDismiss ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return gw;
  }

  testWidgets('renders nothing while the field holds no complete number', (
    tester,
  ) async {
    await pumpSlot(tester, phone: null, proven: false, showPanel: true);
    expect(find.byType(WhatsAppVerifyPanel), findsNothing);
    expect(find.byKey(const Key('whatsapp-otp-offer')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('verified-+919876543210')),
      findsNothing,
    );
  });

  testWidgets('an unproven valid number opens the full panel with its send step',
      (tester) async {
    await pumpSlot(tester, proven: false, showPanel: true);
    expect(find.byType(WhatsAppVerifyPanel), findsOneWidget);
    expect(find.byKey(const Key('whatsapp-otp-offer')), findsNothing);
    // The intro's only action is sending the code - the option is visible
    // next to the number, not hidden behind the place-order button.
    expect(find.text('Send verification code'), findsOneWidget);
    expect(find.byKey(const Key('whatsapp-otp-send')), findsOneWidget);
  });

  testWidgets('a proven number replaces the panel with the green verified row',
      (tester) async {
    await pumpSlot(tester, proven: true, showPanel: true);
    expect(
      find.byKey(const ValueKey<String>('verified-+919876543210')),
      findsOneWidget,
    );
    expect(find.byType(WhatsAppVerifyPanel), findsNothing);
    expect(find.byKey(const Key('whatsapp-otp-offer')), findsNothing);
    expect(find.textContaining('no code needed'), findsOneWidget);
  });

  testWidgets('closing the panel leaves the compact send-otp offer behind', (
    tester,
  ) async {
    var dismissed = 0;
    await pumpSlot(tester, proven: false, showPanel: true, onDismiss: () {
      dismissed += 1;
    });
    await tester.tap(find.byTooltip('Close verification'));
    await tester.pump();
    expect(dismissed, 1);
    // The page would now rebuild with showPanel: false; the slot shows the
    // offer card with an explicit 'Send OTP' action.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CheckoutVerifySlot(
                canonicalPhone: canonical,
                proven: false,
                showPanel: false,
                autoRequestCode: false,
                service: FakeOtpGateway(),
                onVerified: ({required bool freshSession}) {},
                onOpenPanel: () {},
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(WhatsAppVerifyPanel), findsNothing);
    expect(find.byKey(const Key('whatsapp-otp-offer')), findsOneWidget);
    expect(find.text('Send OTP'), findsOneWidget);
  });

  testWidgets('the offer asks the page to re-open the panel on tap', (
    tester,
  ) async {
    var opened = 0;
    await pumpSlot(tester, proven: false, showPanel: false, onOpenPanel: () {
      opened += 1;
    });
    await tester.tap(find.byKey(const Key('whatsapp-otp-offer-open')));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets(
      'offer -> reopen with auto-request really sends, then code -> verify',
      (tester) async {
    var verified = 0;
    final gw = await pumpSlot(
      tester,
      proven: false,
      showPanel: false,
      onVerified: ({required bool freshSession}) => verified += 1,
    );
    expect(gw.sendCalls, 0);
    // The offer's 'Send OTP' re-opens the panel with autoRequestCode set:
    // the code request goes out without a second tap.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: CheckoutVerifySlot(
                canonicalPhone: canonical,
                proven: false,
                showPanel: true,
                autoRequestCode: true,
                service: gw,
                onVerified: ({required bool freshSession}) => verified += 1,
                onOpenPanel: () {},
                onDismiss: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(); // mount frame
    await tester.pump(); // post-frame auto-send runs
    await tester.pump(); // async send resolves
    expect(gw.sendCalls, 1);
    expect(find.byKey(const Key('whatsapp-otp-code')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('whatsapp-otp-code')),
      '123456',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('whatsapp-otp-verify')));
    await tester.pump(); // verifying frame
    await tester.pump(); // async verify resolves
    expect(gw.verifyCalls, 1);
    expect(verified, 1);
  });
}
