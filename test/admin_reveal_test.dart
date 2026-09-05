import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/pages/admin/admin_access_lock.dart';
import 'package:mycosix/state/admin_reveal.dart';

/// The covert shop-search summoner.
///
/// These tests drive the exact matching path the Shop search box uses
/// (`AdminReveal.armFromSearchText`). They never spell the phrase out — it is
/// reconstructed from the code-point list, mirroring how the app compares it.
void main() {
  final reveal = AdminReveal.shared;
  final secret = String.fromCharCodes(AdminAccessLock.secretCodePoints);

  setUp(reveal.resetForTest);

  test('starts fully hidden', () {
    expect(reveal.stage, AdminRevealStage.hidden);
    expect(reveal.revealed, isFalse);
  });

  test('the exact phrase typed in the search reveals the sign-in stage', () {
    expect(reveal.armFromSearchText(secret), isTrue);
    expect(reveal.stage, AdminRevealStage.signIn);
    expect(reveal.revealed, isTrue);
  });

  test('surrounding whitespace around the phrase is accepted', () {
    expect(reveal.armFromSearchText('  $secret  '), isTrue);
    expect(reveal.stage, AdminRevealStage.signIn);
  });

  test('a partial phrase is an ordinary search and never reveals', () {
    final codes = AdminAccessLock.secretCodePoints;
    final partial =
        String.fromCharCodes(codes.sublist(0, codes.length - 1));
    expect(reveal.armFromSearchText(partial), isFalse);
    expect(reveal.stage, AdminRevealStage.hidden);
  });

  test('a wrong phrase (one character off) does not reveal', () {
    final wrong = String.fromCharCodes(
      AdminAccessLock.secretCodePoints.map((c) => c + 1),
    );
    expect(wrong.length, secret.length);
    expect(reveal.armFromSearchText(wrong), isFalse);
    expect(reveal.stage, AdminRevealStage.hidden);
  });

  test('the phrase with an extra trailing character does not reveal', () {
    expect(reveal.armFromSearchText('$secret-x'), isFalse);
    expect(reveal.stage, AdminRevealStage.hidden);
  });

  test('ordinary product searches never reveal', () {
    for (final q in ['dried', '250 g', 'oyster', 'fresh', 'powder']) {
      expect(reveal.armFromSearchText(q), isFalse);
    }
    expect(reveal.stage, AdminRevealStage.hidden);
  });

  test('a reveal is sticky: reset() returns to hidden', () {
    reveal.armFromSearchText(secret);
    expect(reveal.stage, AdminRevealStage.signIn);
    reveal.resetForTest();
    expect(reveal.stage, AdminRevealStage.hidden);
  });
}
