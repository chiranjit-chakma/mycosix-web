import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../state/products_controller.dart';
import '../../widgets/page.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shell.dart';

class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  String _category = 'All';

  static const _categories = ['All', 'Fresh', 'Dried', 'Preserved'];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final products = context.watch<ProductsController>();
    final all = products.products;
    final filtered = _category == 'All'
        ? all
        : all.where((p) => p.category == _category).toList();

    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('THE SHOP'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 12),
                Text('Fresh from the grow room', style: MxType.h1(width)),
                const SizedBox(height: 14),
                Text(
                  'Every pack is harvested to order. When it is gone, it is gone — '
                  'the next harvest is on its way.',
                  style: MxType.body(width),
                ),
                const SizedBox(height: 32),
                // Category filter chips
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final c in _categories)
                      _FilterChip(
                        label: c,
                        selected: _category == c,
                        onTap: () => setState(() => _category = c),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          if (!products.loaded)
            MxPage(
              child: SizedBox(
                height: 260,
                child: Center(
                  child: CircularProgressIndicator(
                    color: MxColors.moss,
                    strokeWidth: 2.5,
                  ),
                ),
              ),
            )
          else if (filtered.isEmpty)
            MxPage(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const Icon(
                      Icons.inbox_outlined,
                      size: 40,
                      color: MxColors.stoneLight,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'No products in this category yet.',
                      style: MxType.bodySm(),
                    ),
                  ],
                ),
              ),
            )
          else
            MxPage(child: ProductGrid(products: filtered, spacing: 22)),
          const SizedBox(height: 60),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? MxColors.forest : MxColors.creamSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? MxColors.forest : MxColors.line),
        ),
        child: Text(
          label,
          style: MxType.label(
            color: selected ? Colors.white : MxColors.charcoalSoft,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
