import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/admin_logs.dart';
import '../../../firebase/fb_admin.dart';
import '../../../models/inventory_movement.dart';
import '../../../models/product.dart';
import '../../../state/auth_controller.dart';
import '../../../util/product_image.dart';
import '../../../widgets/mx_image.dart';
import '../../../widgets/product_video.dart';
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
            stream: FbAdmin.products.orderBy('sortKey').snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return StateNote(
                  icon: Icons.error_outline_rounded,
                  text: 'Products could not be loaded.',
                  detail: FbAdmin.friendlyMessage(snap.error!),
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
        color: p.available
            ? MxColors.creamSoft
            : MxColors.oyster.withValues(alpha: 0.35),
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
                  p.available
                      ? '${p.category}  |  ${rupees(p.price)}  |  stock '
                          '${p.stock}'
                          '${hasProductVideo(p.videoUrl) ? '  |  video' : ''}'
                          '${low ? '  - low!' : ''}'
                      : 'Hidden from the shop  |  ${p.category}  |  '
                          '${rupees(p.price)}',
                  style: MxType.bodyXs(
                    color: !p.available
                        ? MxColors.stone
                        : (low ? MxColors.warn : MxColors.stone),
                    weight: !p.available
                        ? FontWeight.w600
                        : (low ? FontWeight.w700 : FontWeight.w400),
                  ),
                ),
              ],
            ),
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
      await FbAdmin.products.doc(p.id).set({
        'available': value,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
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
      await FbAdmin.products.doc(p.id).delete();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
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
  late final _videoUrl = TextEditingController(
    text: widget.product?.videoUrl ?? '',
  );
  late final _deliveryNote = TextEditingController(
    text: widget.product?.deliveryNote ?? '',
  );
  late bool _available = widget.product?.available ?? true;
  late bool _busy = false;
  String? _error;

  // Product photos, shown and edited in order. The first photo is the cover
  // (`image`) the shop shows; the rest are stored in `gallery`. A photo chosen
  // here is stored inline on the product document (see util/product_image.dart);
  // an existing product may keep its bundled asset paths, replace any of them,
  // or remove them. A product holds at most maxProductPhotos photos.
  late final List<String> _photos = widget.product == null
      ? <String>[]
      : productPhotos(
          image: widget.product!.image,
          gallery: widget.product!.gallery,
        );
  bool _busyPhoto = false;
  String? _photoError;

  static String _num(num? v) => v == null ? '' : v.toString();

  /// Picks one photo and returns it as a compact inline data URL, or null when
  /// the admin cancelled the picker or the photo could not be stored.
  Future<String?> _pickOnePhoto() async {
    if (_busyPhoto) return null;
    setState(() {
      _busyPhoto = true;
      _photoError = null;
    });
    try {
      final picked = await FilePicker.pickFiles(type: FileType.image);
      if (picked.isEmpty) return null; // admin cancelled the picker
      final bytes = await picked.first.readAsBytes();
      final url = await encodeInlineProductImage(bytes);
      if (url == null) {
        if (mounted) {
          setState(() {
            _photoError = 'That photo could not be stored. Choose a JPEG/PNG '
                'photo under a few MB.';
          });
        }
        return null;
      }
      return url;
    } catch (_) {
      if (mounted) {
        setState(() {
          _photoError =
              'The photo could not be read. Choose a JPEG/PNG image.';
        });
      }
      return null;
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
    }
  }

  Future<void> _addPhoto() async {
    if (_photos.length >= maxProductPhotos) return;
    final url = await _pickOnePhoto();
    if (url == null || !mounted) return;
    setState(() {
      if (_photos.length < maxProductPhotos) _photos.add(url);
    });
  }

  Future<void> _replacePhoto(int index) async {
    final url = await _pickOnePhoto();
    if (url == null || !mounted) return;
    setState(() => _photos[index] = url);
  }

  void _removePhoto(int index) {
    setState(() => _photos.removeAt(index));
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
      _videoUrl,
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
    final actor = context.read<AuthController>().user?.email;
    try {
      final price = double.parse(_price.text.trim());
      final stock = int.parse(_stock.text.trim());
      final sortKey = int.parse(_sortKey.text.trim());
      var photos = [
        for (final p in _photos)
          if (p.trim().isNotEmpty) p,
      ];
      // All stored photos of one product must fit under Firestore's per-document
      // cap together; if they do not, they are shrunk to fit before saving.
      photos = await fitProductPhotoBudget(photos);
      final image = photos.isEmpty ? '' : photos.first;
      final gallery =
          photos.length > 1 ? photos.sublist(1) : const <String>[];
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
        'image': image,
        'gallery': gallery,
        'videoUrl': _videoUrl.text.trim(),
        // A blank delivery note is stored as absent so the product page falls
        // back to the site-wide default delivery line from Settings.
        if (_deliveryNote.text.trim().isNotEmpty)
          'deliveryNote': _deliveryNote.text.trim(),
        'updatedAt': FieldValue.serverTimestamp(),
      };
      final existing = widget.product;
      if (existing == null) {
        final ref = FbAdmin.products.doc();
        await ref.set({
          ...base,
          'id': ref.id,
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
        // On edit, an emptied delivery note must REMOVE the stored value
        // (merge:true only touches the keys present), so it is sent as an
        // explicit field delete and the shop falls back to the default line.
        await FbAdmin.products.doc(existing.id).set(
          {
            ...base,
            if (_deliveryNote.text.trim().isEmpty)
              'deliveryNote': FieldValue.delete(),
          },
          SetOptions(merge: true),
        );
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
        _error = FbAdmin.friendlyMessage(e);
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
                const SizedBox(height: 10),
                _field(
                  _videoUrl,
                  'Video link (optional)',
                  videoLinkFieldError,
                  helper: 'Paste a YouTube link (in the app: Share > Copy '
                      'link) or a direct .mp4/.webm web link. When set, '
                      'customers see a "Watch product video" button on the '
                      'product. Leave empty for no video.',
                ),
                const SizedBox(height: 10),
                _field(
                  _deliveryNote,
                  'Delivery note (optional)',
                  null,
                  helper: 'Leave empty for the default line: "Same day or '
                      'next morning delivery in Mysore, Karnataka" (editable in '
                      'Settings). Type a custom line here to override it for '
                      'just this product.',
                ),
                const SizedBox(height: 12),
                _photosSection(),
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

  Widget _photosSection() {
    final remaining = maxProductPhotos - _photos.length;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MxColors.creamDeep,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Product photos',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              if (_photos.isNotEmpty)
                Text(
                  '${_photos.length}/$maxProductPhotos',
                  style: MxType.bodyXs(
                    color: MxColors.stone,
                    weight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'The first photo is the main photo shown in the shop; the rest '
            'appear in the product gallery. Tap a photo to change it, or its X '
            'to remove it. You can add up to $maxProductPhotos photos.',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
          if (_photoError != null) ...[
            const SizedBox(height: 6),
            Text(
              _photoError!,
              style: MxType.bodyXs(
                color: MxColors.danger,
                weight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (var i = 0; i < _photos.length; i++) _photoThumb(i),
              if (remaining > 0) _addPhotoThumb(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _photoThumb(int index) {
    final main = index == 0;
    return SizedBox(
      width: 88,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              InkWell(
                onTap:
                    _busyPhoto || _busy ? null : () => _replacePhoto(index),
                borderRadius: BorderRadius.circular(MxRadius.sm),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(MxRadius.sm),
                  child: MxImage(
                    asset: _photos[index],
                    width: 88,
                    height: 80,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              if (!_busyPhoto)
                Positioned(
                  top: 4,
                  right: 4,
                  child: _photoRemoveButton(index),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            main ? 'Main photo' : 'Photo ${index + 1}',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
        ],
      ),
    );
  }

  Widget _photoRemoveButton(int index) {
    return GestureDetector(
      onTap: _busyPhoto || _busy ? null : () => _removePhoto(index),
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: MxColors.forest,
          shape: BoxShape.circle,
        ),
        child: const Icon(
          Icons.close_rounded,
          size: 14,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _addPhotoThumb() {
    return InkWell(
      onTap: _busyPhoto || _busy ? null : _addPhoto,
      borderRadius: BorderRadius.circular(MxRadius.sm),
      child: Container(
        width: 88,
        height: 80,
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.sm),
          border: Border.all(color: MxColors.moss, width: 1.2),
        ),
        child: _busyPhoto
            ? const Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.add_a_photo_outlined,
                    size: 18,
                    color: MxColors.moss,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Add photo',
                    style: MxType.bodyXs(
                      color: MxColors.moss,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label,
    String? Function(String?)? validator, {
    int maxLines = 1,
    String? helper,
  }) {
    return TextFormField(
      controller: c,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
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
