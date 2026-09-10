import 'package:flutter/widgets.dart';

/// The route names a cold start begins with.
///
/// Mirrors [Navigator.defaultGenerateInitialRoutes]: a path-style initial
/// route (`/product/<id>`, from a shared link) is preceded by the names of its
/// ancestor paths, so the browser back button has somewhere to go, while a
/// plain `/` is a single route. [AppRouter.generateInitialRoutes] turns each of
/// these names into a page; only the last one — the page the visitor is
/// actually opening — is built without a transition, because a first page that
/// fades in from fully transparent is what made a launch look like a flash of
/// blank cream between the splash handing over and the app appearing.
///
/// Kept in its own file (no page imports) so it stays unit-testable on the
/// Dart VM, where the Firebase-backed route pages cannot be compiled.
List<String> initialRouteNames(String initialRouteName) {
  if (initialRouteName.startsWith('/') && initialRouteName.length > 1) {
    final names = <String>[Navigator.defaultRouteName];
    var routeName = '';
    for (final part in initialRouteName.substring(1).split('/')) {
      routeName += '/$part';
      names.add(routeName);
    }
    return names;
  }
  if (initialRouteName != Navigator.defaultRouteName) {
    return <String>[initialRouteName];
  }
  return <String>[Navigator.defaultRouteName];
}

/// How a page arrives on screen.
///
/// [animated] is what the router's transition builder branches on: a
/// non-animated arrival hands the page straight through, so nothing is
/// composited over it and no opacity is ever applied. The durations are set to
/// zero for the same arrival, so the route's animation is already finished by
/// the time anything is painted — belt and braces, and the reason a zero-length
/// first transition is enough on its own to remove the fade.
class RouteArrival {
  const RouteArrival({
    required this.forward,
    required this.reverse,
    required this.animated,
  });

  /// Milliseconds the incoming animation runs for.
  final Duration forward;

  /// Milliseconds the outgoing (back) animation runs for.
  final Duration reverse;

  /// Whether the fade-and-rise transition is applied at all.
  final bool animated;

  /// Drawn in its first frame: no fade, no rise, nothing but the page.
  static const RouteArrival instant = RouteArrival(
    forward: Duration.zero,
    reverse: Duration.zero,
    animated: false,
  );

  /// Fades and rises into place — every ordinary navigation.
  static const RouteArrival ordinary = RouteArrival(
    forward: Duration(milliseconds: 380),
    reverse: Duration(milliseconds: 260),
    animated: true,
  );
}

/// The arrival of the route at [index] of a launch stack of [count] routes.
///
/// Only the last one is the page the visitor is opening, and it must be there
/// in the first frame. A first page that faded in from fully transparent is
/// exactly what made a launch look like a flash of blank cream between the
/// splash handing over and the app appearing. Everything stacked underneath
/// (the ancestors of a deep link) keeps the ordinary transition, so pressing
/// back still reveals a page the way it always has.
RouteArrival launchArrival(int index, int count) =>
    index == count - 1 ? RouteArrival.instant : RouteArrival.ordinary;

/// The arrival of any route opened once the app is already up.
const RouteArrival laterArrival = RouteArrival.ordinary;
