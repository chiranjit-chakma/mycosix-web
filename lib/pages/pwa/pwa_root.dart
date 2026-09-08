import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../router/routes.dart';
import '../../services/app_exit.dart';
import '../../state/back_press_controller.dart';
import '../../widgets/footer.dart';
import '../../widgets/top_bar.dart';
import '../farm/farm_page.dart';
import '../home/home_page.dart';
import '../journey/journey_page.dart';
import '../profile/profile_page.dart';
import '../shop/shop_page.dart';
import 'pwa_dock.dart';
import 'pwa_registry.dart';

/// Index of each primary section inside the paging shell: Home 0, Shop 1,
/// Farm 2, Journey 3, Profile 4. Any other route is -1 (not a primary
/// section). Pure so it can be unit-tested and reused by the router.
int primarySectionIndex(String route) {
  switch (route) {
    case Routes.home:
      return 0;
    case Routes.shop:
      return 1;
    case Routes.farm:
      return 2;
    case Routes.journey:
      return 3;
    case Routes.profile:
      return 4;
    default:
      return -1;
  }
}

/// The five primary sections of the installed MYCOSIX app, in page order.
/// Each page renders in its embedded form — content only, no per-page shell —
/// because the paging shell provides the app chrome (floating top bar,
/// footer, carousel dock) around them.
const List<Widget> kPwaSections = <Widget>[
  HomePage(embedded: true),
  ShopPage(embedded: true),
  FarmPage(embedded: true),
  JourneyPage(embedded: true),
  ProfilePage(embedded: true),
];

const List<String> kPwaSectionLabels = <String>[
  'Home',
  'Shop',
  'Farm',
  'Journey',
  'Profile',
];

const List<IconData> kPwaSectionIcons = <IconData>[
  Icons.home_rounded,
  Icons.storefront_rounded,
  Icons.agriculture_rounded,
  Icons.route_rounded,
  Icons.person_rounded,
];

/// Expanded (fully scrolled-up) and compressed (scrolled-down) heights of
/// the floating dock, and the clearance kept around it: a gap above the
/// screen's bottom safe inset, then room inside each section's scroll view
/// so the footer never hides behind it. The dock compresses smoothly along
/// the page's scroll, so each section's scroll reserve follows the same
/// 0..1 curve.
const double _kDockHeightWide = 78;
const double _kDockHeightNarrow = 58;

/// The installed phone app's home: a horizontal pager over the five primary
/// sections with the floating carousel dock.
///
/// Used ONLY when the app runs as an installed *phone-size* PWA (display-mode
/// standalone on a window narrower than the desktop breakpoint). A browser
/// tab — and a desktop installed PWA — never builds this widget; they keep
/// the ordinary per-page navigation. The pager itself does not swipe:
/// horizontal navigation belongs to the dock alone, so in-page carousels,
/// image rails, maps and forms are never mistaken for navigation.
class MxPwaRoot extends StatefulWidget {
  const MxPwaRoot({
    super.key,
    this.initialIndex = 0,
    this.sections = kPwaSections,
  });

  /// Which section to open at first (drives deep links: /shop -> index 1).
  final int initialIndex;

  /// The sections in page order. Injectable so widget tests can exercise the
  /// paging/gesture behavior with tiny stand-in pages.
  final List<Widget> sections;

  @override
  State<MxPwaRoot> createState() => _MxPwaRootState();
}

class _MxPwaRootState extends State<MxPwaRoot>
    with SingleTickerProviderStateMixin {
  late final PageController _pageController;
  late int _index;
  NavigatorState? _rootNavigator;
  final Map<int, _PwaSectionState> _sectionStates = <int, _PwaSectionState>{};
  final _back = BackPressController();

  /// Page-scroll compression of the floating dock: 0 expanded at the top of
  /// the page, 1 fully compressed once scrolled down. It follows the visible
  /// section's scroll position while the user scrolls, and eases to the new
  /// section's state when the section changes.
  late final AnimationController _dockT = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.sections.length - 1);
    _pageController = PageController(initialPage: _index);
    _rootNavigator = context.findAncestorStateOfType<NavigatorState>();
    PwaRegistry.switchToSection = _switchToRoute;
    PwaRegistry.scrollVisibleToTop = _scrollVisibleToTop;
  }

  @override
  void dispose() {
    if (PwaRegistry.switchToSection == _switchToRoute) {
      PwaRegistry.switchToSection = null;
    }
    if (PwaRegistry.scrollVisibleToTop == _scrollVisibleToTop) {
      PwaRegistry.scrollVisibleToTop = null;
    }
    _dockT.dispose();
    _pageController.dispose();
    super.dispose();
  }

  /// The five primary sections as navigator routes are switched here instead
  /// of being pushed. Returns false for non-primary routes so the caller
  /// pushes them normally.
  bool _switchToRoute(String route) {
    final idx = primarySectionIndex(route);
    if (idx < 0) return false;
    // Bottom-tab semantics: switching a section closes any secondary page
    // (cart, product, ...) stacked above the pager.
    _rootNavigator?.popUntil((r) => r.isFirst);
    _switchTo(idx);
    return true;
  }

  bool _scrollVisibleToTop() {
    // Only claim the request while the pager itself is the visible route: a
    // page pushed on top of it (checkout after an order, ...) must scroll its
    // own shell so the customer lands on the confirmation, not the hidden
    // section underneath.
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    final s = _sectionStates[_index];
    if (s == null) return false;
    s.scrollToTop();
    return true;
  }

  /// Live follow from a section's scroll notification: the dock tracks the
  /// page 1:1, expanding and compressing as the section scrolls.
  void _setDockCompression(double c) {
    if (!mounted) return;
    _dockT.value = c;
  }

  /// The pager settled on another section: update the active index and ease
  /// the dock to that section's own scroll compression.
  void _onPageChanged(int i) {
    setState(() => _index = i);
    _dockT.animateTo(
      _sectionStates[i]?.compression.value ?? 0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _switchTo(int index) {
    if (!mounted) return;
    if (index == _index) {
      // Tapping the section you are already on glides it back to the top.
      _sectionStates[index]?.scrollToTop();
      return;
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  /// System back inside the app: any section other than Home glides back
  /// to Home (the customer's anchor) in one step; back on Home runs the
  /// exit guard (scroll to top, then "press back again to exit", then
  /// leave).
  void _handleBack() {
    if (_index > 0) {
      _switchTo(0);
      return;
    }
    final s = _sectionStates[0];
    final scrolledDown = s?.isScrolled ?? false;
    switch (_back.handle(scrolledDown: scrolledDown)) {
      case BackPressAction.scrollToTop:
        s?.scrollToTop();
      case BackPressAction.showExitWarning:
        _showExitWarning();
      case BackPressAction.exit:
        AppExit.maybeClose();
    }
  }

  void _showExitWarning() {
    final bottom = 96.0 + MediaQuery.paddingOf(context).bottom;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text('Press back again to exit the MYCOSIX app'),
          duration: const Duration(milliseconds: 2500),
          behavior: SnackBarBehavior.floating,
          margin: EdgeInsets.only(bottom: bottom),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // The pager owns the system back button while it is the top route.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: MxColors.cream,
        // The pages fill the whole screen and the floating glass navigation
        // bar overlays them; each section reserves bottom scroll space so
        // its content can always clear the bar.
        body: Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                key: const Key('pwa-pager'),
                controller: _pageController,
                // Only the dock navigates sections; the pager never swipes,
                // so a horizontal carousel, image rail, map or form inside a
                // section is never mistaken for navigation.
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.sections.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (context, index) {
                  return _PwaSection(
                    key: Key('pwa-section-$index'),
                    index: index,
                    onSwitchSection: _switchTo,
                    onCompression: _setDockCompression,
                    onState: (state) => _sectionStates[index] = state,
                    child: widget.sections[index],
                  );
                },
              ),
            ),
            // Floating carousel dock: safe-area aware, floating just above
            // the bottom inset, capped in width so the strip stays a
            // comfortable centred capsule on wide phones.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 620),
                    child: PwaDock(
                      key: const Key('pwa-dock'),
                      index: _index,
                      labels: kPwaSectionLabels,
                      icons: kPwaSectionIcons,
                      onSelect: _switchTo,
                      compression: _dockT,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One pager page: the section content plus the app chrome each section
/// carries in the browser too — a scrollable body with the footer and the
/// floating top bar (the back-to-top button sits inside the footer area,
/// raised above the floating dock). Kept alive so moving between sections
/// never loses the section's scroll position or re-fetches its data.
class _PwaSection extends StatefulWidget {
  const _PwaSection({
    super.key,
    required this.index,
    required this.child,
    required this.onSwitchSection,
    required this.onCompression,
    required this.onState,
  });

  final int index;
  final Widget child;
  final void Function(int index) onSwitchSection;
  final void Function(double compression) onCompression;
  final void Function(_PwaSectionState state) onState;

  @override
  State<_PwaSection> createState() => _PwaSectionState();
}

class _PwaSectionState extends State<_PwaSection>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();

  /// This section's contribution to the dock's compression (0 at the top,
  /// 1 after about 200px of scrolling). The root eases its dock animation
  /// to whichever section is visible.
  final compression = ValueNotifier<double>(0);

  bool _scrolled = false;

  @override
  bool get wantKeepAlive => true;

  bool get isScrolled => _scrolled;

  @override
  void initState() {
    super.initState();
    widget.onState(this);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    compression.dispose();
    super.dispose();
  }

  void scrollToTop() {
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

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    final scrolled = notification.metrics.pixels > 24;
    if (scrolled != _scrolled && mounted) {
      setState(() => _scrolled = scrolled);
    }
    // The dock compresses 1:1 with the page's scroll — progressive, never a
    // jump — and eases back out as the section returns to the top.
    final c = (notification.metrics.pixels / 200.0).clamp(0.0, 1.0);
    if ((c - compression.value).abs() > 0.0005) {
      compression.value = c;
      widget.onCompression(c);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final width = MediaQuery.of(context).size.width;
    return NotificationListener<ScrollNotification>(
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
                child: ListenableBuilder(
                  listenable: compression,
                  builder: (context, _) {
                    final c = compression.value;
                    // Scroll room for the floating dock: even fully scrolled
                    // down, the footer clears the capsule by a comfortable
                    // margin. The reserve shrinks with the dock as the page
                    // scrolls, so compressed content gains the space the
                    // smaller dock frees up.
                    final dockHeight =
                        _kDockHeightWide +
                        (_kDockHeightNarrow - _kDockHeightWide) * c;
                    return Padding(
                      padding: EdgeInsets.only(
                        bottom:
                            MediaQuery.paddingOf(context).bottom +
                            10 +
                            dockHeight +
                            12,
                      ),
                      child: Column(
                        children: [widget.child, const MxFooter()],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          // Floating top bar, exactly as on the browser pages. The hamburger
          // menu is hidden here: the dock already reaches every primary
          // section, and the rest lives under Profile -> More.
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: MxTopBar(
              scrolled: _scrolled,
              onMenu: () {},
              showMenu: false,
            ),
          ),
        ],
      ),
    );
  }
}
