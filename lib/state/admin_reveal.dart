import 'package:flutter/widgets.dart';

import '../router/routes.dart';

/// How far a visitor has summoned the hidden admin area.
enum AdminRevealStage {
  /// Not summoned. Direct `/admin` visits hand off to the public home route,
  /// so the admin page has no discoverable URL for strangers.
  hidden,

  /// The visible "Admin" entry (account page / top bar) was used: show the
  /// admin sign-in page. Firebase Auth is the real boundary, and a signed-in
  /// administrator always lands on the gate regardless of this stage. A
  /// signed-in account without a grant can still unlock one with the owner-set
  /// admin access code (a rules-verified write) - see AuthController.
  signIn,
}

/// Non-secret summoner for the admin area.
///
/// The ways to reach the admin area are (a) the visible "Admin" entries (the
/// account-page tile, the top-bar entry when the owner switched it on) via
/// [openAdmin], (b) an already signed-in administrator visiting `/admin`
/// directly, and (c) a signed-in account without a grant submitting the
/// owner-set admin access code on the gate. A visitor who wanders to `/admin`
/// unsummoned only ever sees the normal public site: [AdminGate] shows the
/// sign-in or dashboard purely from this stage + Firebase auth state. Nothing
/// here is a security boundary — a uid is an administrator only because
/// `admins/{uid}` exists, which the Firestore security rules enforce on every
/// protected operation; the admin access code (owner-set, compared only in the
/// rules engine) is the bootstrap that creates that grant.
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
