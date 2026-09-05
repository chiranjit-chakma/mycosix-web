import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/mx_colors.dart';

/// A call-to-action button — primary, ghost or light.
///
/// Focusable and keyboard-operable (Enter / Space activate), with a visible
/// focus ring so keyboard users can see where they are.
class MxCta extends StatefulWidget {
  const MxCta({
    super.key,
    required this.label,
    required this.onTap,
    this.tone = 'primary',
    this.icon,
  });

  final String label;
  final VoidCallback onTap;
  final String tone; // 'primary' | 'ghost' | 'light' | 'dark'
  final IconData? icon;

  @override
  State<MxCta> createState() => _MxCtaState();
}

class _MxCtaState extends State<MxCta> {
  bool _focused = false;

  void _activate() => widget.onTap();

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _activate();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final isGhost = widget.tone == 'ghost';
    final isLight = widget.tone == 'light';
    final isDark = widget.tone == 'dark';

    final bg = isGhost
        ? Colors.transparent
        : (isLight
              ? MxColors.glow
              : (isDark ? Colors.transparent : MxColors.moss));
    final fg = isGhost
        ? MxColors.charcoal
        : (isLight ? MxColors.forest : (isDark ? Colors.white : Colors.white));

    Border border;
    if (isGhost) {
      border = Border.all(
        color: _focused ? MxColors.forest : MxColors.lineDark,
        width: _focused ? 2 : 1,
      );
    } else if (isDark) {
      border = Border.all(
        color: _focused ? Colors.white : Colors.white.withValues(alpha: 0.55),
        width: _focused ? 2 : 1,
      );
    } else {
      border = Border.all(
        color: _focused ? MxColors.glowDeep : Colors.transparent,
        width: _focused ? 2 : 1,
      );
    }

    return Focus(
      onFocusChange: (focused) => setState(() => _focused = focused),
      onKeyEvent: _handleKey,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(999),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 15),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(999),
            border: border,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 18, color: fg),
                const SizedBox(width: 8),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
