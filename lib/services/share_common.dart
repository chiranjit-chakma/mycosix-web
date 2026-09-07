/// Product-link sharing - pure pieces shared by every target.
///
/// The actual sharing work lives behind a conditional import chosen by
/// share_service.dart: the browser gets the native share sheet
/// (share_service_web.dart), the VM test runner gets a clipboard fallback
/// (share_service_stub.dart). The pieces in this file are identical everywhere.
library;

/// What happened when sharing was requested, so the caller can tell the user.
enum ShareOutcome {
  /// Shared through the browser's native share sheet (phone share, WhatsApp,
  /// email, a desktop OS picker...).
  shared,

  /// There was no share sheet, so the product link was copied to the
  /// clipboard instead.
  copied,

  /// Neither sharing nor copying was possible.
  unsupported,
}

/// The customer-facing web address of one product's page.
///
/// Uses the current page's own origin, so a shared link always points back to
/// whatever site the customer is actually on (mycosix.web.app today, or the
/// custom domain when it is connected). [base] exists only so tests can pin
/// the origin.
String productShareUrl(String productId, {Uri? base}) {
  final b = base ?? Uri.base;
  final origin =
      b.hasScheme && b.hasAuthority ? '${b.scheme}://${b.authority}' : '';
  return '$origin/product/$productId';
}
