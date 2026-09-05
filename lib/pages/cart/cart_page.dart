import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../models/cart_item.dart';
import '../../router/routes.dart';
import '../../state/cart_controller.dart';
import '../../utils/money.dart';
import '../../widgets/mx_image.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

class CartPage extends StatelessWidget {
  const CartPage({super.key});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cart = context.watch<CartController>();
    final lines = cart.lines;

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR CART'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 12),
                Text('Your cart', style: MxType.h1(width)),
                const SizedBox(height: 8),
                if (lines.isNotEmpty)
                  Text(
                    '${cart.lineCount} item${cart.lineCount == 1 ? '' : 's'} · ${cart.totalQuantity} total',
                    style: MxType.bodySm(color: MxColors.stone),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (cart.isEmpty)
            _EmptyCart()
          else
            MxPage(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final desktop = constraints.maxWidth >= 900;
                  return desktop
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 7, child: _LineList(lines: lines)),
                            const SizedBox(width: 36),
                            Expanded(flex: 4, child: _SummaryCard()),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _LineList(lines: lines),
                            const SizedBox(height: 24),
                            _SummaryCard(),
                          ],
                        );
                },
              ),
            ),
          const SizedBox(height: 64),
        ],
      ),
    );
  }
}

class _EmptyCart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return MxPage(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 72),
        child: Column(
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: MxColors.mossTint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                size: 38,
                color: MxColors.moss,
              ),
            ),
            const SizedBox(height: 24),
            Text('Your cart is empty', style: MxType.h2(width)),
            const SizedBox(height: 10),
            Text(
              'Fresh oyster mushrooms are a click away.',
              style: MxType.bodySm(color: MxColors.stone),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
              label: const Text('Continue Shopping'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LineList extends StatelessWidget {
  const _LineList({required this.lines});

  final List<CartItem> lines;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < lines.length; i++) ...[
          _LineRow(item: lines[i]),
          if (i < lines.length - 1)
            const Divider(color: MxColors.line, height: 28),
        ],
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final cart = context.read<CartController>();
    final product = item.product;
    final compact = width < 768;
    final thumb = compact ? 68.0 : 96.0;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 14 : 16),
          child: MxImage(
            asset: product.image,
            width: thumb,
            height: thumb,
            fit: BoxFit.cover,
          ),
        ),
        SizedBox(width: compact ? 14 : 18),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () =>
                          Navigator.of(context)
                              .pushNamed(Routes.product, arguments: product.id),
                      child: Text(
                        product.name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: MxType.h4(color: MxColors.charcoal),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: () => cart.remove(product),
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: MxColors.stoneLight,
                    ),
                    tooltip: 'Remove',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 38,
                      minHeight: 38,
                    ),
                    splashRadius: 19,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${product.weight} · ${formatRupees(product.price)} each',
                style: MxType.bodyXs(color: MxColors.stone),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _MiniStepper(item: item),
                  const Spacer(),
                  Text(
                    formatRupees(item.lineTotal),
                    style: MxType.h4(color: MxColors.forest),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MiniStepper extends StatelessWidget {
  const _MiniStepper({required this.item});

  final CartItem item;

  @override
  Widget build(BuildContext context) {
    final cart = context.read<CartController>();
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
            onPressed: () => cart.decrement(item.product),
            tooltip: 'Decrease quantity',
            icon: const Icon(Icons.remove_rounded, size: 15),
            color: MxColors.moss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            splashRadius: 17,
          ),
          Text(
            '${item.quantity}',
            style: const TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: MxColors.forest,
            ),
          ),
          IconButton(
            onPressed:
                cart.maxQuantityOf(item.product) > 0 &&
                    item.quantity >= cart.maxQuantityOf(item.product)
                ? null
                : () => cart.increment(item.product),
            tooltip:
                cart.maxQuantityOf(item.product) > 0 &&
                    item.quantity >= cart.maxQuantityOf(item.product)
                ? 'Quantity limit reached'
                : 'Increase quantity',
            icon: const Icon(Icons.add_rounded, size: 15),
            color: MxColors.moss,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
            splashRadius: 17,
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cart = context.watch<CartController>();
    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Order summary', style: MxType.h3(color: MxColors.charcoal)),
          const SizedBox(height: 20),
          _SummaryRow(label: 'Subtotal', value: formatRupees(cart.subtotal)),
          const SizedBox(height: 10),
          _SummaryRow(
            label: 'Delivery',
            value: cart.deliveryFee > 0
                ? formatRupees(cart.deliveryFee)
                : 'Free',
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: MxColors.line, height: 1),
          ),
          _SummaryRow(
            label: 'Total',
            value: formatRupees(cart.total),
            bold: true,
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pushNamed(Routes.checkout),
              icon: const Icon(Icons.lock_outline_rounded, size: 17),
              label: const Text('Checkout'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pushNamed(Routes.shop),
              child: const Text('Continue Shopping'),
            ),
          ),
          const SizedBox(height: 12),
          const Row(
            children: [
              Icon(
                Icons.verified_user_outlined,
                size: 15,
                color: MxColors.stone,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'No account needed. Order on WhatsApp.',
                  style: TextStyle(
                    fontFamily: 'Manrope',
                    fontSize: 12.5,
                    color: MxColors.stone,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: MxType.bodySm(
            color: MxColors.charcoalSoft,
            weight: bold ? FontWeight.w700 : FontWeight.w400,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: MxType.bodySm(
            color: MxColors.forest,
            weight: bold ? FontWeight.w800 : FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
