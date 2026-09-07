import 'package:flutter/material.dart';

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
  });

  final String productName;
  final String productId;

  @override
  Widget build(BuildContext context) {
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
