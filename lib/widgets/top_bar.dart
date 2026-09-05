import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../router/routes.dart';
import '../state/cart_controller.dart';
import 'brand.dart';

/// Floating top navigation bar. Rendered by [MxShell] above page content.
class MxTopBar extends StatelessWidget {
  const MxTopBar({super.key, required this.scrolled, required this.onMenu});

  final bool scrolled;
  final VoidCallback onMenu;

  void _go(BuildContext context, String route) {
    Navigator.of(context).pushNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;
    final cart = context.watch<CartController>();

    final barColor = scrolled
        ? MxColors.cream.withValues(alpha: 0.94)
        : Colors.transparent;
    final borderColor = scrolled ? MxColors.line : Colors.transparent;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOut,
      margin: EdgeInsets.symmetric(horizontal: width >= 1440 ? 48 : 20),
      padding: EdgeInsets.symmetric(
        horizontal: width >= 1024 ? 14 : 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: barColor,
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(20),
        boxShadow: scrolled
            ? [
                BoxShadow(
                  color: MxColors.charcoal.withValues(alpha: 0.07),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
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
            _NavLink(label: 'Shop', route: Routes.shop),
            _NavLink(label: 'Farm', route: Routes.farm),
            _NavLink(label: 'Journey', route: Routes.journey),
            _NavLink(label: 'Team', route: Routes.team),
            _NavLink(label: 'Contact', route: Routes.contact),
            const SizedBox(width: 8),
            _CartButton(
              count: cart.totalQuantity,
              onTap: () => _go(context, Routes.cart),
            ),
            const SizedBox(width: 6),
            _OrderCta(onTap: () => _go(context, Routes.shop)),
          ] else ...[
            _CartButton(
              count: cart.totalQuantity,
              onTap: () => _go(context, Routes.cart),
            ),
            const SizedBox(width: 4),
            _MenuButton(onTap: onMenu),
          ],
        ],
      ),
    );
  }
}

class _NavLink extends StatefulWidget {
  const _NavLink({required this.label, required this.route});

  final String label;
  final String route;

  @override
  State<_NavLink> createState() => _NavLinkState();
}

class _NavLinkState extends State<_NavLink> {
  bool _focused = false;

  void _go() {
    Navigator.of(context).pushNamed(widget.route);
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
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 150),
              style:
                  MxType.label(
                    color: _focused ? MxColors.forest : MxColors.charcoalSoft,
                    weight: FontWeight.w600,
                  ).copyWith(
                    decoration: _focused
                        ? TextDecoration.underline
                        : TextDecoration.none,
                    decorationThickness: 2,
                  ),
              child: Text(widget.label),
            ),
          ),
        ),
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
    final cart = context.watch<CartController>();

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
                    onTap: () => Navigator.of(context).pushNamed(Routes.cart),
                    leading: const Icon(
                      Icons.shopping_bag_outlined,
                      color: MxColors.moss,
                    ),
                    title: Text(
                      'Cart',
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w600,
                      ),
                    ),
                    trailing: cart.totalQuantity > 0
                        ? Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: const BoxDecoration(
                              color: MxColors.moss,
                              borderRadius: BorderRadius.all(
                                Radius.circular(999),
                              ),
                            ),
                            child: Text(
                              '${cart.totalQuantity}',
                              style: const TextStyle(
                                fontFamily: 'Manrope',
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                              ),
                            ),
                          )
                        : null,
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
        Navigator.of(context).pushNamed(route);
      },
      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
      title: Text(
        label,
        style: MxType.bodySm(color: MxColors.charcoal, weight: FontWeight.w600),
      ),
    );
  }
}
