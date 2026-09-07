import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/mx_colors.dart';
import '../router/routes.dart';
import '../state/wishlist_controller.dart';

/// Wishlist heart for one product.
///
/// Signed-in customers tap to save / unsave (state comes from the shared
/// [WishlistController], so a heart on a product card and the heart on that
/// product's page always agree). Guests tapping a heart get a clear
/// sign-in prompt — the product is remembered and saved the moment they
/// create an account or sign in. When the sign-in backend is unreachable the
/// tap explains that nothing can be saved right now.
///
/// Saving pops the icon in with an elastic bounce and fires a one-shot heart
/// burst around it — a small, finite animation, so widget tests stay
/// deterministic with fixed pumps.
class WishlistHeartButton extends StatefulWidget {
  const WishlistHeartButton({
    super.key,
    required this.productId,
    this.compact = false,
    this.semanticLabel,
  });

  final String productId;

  /// Small round overlay style for product cards.
  final bool compact;

  /// Override the accessibility label (e.g. "Remove from wishlist").
  final String? semanticLabel;

  @override
  State<WishlistHeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<WishlistHeartButton> {
  /// Baselines per product id, so a State reused by list recycling never fires
  /// a burst for the wrong product.
  String? _trackedProductId;
  bool _lastSaved = false;

  /// Increments on every transition into saved; the burst widget is keyed by
  /// it so each new save remounts the burst fresh (plays 0 → 1) instead of
  /// playing in reverse on the way out.
  int _burstId = 0;

  @override
  Widget build(BuildContext context) {
    final wishlist = context.watch<WishlistController>();
    final saved = wishlist.isFavorite(widget.productId);

    if (_trackedProductId != widget.productId) {
      _trackedProductId = widget.productId;
      _lastSaved = saved; // new product: baseline, no burst
    } else if (saved != _lastSaved) {
      _lastSaved = saved;
      if (saved) _burstId++;
    }

    final foreground = saved ? MxColors.danger : MxColors.charcoal;
    final label =
        widget.semanticLabel ??
        (saved ? 'Remove from wishlist' : 'Save to wishlist');

    // Elastic pop between the outline heart and the filled one.
    final icon = AnimatedSwitcher(
      duration: const Duration(milliseconds: 340),
      switchInCurve: Curves.elasticOut,
      switchOutCurve: Curves.easeOut,
      transitionBuilder: (child, animation) => ScaleTransition(
        scale: animation,
        child: FadeTransition(opacity: animation, child: child),
      ),
      child: Icon(
        saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        key: ValueKey<bool>(saved),
        size: widget.compact ? 20 : 22,
        color: foreground,
      ),
    );

    Widget button;
    if (widget.compact) {
      button = Semantics(
        button: true,
        label: label,
        child: InkWell(
          onTap: () => _onTap(context),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MxColors.cream.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(
                color: saved
                    ? MxColors.danger.withValues(alpha: 0.35)
                    : MxColors.line,
              ),
              boxShadow: [
                BoxShadow(
                  color: MxColors.charcoal.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(child: icon),
          ),
        ),
      );
    } else {
      button = IconButton(
        onPressed: () => _onTap(context),
        tooltip: label,
        icon: icon,
      );
    }

    // The heart watches [WishlistController], so a change elsewhere (another
    // card, the product page, another device) rebuilds it in step. The burst
    // overlay sits on top, transparent once its one-shot has finished.
    if (_burstId == 0) return button;
    final buttonSize = widget.compact ? 36.0 : 48.0;
    final burstSize = widget.compact ? 46.0 : 54.0;
    return SizedBox(
      width: math.max(buttonSize, burstSize),
      height: math.max(buttonSize, burstSize),
      child: Stack(
        alignment: Alignment.center,
        children: [
          button,
          Positioned.fill(
            child: IgnorePointer(
              child: _HeartBurst(
                key: ValueKey<int>(_burstId),
                size: burstSize,
                color: MxColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onTap(BuildContext context) async {
    final wishlist = context.read<WishlistController>();
    switch (wishlist.gate) {
      case WishlistGate.toggled:
        wishlist.toggle(widget.productId);
        return;
      case WishlistGate.offline:
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Sign-in is unavailable right now, so nothing can be saved. '
                'Please check your connection.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        return;
      case WishlistGate.needsSignIn:
        // Remember the intent so it saves on first sign-in.
        wishlist.rememberPendingSave(widget.productId);
        final go = await showDialog<_SignInChoice>(
          context: context,
          builder: (context) => const _SignInPrompt(),
        );
        if (!context.mounted || go == null) return;
        final request = ProfileRouteRequest(
          startMode: go == _SignInChoice.signIn
              ? AuthStartMode.signIn
              : AuthStartMode.register,
        );
        await Navigator.of(context).pushNamed(
          Routes.profile,
          arguments: request,
        );
        return;
    }
  }
}

enum _SignInChoice { signIn, create }

/// Polite gate shown to guests who tap a wishlist heart.
class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Save products to your Wishlist'),
      content: const Text(
        'Create a free MYCOSIX account (or sign in) to save this product — '
        'and find it again later, on any device.',
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _SignInChoice.signIn),
          child: const Text('Sign in'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _SignInChoice.create),
          style: FilledButton.styleFrom(
            backgroundColor: MxColors.forest,
            foregroundColor: Colors.white,
          ),
          child: const Text('Create account'),
        ),
      ],
    );
  }
}

/// One-shot heart burst: an expanding ring plus four little hearts that fly
/// outward. Plays 0 → 1 once when it mounts (each new save mounts a fresh
/// instance via the keyed parent) and sits invisible at rest.
class _HeartBurst extends StatelessWidget {
  const _HeartBurst({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      // A fresh Tween each build is fine: TweenAnimationBuilder only restarts
      // when the *end* changes, and it is always 1 here.
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOutCubic,
      builder: (context, v, _) {
        final opacity = (1 - v).clamp(0.0, 1.0);
        if (opacity <= 0.02) return const SizedBox.shrink();
        return CustomPaint(
          size: Size.square(size),
          painter: _HeartBurstPainter(progress: v, color: color),
        );
      },
    );
  }
}

class _HeartBurstPainter extends CustomPainter {
  _HeartBurstPainter({required this.progress, required this.color});

  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Expanding ring around the heart icon.
    final ringRadius = size.width * (0.14 + progress * 0.4);
    canvas.drawCircle(
      center,
      ringRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = color.withValues(alpha: (1 - progress) * 0.55),
    );

    // Four little hearts flying out along the diagonals.
    final sparkle = Paint()
      ..color = color.withValues(alpha: (1 - progress) * 0.8);
    final heart = _unitHeart();
    for (final angle in [
      math.pi / 4,
      3 * math.pi / 4,
      5 * math.pi / 4,
      7 * math.pi / 4,
    ]) {
      final dir = Offset(math.cos(angle), math.sin(angle));
      final distance = size.width * (0.2 + progress * 0.38);
      canvas
        ..save()
        ..translate(
          center.dx + dir.dx * distance,
          center.dy + dir.dy * distance,
        )
        ..scale(size.width * (0.12 + progress * 0.1))
        ..drawPath(heart, sparkle)
        ..restore();
    }
  }

  /// A 1×1 heart in the 0..1 box, tip pointing down.
  Path _unitHeart() {
    return Path()
      ..moveTo(0.5, 0.32)
      ..cubicTo(0.42, 0.12, 0.06, 0.12, 0.06, 0.34)
      ..cubicTo(0.06, 0.52, 0.22, 0.62, 0.5, 0.82)
      ..cubicTo(0.78, 0.62, 0.94, 0.52, 0.94, 0.34)
      ..cubicTo(0.94, 0.12, 0.58, 0.12, 0.5, 0.32)
      ..close();
  }

  @override
  bool shouldRepaint(_HeartBurstPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
