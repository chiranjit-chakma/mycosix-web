import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/services/whatsapp_otp.dart';
import 'package:mycosix/widgets/whatsapp_verify_panel.dart';

/// The checkout's inline WhatsApp verification step, driven through a fake
/// gateway (the real one talks to Firebase Phone Auth - impossible in tests).
/// Covers: send -> code -> wrong/expired code handling, attempt cap, resend
/// cooldown, guest-handoff disclosure and the verified callback.
/// A scripted stand-in for [WhatsAppOtpService]: each call pops the next
/// scripted result (the last one repeats), so every failure path can be
/// driven deterministically.
/// A scripted stand-in for [WhatsAppOtpService]: each call pops the next
/// scripted result (the last one repeats), so every failure path can be
/// driven deterministically.
class FakeOtpGateway extends WhatsAppOtpService {
  FakeOtpGateway({
    List<OtpRequest> sends = const [],
    List<OtpVerification> verifies = const [],
  })  : sends = List.of(sends),
        verifies = List.of(verifies);

  final List<OtpRequest> sends;
  final List<OtpVerification> verifies;
  int sendCalls = 0;
  int verifyCalls = 0;
  String? lastCode;

  @override
  Future<OtpRequest> requestCode(String canonicalPhone) async {
    sendCalls += 1;
    if (sends.isEmpty) return const OtpRequest.ready('vid-1');
    final i = (sendCalls - 1).clamp(0, sends.length - 1);
    return sends[i];
  }

  @override
  Future<OtpVerification> verifyCode({
    required String verificationId,
    required String code,
    required String canonicalPhone,
  }) async {
    verifyCalls += 1;
    lastCode = code;
    if (verifies.isEmpty) {
      return const OtpVerification.ok(freshSession: false);
    }
    final i = (verifyCalls - 1).clamp(0, verifies.length - 1);
    return verifies[i];
  }
}

void main() {
  const canonical = '+919876543210';

  Future<FakeOtpGateway> pumpPanel(
    WidgetTester tester, {
    FakeOtpGateway? gateway,
    String? sessionPhone,
    required void Function({required bool freshSession}) onVerified,
    VoidCallback? onCancel,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final gw = gateway ?? FakeOtpGateway();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: WhatsAppVerifyPanel(
              service: gw,
              canonicalPhone: canonical,
              sessionPhone: sessionPhone,
              onVerified: onVerified,
              onCancel: onCancel ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return gw;
  }

  Future<void> sendCode(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('whatsapp-otp-send')));
    await tester.pump(); // spinner frame
    await tester.pump(); // async send resolves
  }

  Future<void> enterCode(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('whatsapp-otp-code')), code);
    await tester.pump();
  }

  FilledButton verifyButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.byKey(const Key('whatsapp-otp-verify')),
      );

  testWidgets('intro shows the send step and drives it through the gateway',
      (tester) async {
    final gw = await pumpPanel(tester, onVerified: ({required bool freshSession}) {});
    expect(find.byKey(const Key('whatsapp-verify-panel')), findsOneWidget);
    // The intro's only action is sending the code; the 'Verify & place order'
    // button appears once a code is in flight.
    expect(find.text('Send verification code'), findsOneWidget);
    expect(find.text('Verify & place order'), findsNothing);

    await sendCode(tester);
    expect(gw.sendCalls, 1);
    expect(find.byKey(const Key('whatsapp-otp-code')), findsOneWidget);
    expect(find.text('Verify & place order'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('happy path: send, type 6 digits, verify succeeds',
      (tester) async {
    late bool called;
    late bool fresh;
    final gw = await pumpPanel(
      tester,
      onVerified: ({required bool freshSession}) {
        called = true;
        fresh = freshSession;
      },
    );
    await sendCode(tester);

    // The verify button stays disabled until a full 6-digit code is entered.
    expect(verifyButton(tester).onPressed, isNull);
    await enterCode(tester, '12345');
    expect(verifyButton(tester).onPressed, isNull);
    await enterCode(tester, '123456');
    expect(verifyButton(tester).onPressed, isNotNull);

    await tester.tap(find.byKey(const Key('whatsapp-otp-verify')));
    await tester.pump();
    await tester.pump();
    expect(called, isTrue);
    expect(fresh, isFalse);
    expect(gw.lastCode, '123456');

    // Leave the tree so the panel's timers are disposed cleanly.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a guest verification reports freshSession true', (tester) async {
    late bool fresh;
    final gw = FakeOtpGateway(
      verifies: const [OtpVerification.ok(freshSession: true)],
    );
    await pumpPanel(
      tester,
      gateway: gw,
      onVerified: ({required bool freshSession}) => fresh = freshSession,
    );
    await sendCode(tester);
    await enterCode(tester, '111111');
    await tester.tap(find.byKey(const Key('whatsapp-otp-verify')));
    await tester.pump();
    await tester.pump();
    expect(fresh, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a wrong code counts down attempts and explains', (tester) async {
    final gw = FakeOtpGateway(
      verifies: const [
        OtpVerification.failed(OtpFailure.wrongCode, 'That code is not right.'),
      ],
    );
    await pumpPanel(tester, gateway: gw, onVerified: ({required bool freshSession}) {});
    await sendCode(tester);
    await enterCode(tester, '000000');
    await tester.tap(find.byKey(const Key('whatsapp-otp-verify')));
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('That code is not right.'), findsOneWidget);
    expect(find.textContaining('4 attempts left'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('too many wrong attempts asks for a new code', (tester) async {
    final gw = FakeOtpGateway(
      verifies: List.filled(
        6,
        const OtpVerification.failed(OtpFailure.wrongCode, 'No.'),
      ),
    );
    await pumpPanel(tester, gateway: gw, onVerified: ({required bool freshSession}) {});
    await sendCode(tester);
    for (var i = 0; i < 5; i += 1) {
      await enterCode(tester, '000000');
      await tester.tap(find.byKey(const Key('whatsapp-otp-verify')));
      await tester.pump();
      await tester.pump();
    }
    expect(
      find.text('Too many wrong attempts. Please request a new code.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an expired code says so and a resend starts a fresh phase',
      (tester) async {
    final gw = FakeOtpGateway(
      verifies: const [
        OtpVerification.failed(
          OtpFailure.expired,
          'That code has expired. Please request a new one.',
        ),
      ],
    );
    await pumpPanel(tester, gateway: gw, onVerified: ({required bool freshSession}) {});
    await sendCode(tester);
    await enterCode(tester, '222222');
    await tester.tap(find.byKey(const Key('whatsapp-otp-verify')));
    await tester.pump();
    await tester.pump();
    expect(
      find.text('That code has expired. Please request a new one.'),
      findsOneWidget,
    );

    // Resend goes through the gateway again and starts a fresh code phase.
    await tester.tap(find.byKey(const Key('whatsapp-otp-resend')));
    await tester.pump();
    await tester.pump();
    expect(gw.sendCalls, 2);
    expect(find.byKey(const Key('whatsapp-otp-code')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the resend button waits out its cooldown', (tester) async {
    await pumpPanel(tester, onVerified: ({required bool freshSession}) {});
    await sendCode(tester);
    await tester.pump();
    final resend = tester.widget<TextButton>(
      find.byKey(const Key('whatsapp-otp-resend')),
    );
    expect(resend.onPressed, isNull);
    expect(find.text('Resend code in 30 s'), findsOneWidget);

    // 30 seconds of fake time -> cooldown ends and the button re-enables.
    await tester.pump(const Duration(seconds: 31));
    expect(find.text('Resend code'), findsOneWidget);
    final resendAfter = tester.widget<TextButton>(
      find.byKey(const Key('whatsapp-otp-resend')),
    );
    expect(resendAfter.onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a send failure shows the reason and stays on the intro',
      (tester) async {
    final gw = FakeOtpGateway(
      sends: const [
        OtpRequest.failed(
          OtpFailure.limited,
          'Too many codes have been sent to this number. Please wait a few '
              'minutes and try again.',
        ),
      ],
    );
    await pumpPanel(tester, gateway: gw, onVerified: ({required bool freshSession}) {});
    await sendCode(tester);
    expect(gw.sendCalls, 1);
    expect(find.textContaining('Too many codes have been sent'), findsOneWidget);
    expect(find.text('Send verification code'), findsOneWidget); // intro again
  });

  testWidgets('explains when a signed-in account carries a different number',
      (tester) async {
    await pumpPanel(
      tester,
      sessionPhone: '+919876543211', // a DIFFERENT verified number
      onVerified: ({required bool freshSession}) {},
    );
    expect(find.textContaining('this order is placed as a guest'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the matching signed-in number shows no hand-off warning',
      (tester) async {
    await pumpPanel(
      tester,
      sessionPhone: canonical,
      onVerified: ({required bool freshSession}) {},
    );
    expect(find.textContaining('placed as a guest'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
