import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_config.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb_admin.dart';
import '../../../models/site_settings.dart';
import '../../../repositories/config_repository.dart';
import '../../../widgets/location/location_map.dart';
import '../admin_widgets.dart';

/// Settings: the single siteConfig/public document the whole site reads. Only
/// the known business values are editable here - nothing is invented, and
/// saving stores exactly what is currently live so the customer site and this
/// form can never drift apart.
class SettingsSection extends StatefulWidget {
  const SettingsSection({super.key});

  @override
  State<SettingsSection> createState() => _SettingsSectionState();
}

class _SettingsSectionState extends State<SettingsSection> {
  SiteSettings? _s;
  bool _busy = false;
  String? _status;
  bool _dirty = false;

  late final TextEditingController _whatsapp = TextEditingController();
  late final TextEditingController _instagram = TextEditingController();
  late final TextEditingController _serviceArea = TextEditingController();
  late final TextEditingController _leadTime = TextEditingController();
  late final TextEditingController _supportEmail = TextEditingController();
  late final TextEditingController _phone = TextEditingController();
  bool _deliveryEnabled = true;
  double? _shopLat;
  double? _shopLng;
  List<_TierDraft> _tiers = [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s != null) return;
    final settings = context.read<ConfigRepository>().settings;
    _s = settings;
    _whatsapp.text = settings.whatsappNumber;
    _instagram.text = settings.instagramUrl;
    _serviceArea.text = settings.serviceArea;
    _leadTime.text = settings.orderLeadTime;
    _supportEmail.text = settings.supportEmail ?? '';
    _phone.text = settings.phoneNumber ?? '';
    _deliveryEnabled = settings.deliveryEnabled;
    _shopLat = settings.shopLatitude;
    _shopLng = settings.shopLongitude;
    _tiers = [
      for (final t in settings.deliveryTiers)
        _TierDraft(km: _fmt(t.upToKm), fee: _fmt(t.fee)),
    ];
  }

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [
      _whatsapp,
      _instagram,
      _serviceArea,
      _leadTime,
      _supportEmail,
      _phone,
    ]) {
      c.dispose();
    }
    for (final t in _tiers) {
      t.km.dispose();
      t.fee.dispose();
    }
    super.dispose();
  }

  void _onChanged(String _) => setState(() => _dirty = true);

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = null;
    });

    String? err;
    final whats = _whatsapp.text.replaceAll(RegExp(r'\D'), '');
    if (whats.length < 10 || whats.length > 13) {
      err = 'WhatsApp number needs 10-13 digits (country code first).';
    } else if (_supportEmail.text.trim().isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
            .hasMatch(_supportEmail.text.trim())) {
      err = 'Support email does not look valid.';
    }
    // Distance-based pricing: tiers need a shop location, each tier needs a
    // sensible distance + fee, and tiers must be strictly ascending so the
    // first-match pricing rule is unambiguous ("up to 2 km free, up to 5 km
    // Rs40, beyond = unavailable").
    final parsedTiers = <({double km, double fee})>[];
    if (_tiers.isNotEmpty) {
      if (_shopLat == null || _shopLng == null) {
        err = 'Distance tiers need a shop location - drag the pin '
            'on the map first.';
      } else {
        for (var i = 0; i < _tiers.length && err == null; i++) {
          final km = double.tryParse(_tiers[i].km.text.trim());
          final f = double.tryParse(_tiers[i].fee.text.trim());
          if (km == null || km <= 0 || f == null || f < 0) {
            err = 'Tier ${i + 1} needs a distance above 0 (km) and a fee '
                'of 0 or more.';
          } else if (parsedTiers.isNotEmpty && km <= parsedTiers.last.km) {
            err = 'Tiers must be in order - each next distance (km) must '
                'be larger than the one before it.';
          } else {
            parsedTiers.add((km: km, fee: f));
          }
        }
      }
    }
    if (err != null) {
      setState(() {
        _busy = false;
        _status = err;
      });
      return;
    }

    String? clean(String v) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    // Optional fields left blank are removed from the document (so the site
    // falls back to its bundled default) rather than stored as empty text.
    Object? maybe(String? v) => v ?? FieldValue.delete();

    final patch = <String, Object?>{
      'whatsappNumber': whats,
      // The flat delivery fee is gone: distance tiers now price delivery.
      // Remove any value an older round stored so the site never mixes a
      // stale flat fee with the distance tiers below.
      'deliveryFee': FieldValue.delete(),
      'shopLatitude': _shopLat ?? FieldValue.delete(),
      'shopLongitude': _shopLng ?? FieldValue.delete(),
      'deliveryTiers': [
        for (final t in parsedTiers) {'km': t.km, 'fee': t.fee},
      ],
      'deliveryEnabled': _deliveryEnabled,
      'instagramUrl': maybe(clean(_instagram.text)),
      'serviceArea': maybe(clean(_serviceArea.text)),
      'orderLeadTime': maybe(clean(_leadTime.text)),
      'supportEmail': maybe(clean(_supportEmail.text)),
      'phoneNumber': maybe(clean(_phone.text)),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await FbAdmin.siteConfig.doc('public').set(patch, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dirty = false;
        _status = 'Saved. The site now uses these values.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = FbAdmin.friendlyMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    if (s == null) {
      return const AdminPage(child: LoadingNote(label: 'Loading settings...'));
    }
    final error = _status != null && !_status!.startsWith('Saved');
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Settings',
            subtitle:
                'The live site configuration document (siteConfig/public). '
                'Saved here, used everywhere.',
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: MxColors.creamSoft,
              borderRadius: BorderRadius.circular(MxRadius.lg),
              border: Border.all(color: MxColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _whatsapp,
                  onChanged: _onChanged,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'WhatsApp number (digits, country code first)',
                    helperText: 'e.g. 91XXXXXXXXXX - the number orders go to.',
                  ),
                ),
                const SizedBox(height: 20),
                const Divider(color: MxColors.line, height: 1),
                const SizedBox(height: 16),
                Text('Delivery area & charges',
                    style: MxType.h3(color: MxColors.charcoal)),
                const SizedBox(height: 6),
                Text(
                  'Delivery is charged by distance. Drag the pin to the '
                  'shop\'s spot, then add distance tiers below. The straight '
                  'line from the shop to the customer\'s pin picks the first '
                  'tier that covers it, so "up to 2 km free, up to 5 km '
                  'Rs 40" works exactly like that. Beyond the last tier, '
                  'that spot is marked not available.',
                  style: MxType.bodySm(color: MxColors.stone),
                ),
                const SizedBox(height: 16),
                Text('Shop location',
                    style: MxType.bodySm(
                        color: MxColors.charcoal, weight: FontWeight.w700)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(MxRadius.lg),
                  child: SizedBox(
                    height: 240,
                    child: LocationMap(
                      latitude: _shopLat ?? MxConfig.defaultLatitude,
                      longitude: _shopLng ?? MxConfig.defaultLongitude,
                      height: 240,
                      onChanged: (latLng) => setState(() {
                        _shopLat = latLng.$1;
                        _shopLng = latLng.$2;
                        _dirty = true;
                      }),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _shopLat == null
                            ? 'No shop location set yet - drag the pin '
                                'to the shop\'s spot.'
                            : 'Shop: ${_shopLat!.toStringAsFixed(5)}, '
                                '${_shopLng!.toStringAsFixed(5)}',
                        style: MxType.bodyXs(color: MxColors.stone),
                      ),
                    ),
                    if (_shopLat != null)
                      TextButton(
                        onPressed: () => setState(() {
                          _shopLat = null;
                          _shopLng = null;
                          _dirty = true;
                        }),
                        child: const Text('Reset'),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('Distance tiers',
                    style: MxType.bodySm(
                        color: MxColors.charcoal, weight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(
                  'Up to X km = that fee (0 = free). Each next distance '
                  'must be larger (2, then 5, then 10...).',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                const SizedBox(height: 8),
                if (_tiers.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MxColors.creamSoft,
                      borderRadius: BorderRadius.circular(MxRadius.md),
                      border: Border.all(color: MxColors.line),
                    ),
                    child: Text(
                      'No distance tiers - every order keeps the standard '
                      'delivery fee until you set the shop spot and at '
                      'least one tier.',
                      style: MxType.bodyXs(color: MxColors.stone),
                    ),
                  )
                else
                  for (var i = 0; i < _tiers.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _tiers[i].km,
                            onChanged: _onChanged,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Up to (km)',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 3,
                          child: TextField(
                            controller: _tiers[i].fee,
                            onChanged: _onChanged,
                            keyboardType: const TextInputType
                                .numberWithOptions(decimal: true),
                            inputFormatters: [
                              FilteringTextInputFormatter.allow(
                                  RegExp(r'[0-9.]')),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Fee (Rs, 0 = free)',
                              isDense: true,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Remove tier',
                          onPressed: () => setState(() {
                            _tiers[i].km.dispose();
                            _tiers[i].fee.dispose();
                            _tiers.removeAt(i);
                            _dirty = true;
                          }),
                          icon: const Icon(
                              Icons.remove_circle_outline, size: 20),
                        ),
                      ],
                    ),
                  ],
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => setState(() {
                      _tiers.add(_TierDraft(km: '', fee: ''));
                      _dirty = true;
                    }),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add tier'),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _instagram,
                  onChanged: _onChanged,
                  keyboardType: TextInputType.url,
                  decoration: const InputDecoration(labelText: 'Instagram URL'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _serviceArea,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(labelText: 'Delivery area'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _leadTime,
                  onChanged: _onChanged,
                  decoration: const InputDecoration(
                    labelText: 'Order lead time',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _supportEmail,
                  onChanged: _onChanged,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Support email (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _phone,
                  onChanged: _onChanged,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone number (optional)',
                  ),
                ),
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Delivery enabled'),
                  subtitle: const Text(
                    'Off = customers are told delivery is '
                    'paused; on = normal ordering.',
                  ),
                  value: _deliveryEnabled,
                  onChanged: (v) => setState(() {
                    _deliveryEnabled = v;
                    _dirty = true;
                  }),
                ),
                if (_status != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _status!,
                    style: MxType.bodyXs(
                      color: error ? MxColors.danger : MxColors.ok,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : (_dirty ? _save : null),
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2.2),
                          )
                        : const Icon(Icons.save_outlined, size: 18),
                    label: Text(_dirty ? 'Save changes' : 'Saved'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One editable distance tier row in the admin form (km + fee). Its text
/// controllers are owned and disposed here with the rest of the form.
class _TierDraft {
  _TierDraft({required String km, required String fee})
      : km = TextEditingController(text: km),
        fee = TextEditingController(text: fee);

  final TextEditingController km;
  final TextEditingController fee;
}
