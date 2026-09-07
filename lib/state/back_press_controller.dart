/// What should happen when the installed-app user presses the system back
/// button while already at the home route.
enum BackPressAction {
  /// The page was scrolled down: glide back to the top instead of leaving.
  scrollToTop,

  /// First back press at the top: arm the exit hint.
  showExitWarning,

  /// Second back press within the exit window: leave the app.
  exit,
}

/// The three-step back behaviour of the installed app, kept as pure state so
/// it can be unit-tested without any widget:
///
/// 1. back while the page is scrolled down  -> scroll back to the top;
/// 2. back while at the top                -> show "press back again to exit";
/// 3. another back within the window       -> exit.
///
/// A back press that scrolled to the top also disarms the hint, so the exit
/// requires two deliberate presses while the page is already at the top.
class BackPressController {
  /// How long the "press back again to exit" hint stays armed after the first
  /// warning press.
  static const exitWindow = Duration(milliseconds: 2500);

  DateTime? _armedAt;

  /// Decides what a back press should do. [scrolledDown] is whether the page
  /// was scrolled away from the top at the moment of the press; [now] is only
  /// for deterministic tests.
  BackPressAction handle({required bool scrolledDown, DateTime? now}) {
    final t = now ?? DateTime.now();
    if (scrolledDown) {
      _armedAt = null;
      return BackPressAction.scrollToTop;
    }
    final armed = _armedAt != null && t.difference(_armedAt!) < exitWindow;
    if (!armed) {
      _armedAt = t;
      return BackPressAction.showExitWarning;
    }
    return BackPressAction.exit;
  }
}
