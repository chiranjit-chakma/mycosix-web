import 'package:flutter/widgets.dart';

import '../pages/admin/admin_access_lock.dart';
import '../router/routes.dart';

/// How far a visitor has summoned the hidden admin area.
enum AdminRevealStage {
  /// Not summoned. Direct `/admin` visits hand off to the public home route,
  /// so the admin page has no discoverable URL.
  hidden,

  /// The owner summon phrase was typed into the Shop search box: show the
  /// admin sign-in page.
  signIn,
}

/// Covert summoner for the admin area (owner phrase typed into the Shop search
/// box - there is no other trigger and no discoverable /admin URL).
///
/// A visitor who wanders to /admin (or is never summoned) only ever sees the
/// normal public site: [AdminGate] shows the sign-in or dashboard purely from
/// [AdminRevealStage] + Firebase auth state. The owner summons it by typing
/// the exact phrase into the Shop search field - [armFromSearchText] matches
/// it code-point for code-point and ignores everything else, so ordinary
/// searches never trigger anything.
///
/// This is deliberate obscurity, not security: Firebase Auth is the real
/// boundary, and the phrase ships (obfuscated as code points) in the bundle.
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

  /// Called by the Shop search box on every edit. Returns true when the typed
  /// text is exactly the owner summon phrase - the caller must clear the box
  /// and not treat it as a product search. Any other text returns false (a
  /// normal search) and never changes state.
  bool armFromSearchText(String candidate) {
    if (!AdminAccessLock.matchesCode(candidate)) return false;
    _armSignIn();
    return true;
  }

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
