import 'package:flutter/material.dart';

import '../config/mx_colors.dart';

/// The floating "back to top" circle: forest-to-moss gradient, soft shadow,
/// gentle ripple — reads as premium without shouting. Shared by the browser
/// page shell and the installed PWA's paging shell.
class MxBackToTopButton extends StatelessWidget {
  const MxBackToTopButton({super.key, required this.onTap});

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
