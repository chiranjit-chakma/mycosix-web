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
  static const profile = '/profile';
  static const wishlist = '/wishlist';
  static const myOrders = '/my-orders';
  static const admin = '/admin';
}

/// Which auth form the profile page should open with.
enum AuthStartMode { signIn, register }

/// What the profile page should do when it opens: which tab to show and
/// (optionally) the named route to return to after a successful sign-in.
///
/// Only in-app named routes are ever passed as [returnRoute] — never a raw
/// URL from outside. A plain `String` argument to `/profile` is treated as a
/// bare [returnRoute] for backward compatibility.
class ProfileRouteRequest {
  const ProfileRouteRequest({this.returnRoute, this.startMode = AuthStartMode.signIn});

  final String? returnRoute;
  final AuthStartMode startMode;
}
