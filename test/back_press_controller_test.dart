import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/state/back_press_controller.dart';

/// The installed-app back behaviour, kept as pure state so it can be proven
/// without a widget:
///
///   back while scrolled down  -> glide back to the top (hint disarmed);
///   back while at the top     -> show the "press back again to exit" hint;
///   back again within 2.5 s   -> exit.
void main() {
  final t0 = DateTime(2026, 9, 7, 12, 0, 0);

  test('back while scrolled down scrolls to top and disarms the hint', () {
    final c = BackPressController();
    // Arm the hint first, then scroll down and press back.
    expect(
      c.handle(scrolledDown: false, now: t0),
      BackPressAction.showExitWarning,
    );
    expect(
      c.handle(scrolledDown: true, now: t0),
      BackPressAction.scrollToTop,
    );
    // The scroll press disarmed the hint: the next press warns again instead
    // of exiting.
    expect(
      c.handle(scrolledDown: false, now: t0),
      BackPressAction.showExitWarning,
    );
  });

  test('two backs at the top within the window exit', () {
    final c = BackPressController();
    expect(
      c.handle(scrolledDown: false, now: t0),
      BackPressAction.showExitWarning,
    );
    expect(
      c.handle(scrolledDown: false, now: t0.add(const Duration(seconds: 1))),
      BackPressAction.exit,
    );
  });

  test('the exit hint expires after the window', () {
    final c = BackPressController();
    expect(
      c.handle(scrolledDown: false, now: t0),
      BackPressAction.showExitWarning,
    );
    expect(
      c.handle(
        scrolledDown: false,
        now: t0.add(BackPressController.exitWindow + const Duration(seconds: 1)),
      ),
      BackPressAction.showExitWarning,
      reason: 'a slow second press should re-arm the hint, not exit',
    );
  });

  test('the exit window is exactly the documented duration', () {
    expect(BackPressController.exitWindow, const Duration(milliseconds: 2500));
  });
}
