/// Validates delivery-location text fields (checkout form).
class FormValidators {
  FormValidators._();

  static String? name(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your name';
    if (v.length < 2) return 'Name looks too short';
    return null;
  }

  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your phone number';
    if (!RegExp(r'^[0-9+\-\s]{10,15}$').hasMatch(v)) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  static String? locationDetail(String? value, {required String label}) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please add $label';
    if (v.length < 3) return '$label looks too short';
    return null;
  }

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Please enter your email';
    if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(v)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  /// Sign-in: only presence is checked — whether the password is right is
  /// decided by the auth provider, never locally.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please enter your password';
    return null;
  }

  /// Registration: the minimum for creating a new credential.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Please choose a password';
    if (v.length < 8) return 'Use at least 8 characters';
    return null;
  }

  static String? optional(String? value) => null;
}
