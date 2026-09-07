import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../pages/pwa/pwa_registry.dart';
import '../router/app_nav.dart';
import '../router/routes.dart';
import '../state/cart_controller.dart';
import 'brand.dart';

/// Floating top navigation bar. Rendered by [MxShell] above page content.
class MxTopBar extends StatelessWidget {
  const MxTopBar({
    super.key,
    required this.scrolled,
    required this.onMenu,
    this.showMenu = true,
  });

  final bool scrolled;
  final VoidCallback onMenu;

  /// Whether the mobile hamburger menu is shown. The browser website keeps
  /// it (it is the only navigation on a narrow phone); the installed app
  /// hides it because the bottom navigation already covers every primary
  /// section.
  final bool showMenu;

  void _go(BuildContext context, String route) {
    AppNav.go(context, route);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;
    final cart = context.watch<CartController>();
    // The account icon fits the bar from large phones up; on small phones it
    // lives in the drawer (My Account) so the bar never overflows.
    final showAccount = width >= 480;

    // Active-section highlight for the desktop links. The installed app
    // marks its section through the bottom navigation instead (a live
    // pager is not on the route of the section it shows), so the top
    // links only light up in a normal browser tab.
    final pagerLive = PwaRegistry.switchToSection != null;
    final currentRoute = ModalRoute.of(context)?.settings.name;
    bool isActive(String route) => !pagerLive && currentRoute == route;

    return _FrostPill(
      frosted: scrolled,
      margin: EdgeInsets.symmetric(horizontal: width >= 1440 ? 48 : 20),
      padding: EdgeInsets.symmetric(
        horizontal: width >= 1024 ? 14 : 10,
        vertical: 8,
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => _go(context, Routes.home),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: MxLogo(showFull: width >= 420),
            ),
          ),
          const Spacer(),
          if (desktop) ...[
            _NavLink(
              active: isActive(Routes.shop),
              label: 'Shop',
              route: Routes.shop,
            ),
            _NavLink(
              active: isActive(Routes.farm),
              label: 'Farm',
              route: Routes.farm,
            ),
            _NavLink(
              active: isActive(Routes.journey),
              label: 'Journey',
              route: Routes.journey,
            ),
            _NavLink(
              active: isActive(Routes.team),
              label: 'Team',
              route: Routes.team,
            ),
            _NavLink(
              active: isActive(Routes.contact),
              label: 'Contact',
              route: Routes.contact,
            ),
            const SizedBox(width: 8),
            if (showAccount) ...[
              _AccountButton(onTap: () => _go(context, Routes.profile)),
              const SizedBox(width: 2),
            ],
            _CartButton(
              count: cart.totalQuantity,
              onTap: () => _go(context, Routes.cart),
            ),
            const SizedBox(width: 6),
            _OrderCta(onTap: () => _go(context, Routes.shop)),
          ] else ...[
            if (showAccount) ...[
              _AccountButton(onTap: () => _go(context, Routes.profile)),
              const SizedBox(width: 2),
            ],
            _CartButton(
              count: cart.totalQuantity,
              onTap: () => _go(context, Routes.cart),
            ),
            if (showMenu) ...[
              const SizedBox(width: 4),
              _MenuButton(onTap: onMenu),
            ],
          ],
        ],
      ),
    );
  }
}

/// Frosted-glass shell for the floating top bar. Transparent while the
/// page sits at its top; once it scrolls, the bar fades into a translucent
/// cream pill with a soft backdrop blur, a hairline border and a restrained
/// shadow — so content sliding underneath reads as gently frosted glass.
class _FrostPill extends StatelessWidget {
  const _FrostPill({
    required this.frosted,
    required this.margin,
    required this.padding,
    required this.child,
  });

  final bool frosted;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      margin: margin,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: frosted
            ? [
                BoxShadow(
                  color: MxColors.charcoal.withValues(alpha: 0.10),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ]
            : const <BoxShadow>[],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Positioned.fill(
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                opacity: frosted ? 1 : 0,
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: const ColoredBox(color: Colors.transparent),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: frosted
                      ? MxColors.cream.withValues(alpha: 0.82)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: frosted
                        ? Colors.white.withValues(alpha: 0.55)
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({
    required this.active,
    required this.label,
    required this.route,
  });

  /// Whether this link names the page currently shown. Only marked in a
  /// browser tab: the installed app highlights sections through its bottom
  /// navigation instead, and a live pager is not on the route of the
  /// section it displays.
  final bool active;

  final String label;
  final String route;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _focused = false;

  void _go() {
    AppNav.go(context, widget.route);
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _go();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: width >= 1280 ? 14 : 8),
      child: Focus(
        onFocusChange: (focused) => setState(() => _focused = focused),
        onKeyEvent: _handleKey,
        child: InkWell(
          onTap: _go,
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 14),
            decoration: BoxDecoration(
              color: widget.active
                  ? MxColors.moss.withValues(alpha: 0.16)
                  : (_focused
                        ? MxColors.moss.withValues(alpha: 0.10)
                        : Colors.transparent),
              borderRadius: BorderRadius.circular(999),
            ),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style: MxType.labelLg(
                color: widget.active || _focused
                    ? MxColors.forest
                    : MxColors.charcoalSoft,
                weight: widget.active ? FontWeight.w800 : FontWeight.w600,
              ),
              child: Text(widget.label),
            ),
          ),
        ),
      ),
    );
  }
}

/// Account entry point (sign-in / profile). Present for every visitor —
/// guests land on the sign-in page, signed-in customers on their account.
class _AccountButton extends StatelessWidget {
  const _AccountButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: 'My account',
      style: IconButton.styleFrom(
        hoverColor: MxColors.moss.withValues(alpha: 0.10),
      ),
      icon: const Icon(
        Icons.person_outline_rounded,
        size: 21,
        color: MxColors.forest,
      ),
    );
  }
}

class _CartButton extends StatelessWidget {
  const _CartButton({required this.count, required this.onTap});
  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final label = count > 0 ? 'Open cart, $count items' : 'Open cart';
    return IconButton(
      onPressed: onTap,
      tooltip: label,
      style: IconButton.styleFrom(
        hoverColor: MxColors.moss.withValues(alpha: 0.10),
      ),
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(
            Icons.shopping_bag_outlined,
            size: 21,
            color: MxColors.forest,
          ),
          if (count > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: const BoxDecoration(
                  color: MxColors.moss,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                child: Center(
                  child: Text(
                    '$count',
                    style: const TextStyle(
                      fontFamily: 'Manrope',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _OrderCta extends StatelessWidget {
  const _OrderCta({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        decoration: BoxDecoration(
          color: MxColors.forest,
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          'Order Now',
          style: TextStyle(
            fontFamily: 'Manrope',
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: Colors.white,
          ),
        ),
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: MxColors.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        onPressed: onTap,
        tooltip: 'Open menu',
        padding: const EdgeInsets.all(6),
        style: IconButton.styleFrom(
          hoverColor: MxColors.moss.withValues(alpha: 0.10),
        ),
        icon: const Icon(Icons.menu_rounded, size: 20, color: MxColors.forest),
      ),
    );
  }
}

/// Slide-in navigation drawer (mobile / tablet).
class MxDrawer extends StatelessWidget {
  const MxDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;

    return Drawer(
      backgroundColor: MxColors.cream,
      width: width * 0.82,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(left: Radius.circular(28)),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
              child: Row(
                children: [
                  const MxLogo(showFull: true),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Close menu',
                    padding: const EdgeInsets.all(6),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 22,
                      color: MxColors.forest,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: MxColors.line, height: 24),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                children: [
                  _DrawerLink(label: 'Home', route: Routes.home),
                  _DrawerLink(label: 'Shop', route: Routes.shop),
                  _DrawerLink(label: 'Farm', route: Routes.farm),
                  _DrawerLink(label: 'Journey', route: Routes.journey),
                  _DrawerLink(label: 'Team', route: Routes.team),
                  _DrawerLink(label: 'Contact', route: Routes.contact),
                  const SizedBox(height: 16),
                  ListTile(
                    onTap: () {
                      Navigator.of(context).pop();
                      AppNav.go(context, Routes.profile);
                    },
                    leading: const Icon(
                      Icons.person_outline_rounded,
                      color: MxColors.moss,
                    ),
                    title: Text(
                      'My Account',
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Fresh by Us. Naturally Good.',
                style: MxType.label(color: MxColors.earth),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerLink extends StatelessWidget {
  const _DrawerLink({required this.label, required this.route});

  final String label;
  final String route;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () {
        Navigator.of(context).pop();
        AppNav.go(context, route);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(
        label,
        style: MxType.bodySm(color: MxColors.charcoal, weight: FontWeight.w600),
      ),
    );
  }
}
