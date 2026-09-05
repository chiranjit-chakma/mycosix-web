import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/site_settings.dart';
import '../../../repositories/config_repository.dart';
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
  late final TextEditingController _deliveryFee = TextEditingController();
  late final TextEditingController _instagram = TextEditingController();
  late final TextEditingController _serviceArea = TextEditingController();
  late final TextEditingController _leadTime = TextEditingController();
  late final TextEditingController _supportEmail = TextEditingController();
  late final TextEditingController _phone = TextEditingController();
  bool _deliveryEnabled = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_s != null) return;
    final settings = context.read<ConfigRepository>().settings;
    _s = settings;
    _whatsapp.text = settings.whatsappNumber;
    _deliveryFee.text = _fmt(settings.deliveryFee);
    _instagram.text = settings.instagramUrl;
    _serviceArea.text = settings.serviceArea;
    _leadTime.text = settings.orderLeadTime;
    _supportEmail.text = settings.supportEmail ?? '';
    _phone.text = settings.phoneNumber ?? '';
    _deliveryEnabled = settings.deliveryEnabled;
  }

  static String _fmt(num v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  @override
  void dispose() {
    for (final c in [
      _whatsapp,
      _deliveryFee,
      _instagram,
      _serviceArea,
      _leadTime,
      _supportEmail,
      _phone,
    ]) {
      c.dispose();
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
    final fee = double.tryParse(_deliveryFee.text.trim());
    if (whats.length < 10 || whats.length > 13) {
      err = 'WhatsApp number needs 10-13 digits (country code first).';
    } else if (fee == null || fee < 0) {
      err = 'Delivery fee must be 0 or more.';
    } else if (_supportEmail.text.trim().isNotEmpty &&
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
            .hasMatch(_supportEmail.text.trim())) {
      err = 'Support email does not look valid.';
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
      'deliveryFee': fee,
      'deliveryEnabled': _deliveryEnabled,
      'instagramUrl': maybe(clean(_instagram.text)),
      'serviceArea': maybe(clean(_serviceArea.text)),
      'orderLeadTime': maybe(clean(_leadTime.text)),
      'supportEmail': maybe(clean(_supportEmail.text)),
      'phoneNumber': maybe(clean(_phone.text)),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    try {
      await Fb.siteConfig.doc('public').set(patch, SetOptions(merge: true));
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
        _status = Fb.friendlyMessage(e);
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
                const SizedBox(height: 12),
                TextField(
                  controller: _deliveryFee,
                  onChanged: _onChanged,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: const InputDecoration(
                    labelText: 'Delivery fee (Rs)',
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
