import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/pages/admin/admin_access_lock.dart';
import 'package:mycosix/state/admin_reveal.dart';

/// The covert typed-phrase summoner.
///
/// These tests drive the exact matching path the real key handler uses
/// (`debugFeedCharacter` is the same private routine). They never spell the
/// phrase out — it is reconstructed from the code-point list, mirroring how the
/// running app compares it.
void main() {
  final reveal = AdminReveal.shared;
  final secret = String.fromCharCodes(AdminAccessLock.secretCodePoints);

  setUp(reveal.resetForTest);

  test('starts fully hidden', () {
    expect(reveal.stage, AdminRevealStage.hidden);
    expect(reveal.revealed, isFalse);
  });

  test('long-press reveals the door stage', () {
    reveal.armDoor();
    expect(reveal.stage, AdminRevealStage.door);
    expect(reveal.revealed, isTrue);
  });

  test('typing the whole phrase reveals the sign-in stage', () {
    for (final code in AdminAccessLock.secretCodePoints) {
      reveal.debugFeedCharacter(String.fromCharCode(code));
    }
    expect(reveal.stage, AdminRevealStage.signIn);
    expect(reveal.revealed, isTrue);
  });

  test('a partial phrase never reveals', () {
    final codes = AdminAccessLock.secretCodePoints;
    for (var i = 0; i < codes.length - 1; i++) {
      reveal.debugFeedCharacter(String.fromCharCode(codes[i]));
    }
    expect(reveal.stage, AdminRevealStage.hidden);
  });

  test('a wrong phrase (one character off) does not reveal', () {
    // Same length as the phrase but different content.
    final wrong = String.fromCharCodes(
      AdminAccessLock.secretCodePoints.map((c) => c + 1),
    );
    expect(wrong.length, secret.length);
    for (final ch in wrong.split('')) {
      reveal.debugFeedCharacter(ch);
    }
    expect(reveal.stage, AdminRevealStage.hidden);
  });

  test(
    'the phrase is recognised even after other typed text (rolling window)',
    () {
      for (final ch in 'abc 123'.split('')) {
        reveal.debugFeedCharacter(ch);
      }
      for (final code in AdminAccessLock.secretCodePoints) {
        reveal.debugFeedCharacter(String.fromCharCode(code));
      }
      expect(reveal.stage, AdminRevealStage.signIn);
    },
  );

  test('a reveal is sticky: reset() returns to hidden', () {
    for (final code in AdminAccessLock.secretCodePoints) {
      reveal.debugFeedCharacter(String.fromCharCode(code));
    }
    expect(reveal.stage, AdminRevealStage.signIn);
    reveal.resetForTest();
    expect(reveal.stage, AdminRevealStage.hidden);
  });
}
