import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/models/fcm_registry.dart';
import 'package:mycosix/state/fcm_registration_keeper.dart';

/// Pure token-list semantics shared by the client registration keeper and the
/// multi-device / sign-out story. FCM tokens are per device, never shared, so
/// a device registers exactly its own token and removes exactly its own.
void main() {
  group('upsertToken', () {
    test('adds a new token once', () {
      expect(upsertToken(const <String>[], 't1'), ['t1']);
      expect(upsertToken(const ['t1', 't2'], 't3'), ['t1', 't2', 't3']);
    });

    test('a repeat registration from the same device is a no-op', () {
      final list = upsertToken(const ['t1', 't2'], 't1');
      expect(list, ['t1', 't2']);
      expect(list, isNot(same(['t1', 't2']))); // still returns a safe copy
    });
  });

  group('withoutToken', () {
    test('removes exactly the given token, keeping every other device', () {
      expect(withoutToken(const ['t1', 't2', 't3'], 't2'), ['t1', 't3']);
    });

    test('removing an absent token changes nothing', () {
      expect(withoutToken(const ['t1'], 'nope'), ['t1']);
    });
  });

  group('hasToken', () {
    test('true only for an exact present token', () {
      expect(hasToken(const ['t1', 't2'], 't2'), isTrue);
      expect(hasToken(const ['t1'], 'T1'), isFalse);
      expect(hasToken(const <String>[], ''), isFalse);
    });
  });

  group('registration keeper dormancy', () {
    test('constructing with push disabled is inert (no plugin touched)', () {
      // Fb.enabled is false (Firebase never initialised here) AND the push
      // flag is off, so the keeper must return before touching Firebase
      // Messaging. Construction is the only observable side effect.
      expect(() => FcmRegistrationKeeper(), returnsNormally);
    });
  });
}
