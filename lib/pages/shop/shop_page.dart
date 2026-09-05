import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../models/product.dart';
import '../../state/admin_reveal.dart';
import '../../state/products_controller.dart';
import '../../widgets/page.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shell.dart';

/// The shop: every product, searchable and filterable by category.
///
/// The search box is also the single covert way the owner summons the hidden
/// admin area — typing the exact summon phrase there (instead of a product
/// search) arms the admin sign-in and clears the box. See [AdminReveal].
class ShopPage extends StatefulWidget {
  const ShopPage({super.key});

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  String _category = 'All';
  String _query = '';
  final _search = TextEditingController();

  static const _categories = ['All', 'Fresh', 'Dried', 'Preserved'];

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // The owner summon phrase is matched here and never treated as a search.
    if (AdminReveal.shared.armFromSearchText(value)) {
      _search.clear();
      _query = '';
      setState(() {});
      return;
    }
    setState(() => _query = value);
  }

  List<Product> _visible(List<Product> all) {
    final q = _query.trim().toLowerCase();
    final out = <Product>[];
    for (final p in all) {
      if (_category != 'All' && p.category != _category) continue;
      if (q.isNotEmpty) {
        final hay = '${p.name} ${p.variant} ${p.category} ${p.weight} '
                '${p.description}'
            .toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(p);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final products = context.watch<ProductsController>();
    final all = products.products;
    final filtered = _visible(all);

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
                const SizedBox(height: 28),
                // Search across the whole catalogue.
                SizedBox(
                  width: double.infinity,
                  child: TextField(
                    controller: _search,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      hintText:
                          'Search the harvest, e.g. dried, powder, 250 g…',
                      hintStyle: MxType.bodySm(color: MxColors.stone),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: MxColors.moss,
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(
                                Icons.close_rounded,
                                color: MxColors.stone,
                              ),
                              onPressed: () {
                                _search.clear();
                                setState(() => _query = '');
                              },
                            ),
                      filled: true,
                      fillColor: MxColors.creamSoft,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 15,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MxRadius.md),
                        borderSide: const BorderSide(color: MxColors.line),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(MxRadius.md),
                        borderSide: const BorderSide(
                          color: MxColors.moss,
                          width: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
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
                      _query.trim().isEmpty
                          ? 'No products in this category yet.'
                          : 'No matches for “${_query.trim()}”.',
                      style: MxType.bodySm(),
                    ),
                    const SizedBox(height: 4),
                    if (_query.trim().isNotEmpty)
                      Text(
                        'Try a different word, or browse a category.',
                        style: MxType.bodyXs(color: MxColors.stone),
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
          border: Border.all(
            color: selected ? MxColors.forest : MxColors.line,
          ),
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
