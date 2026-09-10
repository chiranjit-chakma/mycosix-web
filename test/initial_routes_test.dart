import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mycosix/router/initial_routes.dart';

/// The stack a cold start begins with. The router builds a page for each of
/// these names and renders only the LAST one instantly (the rest fade in
/// underneath it, never seen), which is what stops a launch from showing a
/// beat of blank cream between the splash and the first page.
void main() {
  test('the home route is a single route', () {
    expect(initialRouteNames('/'), <String>['/']);
  });

  test('a named route sits above the home route', () {
    expect(initialRouteNames('/shop'), <String>['/', '/shop']);
    expect(initialRouteNames('/admin'), <String>['/', '/admin']);
  });

  test('a path-style deep link keeps its ancestor paths for the back button',
      () {
    expect(
      initialRouteNames('/product/oyster-250g'),
      <String>['/', '/product', '/product/oyster-250g'],
    );
    expect(
      initialRouteNames('/my-orders/abc123'),
      <String>['/', '/my-orders', '/my-orders/abc123'],
    );
  });

  test('a bare name with no leading slash is used as-is', () {
    expect(initialRouteNames('shop'), <String>['shop']);
  });

  test('the last name is always the one that was asked for', () {
    for (final name in <String>[
      '/',
      '/shop',
      '/product/oyster-250g',
      '/my-orders/abc123',
    ]) {
      expect(initialRouteNames(name).last, name, reason: name);
    }
  });

  test('the page a cold start lands on is drawn, never faded in', () {
    // A first page that faded in from fully transparent is what made a launch
    // look like a flash of blank cream. The route the visitor is opening is
    // the LAST one in the stack, and it arrives instantly - zero forward and
    // zero reverse duration, and no transition applied at all.
    for (final name in <String>['/', '/shop', '/product/oyster-250g']) {
      final names = initialRouteNames(name);
      final arrival = launchArrival(names.length - 1, names.length);

      expect(arrival.animated, isFalse, reason: name);
      expect(arrival.forward, Duration.zero, reason: name);
      expect(arrival.reverse, Duration.zero, reason: name);
      expect(arrival, same(RouteArrival.instant), reason: name);
    }
  });

  test('a deep link keeps its ancestors, and they still fade in', () {
    final names = initialRouteNames('/product/oyster-250g');
    expect(names.length, 3);

    for (var i = 0; i < names.length - 1; i++) {
      final arrival = launchArrival(i, names.length);
      expect(arrival.animated, isTrue, reason: names[i]);
      expect(arrival.forward, const Duration(milliseconds: 380));
      expect(arrival.reverse, const Duration(milliseconds: 260));
    }
  });

  test('a single-route launch still arrives instantly', () {
    // '/' is one route, so the check above is the whole story for a normal
    // open: there is no ancestor to animate.
    expect(launchArrival(0, 1), same(RouteArrival.instant));
  });

  test('routes opened after launch keep the ordinary transition', () {
    // Navigation inside the app is unchanged: still fades and rises.
    expect(laterArrival.animated, isTrue);
    expect(laterArrival.forward, const Duration(milliseconds: 380));
    expect(laterArrival.reverse, const Duration(milliseconds: 260));
  });

  test('every stack starts at the home route', () {
    // Every path-style name is preceded by "/", so a back press always has
    // somewhere to land rather than dropping the visitor out of the app.
    expect(initialRouteNames('/product/x').first, Navigator.defaultRouteName);
  });
}
