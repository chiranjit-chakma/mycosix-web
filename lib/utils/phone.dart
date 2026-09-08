/// Phone number validation for India.
///
/// Accepts: 10-digit, 11-digit with leading 0, 12-digit with +91 or 91,
/// and formats with spaces/dashes.
bool isValidIndianPhone(String raw) {
  final digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('0')) {
    return _isTen(digits.substring(1));
  }
  if (digits.length == 12 && (digits.startsWith('91') || digits.startsWith('+91'))) {
    return _isTen(digits.substring(2));
  }
  return _isTen(digits);
}

bool _isTen(String d) {
  if (d.length != 10) return false;
  // Indian mobile numbers start with 6-9.
  final first = d[0];
  return first == '6' || first == '7' || first == '8' || first == '9';
}

/// Normalizes a phone number to E.164 for WhatsApp (country code, digits only).
String normalizePhone(String raw) {
  var digits = raw.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) return '91$digits';
  if (digits.length == 11 && digits.startsWith('0')) return '91${digits.substring(1)}';
  if (digits.length == 12 && digits.startsWith('91')) return digits;
  return digits;
}

/// Why a WhatsApp field value is not (yet) a valid Indian mobile number.
enum PhoneInputCheck {
  /// Nothing typed yet.
  empty,

  /// Typed something that can be a phone number, but too few digits so far.
  incomplete,

  /// Ten digits but the number does not start with 6-9.
  badStart,

  /// Not shaped like an Indian mobile number at all.
  invalid,

  /// A complete, valid Indian WhatsApp number.
  valid,
}

/// Classifies a phone field value. This is the single shared rule the field
/// and the place-order button lean on (see checkout), so their messages can
/// never disagree about what is acceptable.
PhoneInputCheck checkPhoneInput(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return PhoneInputCheck.empty;
  // Anything that is not digits, '+', spaces, dashes or parentheses is not a
  // phone number at all.
  final junk = t.replaceAll(RegExp(r'[0-9+()\- ]'), '');
  if (junk.isNotEmpty) return PhoneInputCheck.invalid;
  final digits = t.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return PhoneInputCheck.invalid;
  if (digits.length < 10) return PhoneInputCheck.incomplete;
  if (digits.length == 10) {
    return _isTen(digits) ? PhoneInputCheck.valid : PhoneInputCheck.badStart;
  }
  // 11 digits: a leading 0 in front of a 10-digit body ('09876543210').
  if (digits.length == 11 && digits.startsWith('0')) {
    return _isTen(digits.substring(1))
        ? PhoneInputCheck.valid
        : PhoneInputCheck.badStart;
  }
  // 12 digits: the country code 91 in front of a 10-digit body.
  if (digits.length == 12 && digits.startsWith('91')) {
    return _isTen(digits.substring(2))
        ? PhoneInputCheck.valid
        : PhoneInputCheck.badStart;
  }
  return PhoneInputCheck.invalid;
}

/// Converts any accepted Indian input to the canonical stored form
/// '+91XXXXXXXXXX' (E.164 with the leading +), or null when not accepted.
///
/// Firebase Auth tokens carry exactly this string as their `phone_number`
/// claim, so the Firestore rules can pin a recorded order's phone to the
/// verified caller with a plain string equality, and the stored value needs
/// no reformatting anywhere else.
String? canonicalWhatsAppPhone(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return null;
  final digits = t.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 10) {
    return _isTen(digits) ? '+91$digits' : null;
  }
  if (digits.length == 11 && digits.startsWith('0') && _isTen(digits.substring(1))) {
    return '+91${digits.substring(1)}';
  }
  if (digits.length == 12 && digits.startsWith('91') && _isTen(digits.substring(2))) {
    return '+91${digits.substring(2)}';
  }
  return null;
}

/// Displays a canonical '+91XXXXXXXXXX' number in a friendlier shape for
/// on-screen copy: '+91 98765 43210'. Anything unexpected is returned as-is.
String humanizeWhatsAppPhone(String canonical) {
  if (canonical.startsWith('+91') && canonical.length == 13) {
    final ten = canonical.substring(3);
    return '+91 ${ten.substring(0, 5)} ${ten.substring(5)}';
  }
  return canonical;
}
