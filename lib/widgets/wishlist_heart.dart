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
class WishlistHeartButton extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final wishlist = context.watch<WishlistController>();
    final saved = wishlist.isFavorite(productId);

    final foreground = saved ? MxColors.danger : MxColors.charcoal;
    final label =
        semanticLabel ?? (saved ? 'Remove from wishlist' : 'Save to wishlist');

    Widget icon = Icon(
      saved ? Icons.favorite_rounded : Icons.favorite_border_rounded,
      size: compact ? 20 : 22,
      color: foreground,
    );

    Widget button;
    if (compact) {
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
    // card, the product page, another device) rebuilds it in step.
    return button;
  }

  Future<void> _onTap(BuildContext context) async {
    final wishlist = context.read<WishlistController>();
    switch (wishlist.gate) {
      case WishlistGate.toggled:
        wishlist.toggle(productId);
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
        wishlist.rememberPendingSave(productId);
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
