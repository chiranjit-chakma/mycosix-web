/// Named routes for the app.
///
/// Kept separate from [AppRouter] (router/app_router.dart) so pages only import
/// these plain string constants. Importing the router itself pulls in every
/// route page - including the Firebase-backed admin area - which would stop
/// widget tests from compiling on the VM.
class Routes {
  Routes._();

  static const home = '/';
  static const shop = '/shop';
  static const farm = '/farm';
  static const journey = '/journey';
  static const team = '/team';
  static const contact = '/contact';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const cart = '/cart';
  static const checkout = '/checkout';
  static const product = '/product';
  static const admin = '/admin';
}
