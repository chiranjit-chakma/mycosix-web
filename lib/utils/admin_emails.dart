/// Pure helpers for the Admins manager (inviting an administrator, setting your
/// own code). Kept free of Firebase so it is unit-testable like the rest of the
/// pure logic in this app.
library;

/// Canonical form for an admin email: trimmed and lowercased. This is also the
/// document key used in the `adminCodes` collection and the `email` field on
/// invited admin grants, so it matches the auth token email the rules compare
/// against (Firebase Auth emails are already lowercase).
String adminEmailKey(String raw) => raw.trim().toLowerCase();

final RegExp _emailShape = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

/// True when [raw] looks like an email address. Only checks the shape - never
/// deliverability.
bool isPlausibleAdminEmail(String raw) => _emailShape.hasMatch(raw.trim());

/// Human message describing why [raw] is not an acceptable admin code, or null
/// when it is. Codes are compared exactly server-side; the bounds here only
/// stop an admin accidentally saving a long paste as a code.
String? adminCodeError(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return 'Enter the code for this admin.';
  if (t.length > 64) return 'Keep the code to 64 characters or fewer.';
  return null;
}
