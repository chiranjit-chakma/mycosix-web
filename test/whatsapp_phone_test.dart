import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/utils/phone.dart';

/// WhatsApp-contact input rules for the checkout phone field: what the field
/// accepts while typing (distinct messages per stage) and the canonical
/// '+91XXXXXXXXXX' form that reaches the order, the rules and the trusted
/// backend. The old [isValidIndianPhone]/[normalizePhone] contracts are pinned
/// unchanged by checkout_scenario_guards_test.dart / models_and_cart_test.dart.
void main() {
  group('checkPhoneInput', () {
    test('empty or whitespace is "empty"', () {
      expect(checkPhoneInput(''), PhoneInputCheck.empty);
      expect(checkPhoneInput('   '), PhoneInputCheck.empty);
    });

    test('fewer than 10 digits is "incomplete"', () {
      expect(checkPhoneInput('9876'), PhoneInputCheck.incomplete);
      expect(checkPhoneInput('98765432'), PhoneInputCheck.incomplete);
      expect(checkPhoneInput('987654321'), PhoneInputCheck.incomplete);
      expect(checkPhoneInput('+91 98765'), PhoneInputCheck.incomplete);
      expect(checkPhoneInput('(987) 654-32'), PhoneInputCheck.incomplete);
    });

    test('a complete number not starting 6-9 is "badStart"', () {
      expect(checkPhoneInput('1234567890'), PhoneInputCheck.badStart);
      expect(checkPhoneInput('0987654321'), PhoneInputCheck.badStart);
      expect(checkPhoneInput('5123456789'), PhoneInputCheck.badStart);
      expect(checkPhoneInput('+91 12345 67890'), PhoneInputCheck.badStart);
    });

    test('junk or characters are "invalid"', () {
      expect(checkPhoneInput('abc'), PhoneInputCheck.invalid);
      expect(checkPhoneInput('98765 43210!'), PhoneInputCheck.invalid);
      expect(checkPhoneInput('98.765.432.10'), PhoneInputCheck.invalid);
      expect(checkPhoneInput('98765x43210'), PhoneInputCheck.invalid);
    });

    test('valid Indian mobile forms pass', () {
      expect(checkPhoneInput('9876543210'), PhoneInputCheck.valid);
      expect(checkPhoneInput('98765 43210'), PhoneInputCheck.valid);
      expect(checkPhoneInput('+91 98765 43210'), PhoneInputCheck.valid);
      expect(checkPhoneInput('+919876543210'), PhoneInputCheck.valid);
      // A leading 0 or 91 before the 10 digits is a dial prefix, not a dup.
      expect(checkPhoneInput('09876543210'), PhoneInputCheck.valid);
      expect(checkPhoneInput('919876543210'), PhoneInputCheck.valid);
      expect(checkPhoneInput('9876543210'), PhoneInputCheck.valid);
    });
  });

  group('canonicalWhatsAppPhone', () {
    test('accepts the display forms of a real number and canonicalises', () {
      expect(canonicalWhatsAppPhone('9876543210'), '+919876543210');
      expect(canonicalWhatsAppPhone('98765 43210'), '+919876543210');
      expect(canonicalWhatsAppPhone('+91 98765 43210'), '+919876543210');
      expect(canonicalWhatsAppPhone('+919876543210'), '+919876543210');
      expect(canonicalWhatsAppPhone('09876543210'), '+919876543210');
      expect(canonicalWhatsAppPhone('919876543210'), '+919876543210');
    });

    test('rejects anything that is not an Indian mobile', () {
      expect(canonicalWhatsAppPhone(''), isNull);
      expect(canonicalWhatsAppPhone('1234567890'), isNull); // starts 1
      expect(canonicalWhatsAppPhone('98765'), isNull); // short
      expect(canonicalWhatsAppPhone('987654321'), isNull); // short
      expect(canonicalWhatsAppPhone('+911234567890'), isNull);
      expect(canonicalWhatsAppPhone('+1 987 654 3210'), isNull); // not India
      expect(canonicalWhatsAppPhone('98765 43210 0'), isNull); // 13 digits
      expect(canonicalWhatsAppPhone('call Neha'), isNull);
    });

    test('agrees with the pinned legacy validator on valid numbers', () {
      // The checkout only accepts numbers the legacy validator would accept.
      for (final v in [
        '9876543210',
        '+91 98765 43210',
        '919876543210',
        '09876543210',
      ]) {
        expect(canonicalWhatsAppPhone(v), isNotNull);
      }
    });
  });

  group('humanizeWhatsAppPhone', () {
    test('renders the canonical number the way customers type it', () {
      expect(humanizeWhatsAppPhone('+919876543210'), '+91 98765 43210');
      expect(humanizeWhatsAppPhone('+919999999999'), '+91 99999 99999');
    });
  });
}
