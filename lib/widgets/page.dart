import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import 'shell.dart';

/// Standard page wrapper inside [MxShell]: top padding for the floating bar,
/// horizontal gutters that widen on desktop.
class MxPage extends StatelessWidget {
  const MxPage({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth = 1240,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final gutter = width >= 1440 ? 88.0 : (width >= 1024 ? 56.0 : 20.0);

    return Container(
      color: backgroundColor ?? Colors.transparent,
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth + gutter * 2),
          child: Padding(
            padding: padding ?? EdgeInsets.symmetric(horizontal: gutter),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Standard section vertical padding, condensed on phones so long pages do
/// not feel oversized. Desktop keeps the airy editorial rhythm.
EdgeInsets mxSectionPadding(
  BuildContext context, {
  double large = 84,
  double small = 56,
}) {
  final w = MediaQuery.of(context).size.width;
  return EdgeInsets.symmetric(vertical: w >= 1024 ? large : small);
}

/// Section header — overline + title + optional body.
class MxSectionHeader extends StatelessWidget {
  const MxSectionHeader({
    super.key,
    required this.overline,
    required this.title,
    this.body,
    this.alignLeft = false,
    this.tone = 'light',
  });

  final String overline;
  final String title;
  final String? body;
  final bool alignLeft;
  final String tone; // 'light' | 'dark' | 'cream'

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDark = tone == 'dark';
    final overlineColor = isDark ? MxColors.mossSoft : MxColors.earth;
    final titleColor = isDark ? MxColors.cream : MxColors.charcoal;
    final bodyColor = isDark
        ? MxColors.cream.withValues(alpha: 0.8)
        : MxColors.charcoalSoft;

    return Column(
      crossAxisAlignment: alignLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.center,
      children: [
        Text(
          overline.toUpperCase(),
          style: MxType.overline(color: overlineColor),
        ),
        const SizedBox(height: 14),
        Text(
          title,
          textAlign: alignLeft ? TextAlign.left : TextAlign.center,
          style: MxType.h1(width, color: titleColor),
        ),
        if (body != null) ...[
          const SizedBox(height: 18),
          Text(
            body!,
            textAlign: alignLeft ? TextAlign.left : TextAlign.center,
            style: MxType.body(width, color: bodyColor),
          ),
        ],
      ],
    );
  }
}

/// A soft, rounded raised panel.
class MxPanel extends StatelessWidget {
  const MxPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.color = MxColors.creamSoft,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line.withValues(alpha: 0.6)),
      ),
      child: child,
    );
  }
}
