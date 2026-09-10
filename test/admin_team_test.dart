import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/utils/admin_team.dart';

/// Removing an administrator: the one guard the Firestore rules cannot express
/// (they cannot count a collection) plus the pairing between a grant and the
/// secret-code row that has to go with it.
void main() {
  group('removalBlockedReason', () {
    test('allows a removal while more than one admin remains', () {
      expect(
        AdminTeam.removalBlockedReason(isSelf: true, adminCount: 2),
        isNull,
      );
      expect(
        AdminTeam.removalBlockedReason(isSelf: false, adminCount: 7),
        isNull,
      );
    });

    test('refuses to let the only admin give up their own access', () {
      final r = AdminTeam.removalBlockedReason(isSelf: true, adminCount: 1);
      expect(r, isNotNull);
      expect(r, contains('only administrator'));
      // Plain English, and it says what to do about it.
      expect(r, contains('Add another administrator first'));
    });

    test('refuses to remove the only admin from someone else either', () {
      final r = AdminTeam.removalBlockedReason(isSelf: false, adminCount: 1);
      expect(r, isNotNull);
      expect(r, contains('only administrator account'));
    });

    test('the refusal explains the consequence, not a rule number', () {
      final r = AdminTeam.removalBlockedReason(isSelf: true, adminCount: 1)!;
      expect(r, contains('nobody able to run the shop'));
      expect(r, isNot(contains('permission')));
      expect(r, isNot(contains('code')));
    });
  });

  group('codeDocIdFor', () {
    test('is the lowercase, trimmed email', () {
      expect(AdminTeam.codeDocIdFor('  Owner@Example.COM '),
          'owner@example.com');
    });

    test('a legacy grant with no email has no code row to cancel', () {
      expect(AdminTeam.codeDocIdFor(null), isNull);
      expect(AdminTeam.codeDocIdFor(''), isNull);
      expect(AdminTeam.codeDocIdFor('   '), isNull);
    });

    test('a field that is not an email is never used as a document id', () {
      expect(AdminTeam.codeDocIdFor('not an email'), isNull);
      expect(AdminTeam.codeDocIdFor('a@b'), isNull);
      expect(AdminTeam.codeDocIdFor('/'), isNull);
    });
  });
}
