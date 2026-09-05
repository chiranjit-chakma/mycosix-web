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

  static String? optional(String? value) => null;
}
