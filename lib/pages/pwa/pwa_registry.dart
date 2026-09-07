/// Live registry shared between the installed PWA's paging shell and the rest
/// of the app.
///
/// While an [MxPwaRoot] is mounted it registers two hooks here so that
/// ordinary in-app navigation and the "glide back to the top" call after
/// placing an order behave correctly inside the app without the rest of the
/// code knowing anything about the pager:
///
/// * [switchToSection] — intercepts pushes to the five primary section
///   routes while the pager is live, gliding the pager to that section
///   instead of stacking a second paging shell on the navigator.
/// * [scrollVisibleToTop] — scrolls whichever section is on screen, so
///   checkout's post-order scroll lands on the visible section.
///
/// In a normal browser tab neither hook is ever registered, so
/// [switchSection] and [scrollToTop] simply report "not handled" and the
/// caller keeps its ordinary behavior.
class PwaRegistry {
  PwaRegistry._();

  static bool Function(String route)? switchToSection;
  static bool Function()? scrollVisibleToTop;

  /// True if a live pager consumed [route] as a primary-section switch.
  static bool switchSection(String route) =>
      switchToSection?.call(route) ?? false;

  /// True if a live pager scrolled its visible section back to the top.
  static bool scrollToTop() => scrollVisibleToTop?.call() ?? false;
}
