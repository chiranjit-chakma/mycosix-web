import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/admin_reveal.dart';

/// The visible Admin entry on the account page.
///
/// There is no secret summon phrase any more — [AdminReveal.openAdmin] is the
/// only way to arm the admin sign-in for a signed-out visitor, and the stage
/// never changes from ordinary app text. Security is server-side (the
/// admins/{uid} grant enforced by Firestore rules); this just opens the door.
void main() {
  final reveal = AdminReveal.shared;

  setUp(reveal.resetForTest);

  test('starts fully hidden', () {
    expect(reveal.stage, AdminRevealStage.hidden);
    expect(reveal.revealed, isFalse);
  });

  test('openAdmin arms the sign-in stage', () {
    reveal.openAdmin();
    expect(reveal.stage, AdminRevealStage.signIn);
    expect(reveal.revealed, isTrue);
  });

  test('openAdmin is idempotent while already armed', () {
    reveal.openAdmin();
    reveal.openAdmin();
    expect(reveal.stage, AdminRevealStage.signIn);
  });

  test('a reveal is sticky: reset() returns to hidden', () {
    reveal.openAdmin();
    expect(reveal.stage, AdminRevealStage.signIn);
    reveal.resetForTest();
    expect(reveal.stage, AdminRevealStage.hidden);
  });
}
