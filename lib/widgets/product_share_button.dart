import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../services/share_service.dart';

/// "Share" control for one product page.
///
/// Tapping it shares that product's own web page so customers can pass a pack
/// to friends and family: the browser opens its native share sheet where
/// available (phone share, WhatsApp, email, a desktop OS picker) and otherwise
/// copies the product link to the clipboard with a short confirmation.
class ProductShareButton extends StatelessWidget {
  const ProductShareButton({
    super.key,
    required this.productName,
    required this.productId,
    this.compact = false,
  });

  final String productName;
  final String productId;

  /// Small round overlay style for the product image.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Semantics(
        button: true,
        label: 'Share this product',
        child: InkWell(
          onTap: () => _share(context),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: MxColors.cream.withValues(alpha: 0.92),
              shape: BoxShape.circle,
              border: Border.all(color: MxColors.line),
              boxShadow: [
                BoxShadow(
                  color: MxColors.charcoal.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: const Icon(
              Icons.share_outlined,
              size: 20,
              color: MxColors.charcoal,
            ),
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: () => _share(context),
      icon: const Icon(Icons.share_outlined, size: 17),
      label: const Text('Share'),
    );
  }

  Future<void> _share(BuildContext context) async {
    final outcome = await shareProductLink(
      url: productShareUrl(productId),
      title: productName,
    );
    // A native share sheet was shown (or sharing failed silently): the system
    // already handled it, so there is nothing to announce here.
    if (outcome != ShareOutcome.copied) return;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text(
            'Link copied - paste it anywhere to share this product',
          ),
          duration: Duration(seconds: 3),
        ),
      );
  }
}
