import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/utils/admin_emails.dart';

void main() {
  group('adminEmailKey', () {
    test('trims and lowercases the email', () {
      expect(adminEmailKey('  Owner@Shop.IN  '), 'owner@shop.in');
      expect(adminEmailKey('admin@gmail.com'), 'admin@gmail.com');
    });
  });

  group('isPlausibleAdminEmail', () {
    test('accepts well-formed addresses', () {
      expect(isPlausibleAdminEmail('owner@gmail.com'), isTrue);
      expect(isPlausibleAdminEmail('  a.b+c@example.co.uk  '), isTrue);
    });

    test('rejects malformed text', () {
      expect(isPlausibleAdminEmail(''), isFalse);
      expect(isPlausibleAdminEmail('owner'), isFalse);
      expect(isPlausibleAdminEmail('owner@'), isFalse);
      expect(isPlausibleAdminEmail('a b@x.com'), isFalse);
      expect(isPlausibleAdminEmail('@x.com'), isFalse);
    });
  });

  group('adminCodeError', () {
    test('rejects an empty code', () {
      expect(adminCodeError(''), isNotNull);
      expect(adminCodeError('   '), isNotNull);
    });

    test('rejects an over-long code (a long paste)', () {
      expect(adminCodeError('x' * 65), isNotNull);
    });

    test('accepts codes of a sane length', () {
      expect(adminCodeError('grow-247'), isNull);
      expect(adminCodeError('ok'), isNull);
      expect(adminCodeError('x' * 64), isNull);
    });
  });
}
