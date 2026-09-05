import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../pages/admin/admin_access_lock.dart';
import '../router/routes.dart';

/// How far a visitor has summoned the hidden admin area.
enum AdminRevealStage {
  /// Not summoned. Direct `/admin` visits hand off to the public home route,
  /// so the admin page has no discoverable URL.
  hidden,

  /// The MYCOSIX wordmark was long-pressed: show the access-code door.
  door,

  /// The owner phrase was typed somewhere on the site: show the sign-in page.
  signIn,
}

/// Covert summoner for the admin area (long-press + typed phrase).
///
/// A visitor who wanders to /admin (or is never summoned) only ever sees the
/// normal public site: [AdminGate] shows the sign-in or dashboard purely from
/// [AdminRevealStage] + Firebase auth state. The long-press lives on the
/// wordmark ([MxLogo]); the phrase is matched from real key events, ignored
/// while a text field is focused so ordinary typing can never trigger it.
///
/// These triggers are deliberate obscurity, not security: Firebase Auth is the
/// real boundary, and the phrase ships (obfuscated as code points) in the
/// bundle.
class AdminReveal extends ChangeNotifier {
  AdminReveal._();

  /// The shared instance used by the app.
  static final AdminReveal shared = AdminReveal._();

  AdminRevealStage _stage = AdminRevealStage.hidden;
  AdminRevealStage get stage => _stage;

  bool get revealed => _stage != AdminRevealStage.hidden;

  /// Rolling window of the most recent printable code points typed while no
  /// text field had focus.
  final List<int> _window = <int>[];

  bool _attached = false;
  String? _topRoute;

  /// Tracks the current top route so a summon never stacks /admin on itself.
  final NavigatorObserver routeObserver = _TopRouteObserver();

  /// Starts listening for the typed phrase. Called once from the app root.
  void attach() {
    if (_attached) return;
    _attached = true;
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  void detach() {
    if (!_attached) return;
    _attached = false;
    HardwareKeyboard.instance.removeHandler(_handleKey);
  }

  /// Long-press on the MYCOSIX wordmark.
  void armDoor() => _set(AdminRevealStage.door);

  /// The owner phrase was typed. Used by the key handler and tests.
  void armSignIn() => _set(AdminRevealStage.signIn);

  /// Test hook: return to the fully hidden state and clear the key window.
  @visibleForTesting
  void resetForTest() {
    _window.clear();
    _set(AdminRevealStage.hidden);
  }

  /// Feeds one printable character exactly as the key handler would (same
  /// matching path). Public for tests; production text goes through [_handleKey].
  @visibleForTesting
  void debugFeedCharacter(String character) => _pushCharacter(character);

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

  bool _handleKey(KeyEvent event) {
    // Never arm from keys that belong to real typing in a field (checkout,
    // contact form, the door itself, …).
    if (_typingInTextField()) return false;
    // Browser/app shortcuts with modifiers must not contribute characters.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed) {
      return false;
    }
    if (event is! KeyDownEvent) return false;
    final char =
        event.character ??
        (event.logicalKey.keyLabel.length == 1
            ? event.logicalKey.keyLabel
            : null);
    if (char == null || char.length != 1) return false;
    _pushCharacter(char);
    // Always let the event through — the site must behave exactly as before.
    return false;
  }

  void _pushCharacter(String character) {
    _window.add(character.codeUnitAt(0));
    while (_window.length > AdminAccessLock.secretLength) {
      _window.removeAt(0);
    }
    if (_window.length == AdminAccessLock.secretLength &&
        AdminAccessLock.matchesCode(String.fromCharCodes(_window))) {
      _window.clear();
      armSignIn();
    }
  }

  bool _typingInTextField() {
    final focus = FocusManager.instance.primaryFocus;
    final ctx = focus?.context;
    if (ctx == null) return false;
    return ctx.widget is EditableText ||
        ctx.findAncestorWidgetOfExactType<EditableText>() != null;
  }
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
