import 'package:flutter/widgets.dart';

import '../router/routes.dart';

/// How far a visitor has summoned the hidden admin area.
enum AdminRevealStage {
  /// Not summoned. Direct `/admin` visits hand off to the public home route,
  /// so the admin page has no discoverable URL for strangers.
  hidden,

  /// The visible "Admin" entry (account page) was used: show the admin
  /// sign-in page. There is no secret code anywhere — Firebase Auth is the
  /// real boundary, and a signed-in administrator always lands on the gate
  /// regardless of this stage.
  signIn,
}

/// Non-secret summoner for the admin area.
///
/// The only ways to reach the admin area are (a) the visible "Admin" entry
/// next to the account Sign-out button ([openAdmin]) and (b) an already
/// signed-in administrator visiting `/admin` directly. A visitor who wanders
/// to `/admin` unsummoned only ever sees the normal public site: [AdminGate]
/// shows the sign-in or dashboard purely from this stage + Firebase auth
/// state. Nothing ships as a secret code — this is deliberate obscurity of a
/// URL, not the security boundary. The security boundary is server-side: a
/// uid is an administrator only because `admins/{uid}` exists, which Firestore
/// security rules enforce on every protected operation.
class AdminReveal extends ChangeNotifier {
  AdminReveal._();

  /// The shared instance used by the app.
  static final AdminReveal shared = AdminReveal._();

  AdminRevealStage _stage = AdminRevealStage.hidden;
  AdminRevealStage get stage => _stage;

  bool get revealed => _stage != AdminRevealStage.hidden;

  String? _topRoute;

  /// Tracks the current top route so a summon never stacks /admin on itself.
  final NavigatorObserver routeObserver = _TopRouteObserver();

  /// Called by the visible "Admin" entry on the account page. Arms the admin
  /// sign-in and navigates to the gate. Idempotent — a second tap while
  /// already heading there does nothing.
  void openAdmin() => _armSignIn();

  void _armSignIn() => _set(AdminRevealStage.signIn);

  /// Test hook: return to the fully hidden state.
  @visibleForTesting
  void resetForTest() => _set(AdminRevealStage.hidden);

  /// Installed by the app root (running app only). Navigates to /admin when a
  /// summon fires without a BuildContext; null in headless tests, where a
  /// summon is asserted purely through [stage].
  VoidCallback? goToAdmin;

  void _set(AdminRevealStage next) {
    if (_stage == next) return;
    _stage = next;
    notifyListeners();
    _goIfNeeded();
  }

  void _goIfNeeded() {
    if (_stage == AdminRevealStage.hidden) return;
    if (_topRoute == Routes.admin) return; // AdminGate reveals in place.
    goToAdmin?.call();
  }

  void _noteTop(String? name) => _topRoute = name;
}

class _TopRouteObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AdminReveal.shared._noteTop(route.settings.name);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AdminReveal.shared._noteTop(previousRoute?.settings.name);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    AdminReveal.shared._noteTop(previousRoute?.settings.name);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    AdminReveal.shared._noteTop(newRoute?.settings.name);
  }
}
