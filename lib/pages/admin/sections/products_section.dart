import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/admin_logs.dart';
import '../../../firebase/fb.dart';
import '../../../models/inventory_movement.dart';
import '../../../models/product.dart';
import '../../../state/auth_controller.dart';
import '../../../util/product_image.dart';
import '../../../widgets/mx_image.dart';
import '../admin_widgets.dart';

/// Catalogue management. Every change is written straight to Firestore and is
/// authorised by the security rules (admin only). Prices, stock and
/// availability set here are what the shop + trusted order backend actually
/// use.
class ProductsSection extends StatefulWidget {
  const ProductsSection({super.key});

  @override
  State<ProductsSection> createState() => _ProductsSectionState();
}

enum _Scope { all, available, unavailable, lowStock }

class _ProductsSectionState extends State<ProductsSection> {
  _Scope _scope = _Scope.all;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(
            title: 'Products',
            subtitle:
                'The real catalogue - edit anything, changes go live '
                'immediately.',
            trailing: FilledButton.icon(
              onPressed: _openEditor,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add product'),
            ),
          ),
          const SizedBox(height: 14),
          _bar(),
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
                return const LoadingNote(label: 'Loading products...');
              }
              final products = [
                for (final d in snap.data!.docs) productFromDoc(d),
              ];
              final q = _query.trim().toLowerCase();
              final shown = products.where((p) {
                final scopeOk = switch (_scope) {
                  _Scope.all => true,
                  _Scope.available => p.available,
                  _Scope.unavailable => !p.available,
                  _Scope.lowStock => p.available && p.stock <= 3,
                };
                final text = '${p.name} ${p.category} ${p.weight}'
                    .toLowerCase();
                return scopeOk && (q.isEmpty || text.contains(q));
              }).toList();
              if (shown.isEmpty) {
                return const StateNote(
                  icon: Icons.inventory_2_outlined,
                  text: 'No products match.',
                  detail: 'Adjust the filter/search, or add a product.',
                );
              }
              return Column(children: [for (final p in shown) _row(p)]);
            },
          ),
        ],
      ),
    );
  }

  Widget _bar() {
    Widget chip(String label, _Scope s) {
      final on = _scope == s;
      return Padding(
        padding: const EdgeInsets.only(right: 6),
        child: ChoiceChip(
          label: Text(label),
          selected: on,
          showCheckmark: false,
          onSelected: (_) => setState(() => _scope = s),
          labelStyle: MxType.bodyXs(
            color: on ? MxColors.forest : MxColors.charcoalSoft,
            weight: FontWeight.w700,
          ),
          selectedColor: MxColors.mossSoft,
          backgroundColor: MxColors.creamSoft,
          side: BorderSide(color: on ? MxColors.moss : MxColors.line),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final wide = c.maxWidth >= 720;
        final chips = Row(
          children: [
            chip('All', _Scope.all),
            chip('Available', _Scope.available),
            chip('Unavailable', _Scope.unavailable),
            chip('Low stock', _Scope.lowStock),
          ],
        );
        final search = TextField(
          decoration: const InputDecoration(
            hintText: 'Search products...',
            prefixIcon: Icon(Icons.search_rounded, size: 19),
            isDense: true,
            contentPadding: EdgeInsets.symmetric(vertical: 10),
          ),
          onChanged: (v) => setState(() => _query = v),
        );
        if (wide) {
          return Row(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: chips,
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(width: 260, child: search),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: chips,
            ),
            const SizedBox(height: 10),
            search,
          ],
        );
      },
    );
  }

  Widget _row(Product p) {
    final low = p.available && p.stock <= 3;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: MxColors.mossSoft,
              borderRadius: BorderRadius.circular(MxRadius.sm),
            ),
            child: const Icon(
              Icons.spa_rounded,
              size: 18,
              color: MxColors.moss,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${p.name}${p.weight.isEmpty ? '' : ' (${p.weight})'}'
                  '${p.variant.isEmpty ? '' : '  [${p.variant}]'}',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${p.category}  |  ${rupees(p.price)}  |  stock ${p.stock}'
                  '${low ? '  - low!' : ''}',
                  style: MxType.bodyXs(
                    color: low ? MxColors.warn : MxColors.stone,
                    weight: low ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (!p.available)
            Text(
              'Hidden from shop',
              style: MxType.bodyXs(color: MxColors.stoneLight),
            ),
          Switch(value: p.available, onChanged: (v) => _toggleAvailable(p, v)),
          IconButton(
            tooltip: 'Edit',
            icon: const Icon(Icons.edit_outlined, size: 19),
            onPressed: () => _openEditor(p),
          ),
          IconButton(
            tooltip: 'Delete',
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: MxColors.danger,
            ),
            onPressed: () => _deleteProduct(p),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleAvailable(Product p, bool value) async {
    try {
      await Fb.products.doc(p.id).set({
        'available': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Fb.friendlyMessage(e))));
    }
  }

  Future<void> _deleteProduct(Product p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${p.name}?'),
        content: const Text(
          'This removes the product from the live catalogue. Orders already '
          'placed are not changed.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MxColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await Fb.products.doc(p.id).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Fb.friendlyMessage(e))));
    }
  }

  Future<void> _openEditor([Product? existing]) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProductEditorSheet(product: existing),
    );
  }
}

class ProductEditorSheet extends StatefulWidget {
  const ProductEditorSheet({super.key, this.product});

  final Product? product;

  @override
  State<ProductEditorSheet> createState() => _ProductEditorSheetState();
}

class _ProductEditorSheetState extends State<ProductEditorSheet> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.product?.name ?? '');
  late final _description = TextEditingController(
    text: widget.product?.description ?? '',
  );
  late final _category = TextEditingController(
    text: widget.product?.category ?? 'Mushrooms',
  );
  late final _variant = TextEditingController(
    text: widget.product?.variant ?? 'Fresh',
  );
  late final _weight = TextEditingController(
    text: widget.product?.weight ?? '',
  );
  late final _price = TextEditingController(text: _num(widget.product?.price));
  late final _stock = TextEditingController(text: _num(widget.product?.stock));
  late final _sortKey = TextEditingController(
    text: _num(widget.product?.sortKey),
  );
  late bool _available = widget.product?.available ?? true;
  late bool _busy = false;
  String? _error;

  // Optional photo. A photo chosen here is stored inline on the product
  // document (see util/product_image.dart); an existing product may keep its
  // bundled asset path, be replaced, or have its photo removed.
  String? _pickedImage;
  bool _imageRemoved = false;
  bool _pickingImage = false;
  String? _imageError;

  static String _num(num? v) => v == null ? '' : v.toString();

  String get _existingImage => widget.product?.image ?? '';

  /// The value `image` should hold when the editor is saved.
  String get _imageToSave {
    if (_pickedImage != null) return _pickedImage!;
    if (_imageRemoved) return '';
    return _existingImage;
  }

  /// What the preview box should show right now.
  String get _previewImage {
    if (_pickedImage != null) return _pickedImage!;
    if (_imageRemoved) return '';
    return _existingImage;
  }

  Future<void> _pickPhoto() async {
    if (_pickingImage) return;
    setState(() {
      _pickingImage = true;
      _imageError = null;
    });
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return; // admin cancelled the picker
      final bytes = await picked.first.readAsBytes();
      final url = await encodeInlineProductImage(bytes);
      if (url == null) {
        if (!mounted) return;
        setState(() {
          _imageError = 'That photo could not be stored. Choose a JPEG/PNG '
              'photo under a few MB.';
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _pickedImage = url;
        _imageRemoved = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _imageError = 'The photo could not be read. Choose a JPEG/PNG image.';
      });
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _removeImage() {
    setState(() {
      _pickedImage = null;
      _imageRemoved = true;
    });
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _category,
      _variant,
      _weight,
      _price,
      _stock,
      _sortKey,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final price = double.parse(_price.text.trim());
      final stock = int.parse(_stock.text.trim());
      final sortKey = int.parse(_sortKey.text.trim());
      final base = <String, Object?>{
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'category': _category.text.trim(),
        'variant': _variant.text.trim(),
        'weight': _weight.text.trim(),
        'price': price,
        'stock': stock,
        'sortKey': sortKey,
        'available': _available,
        'image': _imageToSave,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final existing = widget.product;
      final actor = context.read<AuthController>().user?.email;
      if (existing == null) {
        final ref = Fb.products.doc();
        await ref.set({
          ...base,
          'id': ref.id,
          'gallery': const <String>[],
          'createdAt': FieldValue.serverTimestamp(),
        });
        final label = _name.text.trim() +
            (_weight.text.trim().isEmpty
                ? ''
                : ' (${_weight.text.trim()})');
        await logStockChange(
          productId: ref.id,
          productLabel: label,
          type: InventoryMovementType.adjustment,
          previousStock: 0,
          newStock: stock,
          note: 'Initial stock on creation',
          recordedByEmail: actor,
        );
      } else {
        await Fb.products.doc(existing.id).set(base, SetOptions(merge: true));
        if (stock != existing.stock) {
          final label = existing.name +
              (existing.weight.isEmpty ? '' : ' (${existing.weight})');
          await logStockChange(
            productId: existing.id,
            productLabel: label,
            type: InventoryMovementType.adjustment,
            previousStock: existing.stock,
            newStock: stock,
            note: 'Stock set in the product editor',
            recordedByEmail: actor,
          );
        }
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = Fb.friendlyMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final isNew = widget.product == null;
    return FractionallySizedBox(
      heightFactor: 0.95,
      child: Container(
        decoration: const BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 14, 24, 24 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  isNew ? 'Add a product' : 'Edit ${widget.product!.name}',
                  style: MxType.h3(color: MxColors.forest),
                ),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _field(
                        _name,
                        'Name *',
                        (v) => (v ?? '').trim().isEmpty
                            ? 'Name is required'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(
                        _weight,
                        'Weight (e.g. 200g) *',
                        (v) => (v ?? '').trim().isEmpty
                            ? 'Weight is required'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _field(_category, 'Category', null)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _field(_variant, 'Variant (Fresh/Dried)', null),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _field(_description, 'Description', null, maxLines: 3),
                const SizedBox(height: 12),
                _photoTile(),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _field(_price, 'Price (Rs) *', _priceVal)),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_stock, 'Stock *', _int)),
                    const SizedBox(width: 10),
                    Expanded(child: _field(_sortKey, 'Sort key *', _int)),
                  ],
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Available in the shop'),
                  value: _available,
                  onChanged: (v) => setState(() => _available = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 6),
                  Text(_error!, style: MxType.bodyXs(color: MxColors.danger)),
                ],
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _busy ? null : () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _busy ? null : _save,
                        child: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                ),
                              )
                            : Text(isNew ? 'Add product' : 'Save changes'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoTile() {
    final hasPhoto = _previewImage.isNotEmpty;
    final preview = SizedBox(
      width: 88,
      height: 88,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(MxRadius.sm),
        child: hasPhoto
            ? MxImage(asset: _previewImage, width: 88, height: 88)
            : Container(
                color: MxColors.creamDeep,
                child: const Icon(
                  Icons.image_outlined,
                  size: 30,
                  color: MxColors.stoneLight,
                ),
              ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MxColors.creamDeep,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          preview,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Product photo (optional)',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  hasPhoto
                      ? 'Shown in the shop. Pick another photo to replace it.'
                      : 'No photo yet - the shop shows a placeholder. You can '
                          'add one later.',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                if (_imageError != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _imageError!,
                    style: MxType.bodyXs(
                      color: MxColors.danger,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickingImage || _busy ? null : _pickPhoto,
                      icon: _pickingImage
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_a_photo_outlined, size: 16),
                      label: Text(
                        _pickingImage
                            ? 'Preparing...'
                            : (hasPhoto ? 'Change photo' : 'Add photo'),
                      ),
                    ),
                    if (hasPhoto) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _busy ? null : _removeImage,
                        child: const Text('Remove'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String? Function(String?)? validator, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 11,
        ),
      ),
      validator: validator,
    );
  }

  String? _priceVal(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    final d = double.tryParse(t);
    if (d == null) return 'Not a number';
    if (d < 0) return 'Must be 0 or more';
    return null;
  }

  String? _int(String? v) {
    final t = v?.trim() ?? '';
    if (t.isEmpty) return 'Required';
    final i = int.tryParse(t);
    if (i == null) return 'Whole number';
    if (i < 0) return 'Cannot be negative';
    return null;
  }
}
