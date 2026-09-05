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
