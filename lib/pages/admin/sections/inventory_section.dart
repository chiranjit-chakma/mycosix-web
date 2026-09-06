import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/admin_logs.dart';
import '../../../firebase/fb.dart';
import '../../../models/inventory_movement.dart';
import '../../../models/product.dart';
import '../../../state/auth_controller.dart';
import '../admin_widgets.dart';

/// Inventory: keep stock levels accurate in real time. Unavailable products
/// stay here so they can be restocked, but they are not offered in the shop.
/// Every adjustment is written straight to Firestore AND logged as an
/// [InventoryMovement] so the team can audit who changed what and when.
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
                'Live stock levels - every change writes to Firestore and is '
                'logged as a movement for the audit trail.',
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
              return _stockPanel(context, products);
            },
          ),
          const SizedBox(height: 26),
          const SectionHeader(
            title: 'Stock movements',
            subtitle:
                'The audit trail: every stock change, with the product, the '
                'change, who made it and when.',
          ),
          const SizedBox(height: 10),
          _MovementLog(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _stockPanel(BuildContext context, List<Product> products) {
    final units = products.fold<int>(0, (acc, p) => acc + p.stock);
    final availableValue = products
        .where((p) => p.available)
        .fold<double>(0, (acc, p) => acc + p.price * p.stock);
    final low = products.where((p) => p.available && p.stock <= 3).length;
    final unavailable = products.where((p) => !p.available).length;
    final shown = _onlyLow
        ? products.where((p) => p.available && p.stock <= 3).toList()
        : products;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stats([
          _MiniStat(
            label: 'Units in stock',
            value: '$units',
            icon: Icons.category_outlined,
            accent: MxColors.moss,
          ),
          _MiniStat(
            label: 'Stock value (on-sale)',
            value: rupees(availableValue),
            icon: Icons.payments_outlined,
            accent: MxColors.ok,
          ),
          _MiniStat(
            label: 'Low stock (<= 3)',
            value: '$low',
            icon: Icons.priority_high_rounded,
            accent: MxColors.warn,
          ),
          _MiniStat(
            label: 'Unavailable',
            value: '$unavailable',
            icon: Icons.block_outlined,
            accent: MxColors.danger,
          ),
        ]),
        const SizedBox(height: 6),
        if (_onlyLow)
          TextButton.icon(
            onPressed: () => setState(() => _onlyLow = false),
            icon: const Icon(Icons.filter_alt_off_rounded, size: 17),
            label: const Text('Show all products'),
          ),
        if (shown.isEmpty)
          StateNote(
            icon: Icons.warehouse_outlined,
            text: _onlyLow ? 'Nothing is running low.' : 'No products yet.',
            detail: 'Add products from the Products section.',
          )
        else
          for (final p in shown) _row(p),
      ],
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
                  productLabel(p),
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
    final previous = p.stock;
    try {
      await Fb.products.doc(p.id).set({
        'stock': next,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      final actor = _actorEmail();
      await logStockChange(
        productId: p.id,
        productLabel: productLabel(p),
        type: InventoryMovementType.adjustment,
        previousStock: previous,
        newStock: next,
        recordedByEmail: actor,
      );
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
        title: Text('Set stock for ${productLabel(p)}'),
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
    if (next != null && next >= 0 && next != p.stock) {
      await _adjust(p, next);
    }
  }

  String? _actorEmail() => context.read<AuthController>().user?.email;
}

/// Shared product display label used by inventory rows and the movement log.
String productLabel(Product p) =>
    '${p.name}${p.weight.isEmpty ? '' : ' (${p.weight})'}';

/// Compact responsive stat cards (mirror of the dashboard card grid).
class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.accent,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(MxRadius.sm),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: MxType.h4(color: MxColors.charcoal)),
                Text(label, style: MxType.bodyXs(color: MxColors.stone)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _stats(List<_MiniStat> cards) {
  return LayoutBuilder(
    builder: (context, constraints) {
      final w = constraints.maxWidth;
      final cols = w >= 980 ? 4 : w >= 560 ? 2 : 1;
      final rows = <Widget>[];
      for (var i = 0; i < cards.length; i += cols) {
        final chunk = cards.sublist(i, (i + cols).clamp(0, cards.length));
        rows.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                for (var j = 0; j < chunk.length; j++) ...[
                  Expanded(child: chunk[j]),
                  if (j != chunk.length - 1) const SizedBox(width: 10),
                ],
              ],
            ),
          ),
        );
      }
      return Column(children: rows);
    },
  );
}

class _MovementLog extends StatelessWidget {
  const _MovementLog();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.inventoryMovements
          .orderBy('recordedAt', descending: true)
          .limit(60)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return StateNote(
            icon: Icons.error_outline_rounded,
            text: 'Movements could not be loaded.',
            detail: Fb.friendlyMessage(snap.error!),
            tone: StateTone.danger,
          );
        }
        if (!snap.hasData) {
          return const LoadingNote(label: 'Loading movements...');
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const StateNote(
            icon: Icons.history_rounded,
            text: 'No stock movements recorded yet.',
            detail:
                'Every stock change you make in this section will appear here '
                'with who made it and when.',
          );
        }
        final movements = <InventoryMovement>[];
        for (final d in docs) {
          final m = d.data();
          movements.add(
            InventoryMovement.fromMap(m, id: d.id, recordedAt: fireTs(m['recordedAt'])),
          );
        }
        return Column(
          children: [
            for (final m in movements)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MxColors.creamSoft,
                  borderRadius: BorderRadius.circular(MxRadius.md),
                  border: Border.all(color: MxColors.line),
                ),
                child: Row(
                  children: [
                    Icon(
                      m.delta >= 0
                          ? Icons.add_circle_outline_rounded
                          : Icons.remove_circle_outline_rounded,
                      size: 18,
                      color: m.delta >= 0 ? MxColors.ok : MxColors.warn,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            m.productName,
                            style: MxType.bodySm(
                              color: MxColors.charcoal,
                              weight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${m.movementType.label}  |  '
                            '${m.previousStock} -> ${m.newStock}'
                            '${(m.note == null || m.note!.isEmpty) ? '' : '  |  ${m.note}'}',
                            style: MxType.bodyXs(color: MxColors.stone),
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          m.delta >= 0 ? '+${m.delta}' : '${m.delta}',
                          style: MxType.bodySm(
                            color: m.delta >= 0 ? MxColors.ok : MxColors.warn,
                            weight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          m.recordedByEmail == null || m.recordedByEmail!.isEmpty
                              ? shortWhen(m.recordedAt)
                              : '${m.recordedByEmail} · ${shortWhen(m.recordedAt)}',
                          style: MxType.bodyXs(color: MxColors.stone),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}
