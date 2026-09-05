/// Formatting helpers for rupee prices.
String formatRupees(num value) {
  final v = value.toDouble();
  if (v == v.roundToDouble()) {
    return '₹${v.toStringAsFixed(0)}';
  }
  return '₹${v.toStringAsFixed(2)}';
}
