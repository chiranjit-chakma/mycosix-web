import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
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
/// footer, bottom navigation) around them.
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

/// The installed-app home: a Slice-style horizontal pager over the five
/// primary sections with a bottom navigation bar.
///
/// Used ONLY when the app runs as an installed PWA (display-mode standalone).
/// A normal browser tab never builds this widget — it keeps its ordinary
/// per-page navigation. The pager distinguishes navigation swipes from
/// interactions inside the pages: a horizontal carousel or image rail inside
/// a section scrolls itself, and only swipes on non-scrollable horizontal
/// space change the page.
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

class _MxPwaRootState extends State<MxPwaRoot> {
  late final PageController _pageController;
  late int _index;
  NavigatorState? _rootNavigator;
  final Map<int, _PwaSectionState> _sectionStates = <int, _PwaSectionState>{};
  final _back = BackPressController();

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
        body: PageView.builder(
          key: const Key('pwa-pager'),
          controller: _pageController,
          physics: const PageScrollPhysics(),
          itemCount: widget.sections.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (context, index) {
            return _PwaSection(
              key: Key('pwa-section-$index'),
              index: index,
              onSwitchSection: _switchTo,
              onState: (state) => _sectionStates[index] = state,
              child: widget.sections[index],
            );
          },
        ),
        bottomNavigationBar: _PwaNavBar(
          index: _index,
          labels: kPwaSectionLabels,
          icons: kPwaSectionIcons,
          onTap: _switchTo,
        ),
      ),
    );
  }
}

/// One pager page: the section content plus the app chrome each section
/// carries in the browser too — a scrollable body with the footer, the
/// floating top bar, and the back-to-top button (raised above the bottom
/// navigation). Kept alive so swiping back and forth never loses the
/// section's scroll position or re-fetches its data.
class _PwaSection extends StatefulWidget {
  const _PwaSection({
    super.key,
    required this.index,
    required this.child,
    required this.onSwitchSection,
    required this.onState,
  });

  final int index;
  final Widget child;
  final void Function(int index) onSwitchSection;
  final void Function(_PwaSectionState state) onState;

  @override
  State<_PwaSection> createState() => _PwaSectionState();
}

class _PwaSectionState extends State<_PwaSection>
    with AutomaticKeepAliveClientMixin {
  final _scrollController = ScrollController();
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
                child: Column(children: [widget.child, const MxFooter()]),
              ),
            ),
          ),
          // Floating top bar, exactly as on the browser pages. The hamburger
          // menu is hidden here: the bottom navigation already reaches every
          // primary section, and the rest lives under Profile -> More.
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

/// The installed app's bottom navigation: five destinations, safe-area aware,
/// tapping glides the pager to the matching section.
class _PwaNavBar extends StatelessWidget {
  const _PwaNavBar({
    required this.index,
    required this.labels,
    required this.icons,
    required this.onTap,
  });

  final int index;
  final List<String> labels;
  final List<IconData> icons;
  final void Function(int index) onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MxColors.cream,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(top: BorderSide(color: MxColors.line, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: _PwaNavItem(
                      key: Key('pwa-nav-${labels[i].toLowerCase()}'),
                      selected: i == index,
                      label: labels[i],
                      icon: icons[i],
                      onTap: () => onTap(i),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PwaNavItem extends StatelessWidget {
  const _PwaNavItem({
    super.key,
    required this.selected,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final bool selected;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? MxColors.forest : MxColors.stone;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: MxType.label(
                color: color,
                weight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
