import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../router/routes.dart';
import '../services/app_exit.dart';
import '../services/display_mode.dart';
import '../state/back_press_controller.dart';
import 'footer.dart';
import 'top_bar.dart';

/// Master layout: floating top bar over a scrolling page + footer.
///
/// Owns scroll state and passes it to [MxTopBar]. Also hosts the two
/// navigation helpers the site-wide UX needs:
///
/// * a premium "back to top" floating button that appears once the page is
///   scrolled down (every page gets it for free);
/// * the installed-app back-press behaviour on the home page — back while
///   scrolled glides to the top, back again shows an exit warning, and back a
///   third time within the warning window closes the app. Normal browser tabs
///   keep their ordinary back behaviour.
class MxShell extends StatefulWidget {
  const MxShell({super.key, required this.child, this.showFooter = true});

  final Widget child;
  final bool showFooter;

  /// Every shell currently mounted, in mount order (the last one is the page
  /// on top of the navigator stack). Lets any page ask the visible shell to
  /// glide back to the top — checkout uses this after placing an order so the
  /// customer lands on the Order Confirmed section.
  static final List<_MxShellState> _live = <_MxShellState>[];

  /// Glides the visible page back to the top. Safe to call at any time —
  /// with no shell mounted (e.g. a post-frame callback racing the first
  /// frame) it simply does nothing.
  static void scrollToTop() {
    final live = _live;
    if (live.isEmpty) return;
    live.last._scrollToTop();
  }

  @override
  State<MxShell> createState() => _MxShellState();
}

class _MxShellState extends State<MxShell> {
  bool _scrolled = false;
  bool _showTopButton = false;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Drives the page-level scroll. The shell reads its live position from
  /// this controller: scroll notifications carry a *snapshot* of the
  /// metrics (FixedScrollMetrics), not the position itself, so the
  /// controller is the reliable source of truth for where the page is.
  final _scrollController = ScrollController();

  final _back = BackPressController();

  /// Whether this shell is inside an installed PWA. Read once at mount from
  /// the display-mode facade (the VM test stub always reports false, so the
  /// back-press guard is inert in widget tests).
  bool? _standalone;

  @override
  void initState() {
    super.initState();
    _standalone = isStandaloneDisplay();
    MxShell._live.add(this);
  }

  @override
  void dispose() {
    MxShell._live.remove(this);
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final pixels = notification.metrics.pixels;
    final scrolled = pixels > 24;
    final showTop = pixels > 420;
    if (scrolled != _scrolled || showTop != _showTopButton) {
      if (mounted) {
        setState(() {
          _scrolled = scrolled;
          _showTopButton = showTop;
        });
      }
    }
    return false;
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels <= 0) return;
    position
        .animateTo(
          0,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeOutCubic,
        )
        .ignore();
  }

  void openDrawer() {
    // The scaffold is this widget's descendant, so Scaffold.of(context) can't
    // find it — use the key directly.
    _scaffoldKey.currentState?.openEndDrawer();
  }

  /// Installed-app back behaviour on the home route:
  /// 1. scrolled down      -> glide back to the top;
  /// 2. at the top         -> show the exit warning;
  /// 3. back again quickly -> leave the app.
  void _handleBack() {
    final scrolledDown =
        _scrollController.hasClients && _scrollController.position.pixels > 8;
    switch (_back.handle(scrolledDown: scrolledDown)) {
      case BackPressAction.scrollToTop:
        _scrollToTop();
      case BackPressAction.showExitWarning:
        _showExitWarning();
      case BackPressAction.exit:
        AppExit.maybeClose();
    }
  }

  void _showExitWarning() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Press back again to exit the MYCOSIX app'),
          duration: Duration(milliseconds: 2500),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: 96),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final standalone = _standalone ?? false;
    final atHome = ModalRoute.of(context)?.settings.name == Routes.home;
    final guardBack = standalone && atHome;

    return PopScope(
      // An installed PWA at the home route owns its back button; everywhere
      // else (browser tabs, deeper pages) back behaves as usual.
      canPop: !guardBack,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !guardBack) return;
        _handleBack();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: MxColors.cream,
        endDrawer: const MxDrawer(),
        body: NotificationListener<ScrollNotification>(
          onNotification: _handleScroll,
          child: Stack(
            children: [
              Positioned.fill(
                child: Scrollbar(
                  controller: _scrollController,
                  thumbVisibility: width >= 1024,
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    physics: const BouncingScrollPhysics(
                      parent: AlwaysScrollableScrollPhysics(),
                    ),
                    child: Column(
                      children: [
                        widget.child,
                        if (widget.showFooter) const MxFooter(),
                      ],
                    ),
                  ),
                ),
              ),
              // Floating top bar — taps pass through where it is transparent.
              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  ignoring: false,
                  child: MxTopBar(
                    scrolled: _scrolled,
                    onMenu: openDrawer,
                  ),
                ),
              ),
              // Premium "back to top" — fades and scales in once the page has
              // been scrolled well down, taps glide smoothly back up.
              Positioned(
                right: width >= 768 ? 24 : 14,
                bottom: width >= 768 ? 28 : 16,
                child: IgnorePointer(
                  ignoring: !_showTopButton,
                  child: AnimatedOpacity(
                    opacity: _showTopButton ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOut,
                    child: AnimatedScale(
                      scale: _showTopButton ? 1 : 0.6,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      child: _TopButton(onTap: _scrollToTop),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The floating "back to top" circle: forest-to-moss gradient, soft shadow,
/// gentle ripple — reads as premium without shouting.
class _TopButton extends StatelessWidget {
  const _TopButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Back to top',
      child: Semantics(
        button: true,
        label: 'Back to top',
        child: Material(
          key: const Key('scroll-top-button'),
          shape: const CircleBorder(),
          elevation: 6,
          shadowColor: MxColors.forest.withValues(alpha: 0.35),
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Ink(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [MxColors.forest, MxColors.mossDeep],
                ),
              ),
              child: const Icon(
                Icons.keyboard_arrow_up_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
