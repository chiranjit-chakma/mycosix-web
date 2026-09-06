import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_config.dart';
import '../../config/mx_type.dart';
import '../../models/product.dart';
import '../../state/products_controller.dart';
import '../../router/routes.dart';
import '../../state/cart_controller.dart';
import '../../utils/money.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/product_card.dart';
import '../../widgets/product_video.dart';
import '../../widgets/products_scope.dart';
import '../../widgets/shell.dart';

class ProductPage extends StatefulWidget {
  const ProductPage({super.key, required this.productId});

  final String productId;

  @override
  State<ProductPage> createState() => _ProductPageState();
}

class _ProductPageState extends State<ProductPage> {
  int _quantity = 1;
  int _activeImage = 0;
  bool _loading = true;
  Product? _product;

  @override
  void initState() {
    super.initState();
    // Stay in step with the live catalog: if the owner edits a product while a
    // customer is viewing it, the page updates in place (price, stock, etc.).
    context.read<ProductsController>().addListener(_refreshFromCatalog);
    _load();
  }

  void _refreshFromCatalog() {
    if (!mounted) return;
    final catalog = context.read<ProductsController>().products;
    Product? fresh;
    for (final p in catalog) {
      if (p.id == widget.productId) {
        fresh = p;
        break;
      }
    }
    if (fresh == null) return; // no longer in the catalogue — keep last view
    final p = fresh; // non-null local: promotions do not reach closures
    final cur = _product;
    final same = cur != null &&
        cur.id == p.id &&
        cur.price == p.price &&
        cur.stock == p.stock &&
        cur.available == p.available &&
        cur.name == p.name &&
        cur.weight == p.weight &&
        cur.image == p.image &&
        cur.description == p.description;
    if (same) return;
    setState(() {
      _product = p;
      if (_quantity > math.max(1, p.stock)) {
        _quantity = math.max(1, p.stock);
      }
    });
  }

  @override
  void dispose() {
    context.read<ProductsController>().removeListener(_refreshFromCatalog);
    super.dispose();
  }

  Future<void> _load() async {
    final products = context.products()!;
    final p = await products.byId(widget.productId);
    if (!mounted) return;
    setState(() {
      _product = p;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final desktop = width >= 1024;

    if (_loading) {
      return MxShell(
        child: SizedBox(
          height: MediaQuery.of(context).size.height,
          child: const Center(
            child: CircularProgressIndicator(
              color: MxColors.moss,
              strokeWidth: 2.5,
            ),
          ),
        ),
      );
    }

    final product = _product;
    if (product == null) {
      return MxShell(
        child: MxPage(
          padding: const EdgeInsets.symmetric(vertical: 160),
          child: Column(
            children: [
              Text('Product not found', style: MxType.h1(width)),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
                child: const Text('Back to shop'),
              ),
            ],
          ),
        ),
      );
    }

    final gallery = product.gallery.isNotEmpty
        ? product.gallery
        : [product.image];

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            child: desktop
                ? Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gallery
                      Expanded(
                        flex: 6,
                        child: _Gallery(
                          gallery: gallery,
                          activeImage: _activeImage,
                          onSelect: (i) => setState(() => _activeImage = i),
                        ),
                      ),
                      const SizedBox(width: 56),
                      // Info
                      Expanded(
                        flex: 5,
                        child: _ProductInfo(
                          product: product,
                          quantity: _quantity,
                          onQuantity: (q) => setState(() => _quantity = q),
                        ),
                      ),
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Gallery(
                        gallery: gallery,
                        activeImage: _activeImage,
                        onSelect: (i) => setState(() => _activeImage = i),
                      ),
                      const SizedBox(height: 28),
                      _ProductInfo(
                        product: product,
                        quantity: _quantity,
                        onQuantity: (q) => setState(() => _quantity = q),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 72),
          // You may also like
          _Related(productId: product.id),
          const SizedBox(height: 48),
        ],
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  const _Gallery({
    required this.gallery,
    required this.activeImage,
    required this.onSelect,
  });

  final List<String> gallery;
  final int activeImage;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AspectRatio(
          aspectRatio: 4 / 3.2,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(MxRadius.lg),
            child: MxImage(
              asset: gallery[activeImage.clamp(0, gallery.length - 1)],
              fit: BoxFit.cover,
            ),
          ),
        ),
        if (gallery.length > 1) ...[
          const SizedBox(height: 14),
          Row(
            children: [
              for (var i = 0; i < gallery.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: InkWell(
                    onTap: () => onSelect(i),
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 68,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: activeImage == i
                              ? MxColors.moss
                              : MxColors.line,
                          width: activeImage == i ? 2 : 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11),
                        child: MxImage(asset: gallery[i], fit: BoxFit.cover),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _ProductInfo extends StatelessWidget {
  const _ProductInfo({
    required this.product,
    required this.quantity,
    required this.onQuantity,
  });

  final Product product;
  final int quantity;
  final ValueChanged<int> onQuantity;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cart = context.watch<CartController>();
    final inCart = cart.quantityOf(product.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(product.category.toUpperCase(), style: MxType.overline()),
        const SizedBox(height: 10),
        Text(product.name, style: MxType.h1(width)),
        const SizedBox(height: 10),
        Text(
          '${product.weight} · ${product.variant}',
          style: MxType.bodySm(color: MxColors.stone),
        ),
        const SizedBox(height: 18),
        Text(
          formatRupees(product.price),
          style: MxType.displayAlt(width, color: MxColors.moss),
        ),
        const SizedBox(height: 24),
        Text('About this pack', style: MxType.label(color: MxColors.forest)),
        const SizedBox(height: 8),
        Text(product.description, style: MxType.body(width)),
        ProductVideoButton(product: product),
        const SizedBox(height: 28),
        if (product.inStock) ...[
          Row(
            children: [
              _QtyStepper(
                quantity: quantity,
                max: cart.maxQuantityOf(product),
                onChange: onQuantity,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: _AddToCartButton(product: product, quantity: quantity),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (inCart > 0)
            Text(
              '$inCart in your cart already',
              style: MxType.label(color: MxColors.ok),
            ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(
                Icons.local_shipping_outlined,
                size: 16,
                color: MxColors.stone,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  '${MxConfig.orderLeadTime} delivery in ${MxConfig.serviceArea}',
                  style: const TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 13,
                    color: MxColors.stone,
                  ),
                ),
              ),
            ],
          ),
        ] else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: MxColors.warnSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              'Currently unavailable — the next harvest will be here soon.',
              style: MxType.bodySm(
                color: MxColors.warn,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _QtyStepper extends StatelessWidget {
  const _QtyStepper({
    required this.quantity,
    required this.max,
    required this.onChange,
  });

  final int quantity;
  final int max;
  final ValueChanged<int> onChange;

  @override
  Widget build(BuildContext context) {
    final atMax = max > 0 && quantity >= max;
    return Container(
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            onPressed: quantity > 1 ? () => onChange(quantity - 1) : null,
            icon: const Icon(Icons.remove_rounded, size: 18),
            color: MxColors.moss,
            tooltip: 'Decrease quantity',
          ),
          Text(
            '$quantity',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: MxColors.forest,
            ),
          ),
          IconButton(
            onPressed: atMax ? null : () => onChange(quantity + 1),
            icon: const Icon(Icons.add_rounded, size: 18),
            color: MxColors.moss,
            tooltip: atMax ? 'Maximum quantity reached' : 'Increase quantity',
          ),
        ],
      ),
    );
  }
}

class _AddToCartButton extends StatelessWidget {
  const _AddToCartButton({required this.product, required this.quantity});

  final Product product;
  final int quantity;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
    final cap = cart.maxQuantityOf(product);
    final remaining = cap - cart.quantityOf(product.id);

    void announce(String message) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
            action: SnackBarAction(
              label: 'View Cart',
              textColor: MxColors.mossSoft,
              onPressed: () => Navigator.of(context).pushNamed(Routes.cart),
            ),
          ),
        );
    }

    void addToCart() {
      if (remaining <= 0) {
        announce(
          '${product.name} is already at its delivery limit in your cart.',
        );
        return;
      }
      final addQty = math.min(quantity, remaining);
      cart.add(product, quantity: addQty);
      announce('${product.name} × $addQty added to cart');
    }

    return ElevatedButton.icon(
      onPressed: addToCart,
      icon: const Icon(Icons.add_shopping_cart_rounded, size: 18),
      label: const Text('Add to Cart'),
    );
  }
}

class _Related extends StatelessWidget {
  const _Related({required this.productId});

  final String productId;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final products = context.watch<ProductsController>();
    final related = products.products
        .where((p) => p.id != productId)
        .take(4)
        .toList();
    if (related.isEmpty) return const SizedBox.shrink();

    return MxPage(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('You may also like', style: MxType.h2(width)),
          const SizedBox(height: 28),
          ProductGrid(products: related),
        ],
      ),
    );
  }
}
