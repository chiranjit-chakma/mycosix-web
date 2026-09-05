import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../models/product.dart';
import '../router/routes.dart';
import '../state/cart_controller.dart';
import '../utils/money.dart';
import 'mx_image.dart';

/// Builds a responsive product grid whose tiles are sized to the real card
/// height (4:3 image + text block), so nothing clips on phones or tablets.
class ProductGrid extends StatelessWidget {
  const ProductGrid({super.key, required this.products, this.spacing = 20});

  final List<Product> products;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cols = constraints.maxWidth >= 1180
            ? 4
            : (constraints.maxWidth >= 840
                  ? 3
                  : (constraints.maxWidth >= 320 ? 2 : 1));
        final tileWidth = (constraints.maxWidth - spacing * (cols - 1)) / cols;
        return GridView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: cols,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            mainAxisExtent: productTileExtent(tileWidth),
          ),
          children: [
            for (final p in products)
              ProductCard(product: p, compact: tileWidth < 320),
          ],
        );
      },
    );
  }
}

/// Height of a [ProductCard] tile for a given [width]: the 4:3 image plus the
/// text block below it, with a little slack so nothing ever overflows.
double productTileExtent(double width) {
  final compact = width < 320;
  final image = (width - 2) * 3 / 4; // 4:3 image inside the card border
  final chrome = compact ? 130.0 : 142.0; // paddings + 2 lines of name + meta
  return image + chrome + 6;
}

/// Premium product card — image, category, name, price, quick add.
class ProductCard extends StatefulWidget {
  const ProductCard({super.key, required this.product, this.compact = false});

  final Product product;
  final bool compact;

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  bool _hovered = false;
  bool _focused = false;

  void _open(BuildContext context) {
    Navigator.of(context)
        .pushNamed(Routes.product, arguments: widget.product.id);
  }

  /// Activates the card from the keyboard (Enter or Space while focused).
  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space)) {
      _open(context);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final compact = widget.compact;
    final width = MediaQuery.of(context).size.width;
    final cart = context.watch<CartController>();
    final qty = cart.quantityOf(product.id);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => _open(context),
        // The card itself is a button: it sits in the Tab order, shows a focus
        // ring, and announces itself to screen readers. Space/Enter activate.
        child: Focus(
          onFocusChange: (focused) => setState(() => _focused = focused),
          onKeyEvent: _handleKey,
          child: Semantics(
            button: true,
            label: '${product.name}, ${product.weight}',
            hint: 'Opens product details',
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOut,
              transform: Matrix4.identity()
                ..setTranslationRaw(0, _hovered && width >= 768 ? -6 : 0, 0),
              decoration: BoxDecoration(
                color: MxColors.creamSoft,
                borderRadius: BorderRadius.circular(MxRadius.lg),
                border: Border.all(
                  color: (_hovered || _focused)
                      ? MxColors.glowDeep.withValues(alpha: 0.8)
                      : MxColors.line,
                  width: (_hovered || _focused) ? 1.6 : 1,
                ),
                boxShadow: _hovered
                    ? [
                        BoxShadow(
                          color: MxColors.glow.withValues(alpha: 0.35),
                          blurRadius: 28,
                          offset: const Offset(0, 14),
                        ),
                      ]
                    : const [
                        BoxShadow(color: Colors.transparent, blurRadius: 0),
                      ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Image
                  Stack(
                    children: [
                      AspectRatio(
                        aspectRatio: 4 / 3,
                        child: MxImage(
                          asset: product.image,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(MxRadius.lg - 2),
                          ),
                        ),
                      ),
                      // Category chip
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: MxColors.cream.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            product.category.toUpperCase(),
                            style: MxType.label(
                              color: MxColors.moss,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      // Out of stock badge
                      if (!product.inStock)
                        Positioned.fill(
                          child: Container(
                            decoration: BoxDecoration(
                              color: MxColors.cream.withValues(alpha: 0.72),
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(MxRadius.lg - 2),
                              ),
                            ),
                            child: Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: MxColors.charcoal,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Currently unavailable',
                                  style: MxType.label(color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      compact ? 12 : 16,
                      compact ? 10 : 14,
                      compact ? 12 : 16,
                      compact ? 12 : 16,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: MxType.h4(color: MxColors.charcoal),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${product.weight} · ${product.variant}',
                          style: MxType.bodyXs(color: MxColors.stone),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Text(
                              formatRupees(product.price),
                              style: compact
                                  ? const TextStyle(
                                      fontFamily: 'Fraunces',
                                      fontSize: 17,
                                      height: 1.1,
                                      fontWeight: FontWeight.w700,
                                      color: MxColors.forest,
                                    )
                                  : MxType.h3(color: MxColors.forest),
                            ),
                            const Spacer(),
                            if (product.inStock)
                              _AddButton(
                                product: product,
                                qty: qty,
                                compact: compact,
                              )
                            else
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: MxColors.creamDeep,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Unavailable',
                                  style: MxType.label(color: MxColors.stone),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.product,
    required this.qty,
    this.compact = false,
  });

  final Product product;
  final int qty;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();

    if (qty == 0) {
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
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 14,
            vertical: compact ? 8 : 9,
          ),
          decoration: BoxDecoration(
            color: MxColors.glow,
            borderRadius: BorderRadius.circular(999),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add_rounded, size: 16, color: MxColors.forest),
              SizedBox(width: 4),
              Text(
                'Add',
                style: TextStyle(
                  fontFamily: 'Manrope',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: MxColors.forest,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Quantity stepper when already in cart.
    final maxFor = cart.maxQuantityOf(product);
    return Container(
      decoration: BoxDecoration(
        color: MxColors.mossTint,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: MxColors.moss.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperBtn(
            label: 'Decrease quantity of ${product.name}',
            icon: Icons.remove_rounded,
            onTap: () => cart.decrement(product),
          ),
          Text(
            '$qty',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: MxColors.forest,
            ),
          ),
          _StepperBtn(
            label: 'Increase quantity of ${product.name}',
            icon: Icons.add_rounded,
            enabled: qty < maxFor,
            onTap: () => cart.increment(product),
          ),
        ],
      ),
    );
  }
}

class _StepperBtn extends StatelessWidget {
  const _StepperBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final color = enabled ? MxColors.moss : MxColors.stoneLight;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.all(7),
          child: Icon(icon, size: 15, color: color),
        ),
      ),
    );
  }
}
