import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/product.dart';
import '../admin_widgets.dart';

/// Inventory: keep stock levels accurate in real time. Unavailable products
/// stay here so they can be restocked, but they are not offered in the shop.
class InventorySection extends StatefulWidget {
  const InventorySection({super.key});

  @override
  State<InventorySection> createState() => _InventorySectionState();
}

class _InventorySectionState extends State<InventorySection> {
  bool _onlyLow = false;

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Inventory',
            subtitle:
                'Every adjustment writes straight to Firestore and is '
                'what customers and the trusted order backend see.',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  size: 16,
                  color: MxColors.warn,
                ),
                const SizedBox(width: 6),
                Text('low = <= 3', style: MxType.bodyXs(color: MxColors.stone)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Fb.products.orderBy('sortKey').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return StateNote(
                  icon: Icons.error_outline_rounded,
                  text: 'Products could not be loaded.',
                  detail: Fb.friendlyMessage(snap.error!),
                  tone: StateTone.danger,
                );
              }
              if (!snap.hasData) {
                return const LoadingNote(label: 'Loading inventory...');
              }
              final products = [
                for (final d in snap.data!.docs) productFromDoc(d),
              ];
              final shown = _onlyLow
                  ? products.where((p) => p.available && p.stock <= 3).toList()
                  : products;
              if (shown.isEmpty) {
                return StateNote(
                  icon: Icons.warehouse_outlined,
                  text: _onlyLow
                      ? 'Nothing is running low.'
                      : 'No products in the catalogue yet.',
                  detail: 'Add products from the Products section.',
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_onlyLow)
                    TextButton.icon(
                      onPressed: () => setState(() => _onlyLow = false),
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
                      label: const Text('Show all products'),
                    ),
                  const SizedBox(height: 2),
                  for (final p in shown) _row(p),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _row(Product p) {
    final low = p.available && p.stock <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: p.available
            ? MxColors.creamSoft
            : MxColors.oyster.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(
          color: low
              ? MxColors.warn.withValues(alpha: 0.5)
              : p.available
              ? MxColors.line
              : MxColors.stoneLight.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.name}${p.weight.isEmpty ? '' : ' (${p.weight})'}',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  p.available
                      ? (low ? 'LOW - restock soon' : 'In stock and on sale')
                      : 'Hidden from the shop (unavailable)',
                  style: MxType.bodyXs(
                    color: !p.available
                        ? MxColors.stone
                        : low
                        ? MxColors.warn
                        : MxColors.ok,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'One less',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.remove_circle_outline_rounded, size: 20),
            onPressed: p.stock <= 0 ? null : () => _adjust(p, p.stock - 1),
          ),
          InkWell(
            onTap: () => _setExact(p),
            borderRadius: BorderRadius.circular(MxRadius.sm),
            child: Container(
              width: 56,
              padding: const EdgeInsets.symmetric(vertical: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: MxColors.cream,
                borderRadius: BorderRadius.circular(MxRadius.sm),
                border: Border.all(color: MxColors.line),
              ),
              child: Text(
                '${p.stock}',
                style: MxType.bodySm(
                  color: MxColors.forest,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'One more',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.add_circle_outline_rounded, size: 20),
            onPressed: () => _adjust(p, p.stock + 1),
          ),
        ],
      ),
    );
  }

  Future<void> _adjust(Product p, int next) async {
    if (next < 0) return;
    try {
      await Fb.products.doc(p.id).set({
        'stock': next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Fb.friendlyMessage(e))));
    }
  }

  Future<void> _setExact(Product p) async {
    final controller = TextEditingController(text: '${p.stock}');
    final next = await showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Set stock for ${p.name}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(labelText: 'Units in stock'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              Navigator.pop(context, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (next != null && next >= 0) {
      await _adjust(p, next);
    }
  }
}
