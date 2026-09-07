import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../models/product.dart';
import '../../router/routes.dart';
import '../../state/cart_controller.dart';
import '../../state/customer_auth_controller.dart';
import '../../state/wishlist_controller.dart';
import '../../utils/money.dart';
import '../../widgets/account_locked.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/products_scope.dart';
import '../../widgets/shell.dart';
import '../../widgets/wishlist_heart.dart';

/// The signed-in customer's saved products.
///
/// Opened from the account page. Guests (or offline sessions) see an honest
/// locked state with sign-in actions — the page never pretends to hold data
/// it cannot read.
class WishlistPage extends StatelessWidget {
  const WishlistPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final auth = context.watch<CustomerAuthController>();
    final wishlist = context.watch<WishlistController>();

    final signedIn = auth.backendAvailable && auth.user != null;
    if (!signedIn) {
      return LockedAccountPage(
        title: 'Wishlist',
        icon: Icons.favorite_border_rounded,
        message:
            'Sign in to see the products you saved — they follow you across '
            'the website and the installed app.',
        returnRoute: Routes.wishlist,
      );
    }
    if (!wishlist.ready) {
      return MxShell(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 120),
            MxPage(
              maxWidth: 720,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('YOUR WISHLIST'.toUpperCase(), style: MxType.overline()),
                  const SizedBox(height: 12),
                  Text('Wishlist', style: MxType.h1(width)),
                  const SizedBox(height: 24),
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: CircularProgressIndicator(color: MxColors.moss),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Saved ids resolved against the live catalogue: only products that still
    // exist render; a stale id simply does not appear.
    final products = context.products();
    final catalog = products == null ? const <Product>[] : products.products;
    final byId = <String, Product>{for (final p in catalog) p.id: p};
    final ordered = <Product>[];
    for (final id in wishlist.ids) {
      final p = byId[id];
      if (p != null) ordered.add(p);
    }

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            maxWidth: 720,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR WISHLIST'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 12),
                Text('Wishlist', style: MxType.h1(width)),
                const SizedBox(height: 10),
                Text(
                  ordered.isEmpty
                      ? 'No saved products yet — tap the heart on any product '
                          'to keep it here.'
                      : '${ordered.length} saved '
                          '${ordered.length == 1 ? 'product' : 'products'}',
                  style: MxType.bodySm(color: MxColors.stone),
                ),
                const SizedBox(height: 28),
                if (ordered.isEmpty)
                  const _EmptyState()
                else
                  Column(
                    children: [
                      for (final p in ordered)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _WishlistRow(product: p),
                        ),
                    ],
                  ),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return MxPanel(
      child: Column(
        children: [
          const Icon(Icons.favorite_border_rounded,
              size: 34, color: MxColors.stone),
          const SizedBox(height: 12),
          Text(
            'Your wishlist is empty.\nBrowse the shop and tap the heart on '
            'anything you like.',
            textAlign: TextAlign.center,
            style: MxType.bodySm(color: MxColors.charcoalSoft),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
            style: FilledButton.styleFrom(
              backgroundColor: MxColors.forest,
              foregroundColor: Colors.white,
            ),
            child: const Text('Browse the shop'),
          ),
        ],
      ),
    );
  }
}

class _WishlistRow extends StatelessWidget {
  const _WishlistRow({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    final qty = cart.quantityOf(product.id);

    return Material(
      color: MxColors.creamSoft,
      borderRadius: BorderRadius.circular(MxRadius.md),
      child: InkWell(
        onTap: () => Navigator.of(context)
            .pushNamed(Routes.product, arguments: product.id),
        borderRadius: BorderRadius.circular(MxRadius.md),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(MxRadius.md),
            border: Border.all(color: MxColors.line),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  width: 74,
                  height: 74,
                  child: MxImage(asset: product.image, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${product.weight} · ${product.variant}',
                      style: MxType.bodyXs(color: MxColors.stone),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      formatRupees(product.price),
                      style: MxType.h4(color: MxColors.forest),
                    ),
                    if (!product.inStock) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Currently unavailable',
                        style: MxType.label(color: MxColors.danger),
                      ),
                    ],
                  ],
                ),
              ),
              if (product.inStock)
                _WishlistAddButton(product: product, qty: qty),
              WishlistHeartButton(
                productId: product.id,
                semanticLabel: 'Remove from wishlist',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WishlistAddButton extends StatelessWidget {
  const _WishlistAddButton({required this.product, required this.qty});

  final Product product;
  final int qty;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    return InkWell(
      onTap: () {
        cart.add(product);
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text('${product.name} added to cart'),
              duration: const Duration(seconds: 2),
            ),
          );
      },
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: qty > 0 ? MxColors.mossSoft : MxColors.glow,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              qty > 0 ? Icons.check_rounded : Icons.add_rounded,
              size: 16,
              color: qty > 0 ? MxColors.moss : MxColors.forest,
            ),
            const SizedBox(width: 4),
            Text(
              qty > 0 ? 'In cart' : 'Add',
              style: MxType.label(
                color: qty > 0 ? MxColors.moss : MxColors.forest,
                weight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
