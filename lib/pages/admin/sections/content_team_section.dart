import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb_admin.dart';
import '../admin_widgets.dart';

/// Content + team editing.
///
/// Both collections are read by the public marketing site, so everything here
/// is genuinely live:
///
/// * **Team** — each record is a member card on the site's "Our Team" page
///   (name, optional role, optional display order). Nothing here is invented:
///   only what an admin adds or edits appears.
///
/// * **Content** — a fixed set of copy slots that the site's story pages read
///   (Farm opening, Farm grow-room, Journey opening, Journey story heading).
///   Blank fields keep the page's built-in line, so an admin edits only the
///   words they want to change and can clear the whole slot to restore the
///   bundled copy. Only these known slots are offered — saving an unknown doc
///   would never be shown anywhere.
class ContentTeamSection extends StatelessWidget {
  const ContentTeamSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Content & team',
            subtitle:
                'Live editorial records. Team members appear on the site’s '
                '“Our Team” page; content slots feed the Farm and Journey '
                'pages. Nothing here is invented — only what you add shows.',
          ),
          const SizedBox(height: 16),
          const _TeamEditor(),
          const SizedBox(height: 32),
          const _ContentEditor(),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Team members
// ---------------------------------------------------------------------------

class _TeamEditor extends StatelessWidget {
  const _TeamEditor();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FbAdmin.db.collection('team').snapshots(),
      builder: (context, snap) {
        var docs =
            snap.data?.docs ?? const <DocumentSnapshot<Map<String, dynamic>>>[];
        // Sort client-side (docs may predate the sort field and Firestore's
        // orderBy would silently drop them).
        docs = [...docs]..sort((a, b) {
          final sa = a.data()?['sort'];
          final sb = b.data()?['sort'];
          final ia = sa is int
              ? sa
              : (sa is num ? sa.toInt() : 0x7FFFFFFF);
          final ib = sb is int
              ? sb
              : (sb is num ? sb.toInt() : 0x7FFFFFFF);
          return ia.compareTo(ib);
        });
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Team members',
                    style: MxType.labelLg(color: MxColors.moss),
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: MxColors.moss,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                  onPressed: () => _edit(context, doc: null, sortHint: docs.length),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add member'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (snap.hasError)
              StateNote(
                icon: Icons.error_outline_rounded,
                text: 'Could not load team records.',
                detail: FbAdmin.friendlyMessage(snap.error!),
                tone: StateTone.danger,
              )
            else if (!snap.hasData)
              const LoadingNote(label: 'Loading team...')
            else if (docs.isEmpty)
              StateNote(
                icon: Icons.groups_outlined,
                text: 'No team members yet.',
                detail:
                    'The site still shows its six bundled founders until you '
                    'add members here — a customer is never left with an '
                    'empty team.',
              )
            else ...[
              for (final d in docs) _teamRow(context, d),
            ],
            if (docs.isEmpty) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: MxColors.moss,
                  side: const BorderSide(color: MxColors.line),
                ),
                onPressed: () => _seedFounders(context),
                icon: const Icon(Icons.download_rounded, size: 18),
                label: const Text('Start from the six founders on the site'),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Writes the six real founders (already shown on the public page) as team
  /// records so the owner can edit roles/order from the correct starting
  /// point instead of accidentally replacing them with a single new member.
  Future<void> _seedFounders(BuildContext context) async {
    const founders = <String>[
      'Chandan',
      'Hruday',
      'Preetham',
      'Jashwanth',
      'Neha',
      'Varshini',
    ];
    try {
      final batch = FbAdmin.db.batch();
      for (var i = 0; i < founders.length; i++) {
        final ref = FbAdmin.db.collection('team').doc();
        batch.set(ref, <String, dynamic>{'name': founders[i], 'sort': i});
      }
      await batch.commit();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
    }
  }

  Widget _teamRow(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final m = doc.data() ?? const <String, dynamic>{};
    final name = (m['name'] as String?)?.trim() ?? '(untitled)';
    final role = (m['role'] as String?)?.trim() ?? '';
    final order = m['sort'];
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  role.isEmpty
                      ? 'No role yet — shows the MYCOSIX label on the site'
                      : 'Role: $role',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                if (order is num)
                  Text(
                    'Order: ${order.toInt()}',
                    style: MxType.bodyXs(color: MxColors.stone),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit this member',
            icon: const Icon(Icons.edit_outlined, size: 19, color: MxColors.moss),
            onPressed: () => _edit(context, doc: doc),
          ),
          IconButton(
            tooltip: 'Remove this member',
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: MxColors.danger,
            ),
            onPressed: () => _delete(context, doc.id),
          ),
        ],
      ),
    );
  }

  Future<void> _edit(
    BuildContext context, {
    required DocumentSnapshot<Map<String, dynamic>>? doc,
    int sortHint = 0,
  }) async {
    final m = doc?.data();
    final name = TextEditingController(text: (m?['name'] as String?) ?? '');
    final role = TextEditingController(text: (m?['role'] as String?) ?? '');
    final order = TextEditingController(
      text: m?['sort'] is num ? '${(m?['sort'] as num).toInt()}' : '',
    );
    final formKey = GlobalKey<FormState>();

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(doc == null ? 'Add a team member' : 'Edit team member'),
        content: SizedBox(
          width: 420,
          child: Form(
            key: formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _field(name, 'Full name *', _required,
                      helper: 'Exactly as it should appear on the site.'),
                  const SizedBox(height: 10),
                  _field(role, 'Role (optional)', null,
                      helper:
                          'e.g. “Founder · grows the spawn”. Leave empty to '
                          'keep the MYCOSIX label.'),
                  const SizedBox(height: 10),
                  _field(
                    order,
                    'Display order (optional)',
                    _wholeNum,
                    helper:
                        'Lower numbers appear first. Leave empty to append at '
                        'the end.',
                  ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MxColors.moss),
            onPressed: () {
              if (!(formKey.currentState?.validate() ?? false)) return;
              Navigator.pop(context, true);
            },
            child: const Text('Save member'),
          ),
        ],
      ),
    );
    if (save != true) return;

    final trimmedName = name.text.trim();
    final trimmedRole = role.text.trim();
    final sort = int.tryParse(order.text.trim()) ?? sortHint;

    try {
      if (doc == null) {
        await FbAdmin.db.collection('team').add(<String, dynamic>{
          'name': trimmedName,
          'sort': sort,
          if (trimmedRole.isNotEmpty) 'role': trimmedRole,
        });
      } else {
        await FbAdmin.db.collection('team').doc(doc.id).update(<String, dynamic>{
          'name': trimmedName,
          'sort': sort,
          // An empty role must clear a previously stored one.
          'role': trimmedRole.isNotEmpty
              ? trimmedRole
              : FieldValue.delete(),
        });
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
    }
  }

  Future<void> _delete(BuildContext context, String id) async {
    final ok = await _confirmDelete(
      context,
      'Remove this team member?',
      'They will disappear from the “Our Team” page immediately.',
    );
    if (ok != true) return;
    try {
      await FbAdmin.db.collection('team').doc(id).delete();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
    }
  }
}

// ---------------------------------------------------------------------------
// Content slots (fixed set the site reads)
// ---------------------------------------------------------------------------

class _ContentEditor extends StatelessWidget {
  const _ContentEditor();

  /// The copy slots the site pages read, in admin order. `label` is what an
  /// admin recognises; `page` says where the slot shows.
  static const _slots = <({String id, String page, String about, bool bodyExtra})>[
    (
      id: 'farm-hero',
      page: 'Farm',
      about: 'Opening hero',
      bodyExtra: false,
    ),
    (
      id: 'farm-grow',
      page: 'Farm',
      about: 'The Grow Room feature',
      bodyExtra: true,
    ),
    (
      id: 'journey-hero',
      page: 'Journey',
      about: 'Opening hero',
      bodyExtra: false,
    ),
    (
      id: 'journey-story',
      page: 'Journey',
      about: '“The Story So Far” heading',
      bodyExtra: false,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Page copy (content)',
                style: MxType.labelLg(color: MxColors.moss),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final slot in _slots) _slotRow(context, slot),
      ],
    );
  }

  Widget _slotRow(
    BuildContext context,
    ({String id, String page, String about, bool bodyExtra}) slot,
  ) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FbAdmin.db.collection('content').doc(slot.id).snapshots(),
      builder: (context, snap) {
        final m = snap.data?.data();
        final hasOverride = snap.data?.exists == true &&
            (m?.values.any((v) => v is String && v.trim().isNotEmpty) ??
                false);
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: MxColors.creamSoft,
            borderRadius: BorderRadius.circular(MxRadius.md),
            border: Border.all(color: MxColors.line),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${slot.page} — ${slot.about}',
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      hasOverride ? 'Custom copy is showing' : 'Using built-in copy',
                      style: MxType.bodyXs(
                        color: hasOverride ? MxColors.moss : MxColors.stone,
                      ),
                    ),
                    if (snap.hasError)
                      Text(
                        FbAdmin.friendlyMessage(snap.error!),
                        style: MxType.bodyXs(color: MxColors.danger),
                      ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit this copy',
                icon: const Icon(Icons.edit_outlined, size: 19, color: MxColors.moss),
                onPressed: () => _edit(context, slot: slot, doc: snap.data),
              ),
              if (hasOverride)
                IconButton(
                  tooltip: 'Restore built-in copy',
                  icon: const Icon(
                    Icons.restart_alt_rounded,
                    size: 19,
                    color: MxColors.danger,
                  ),
                  onPressed: () => _clear(context, slot.id),
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _edit(
    BuildContext context,
    {
      required ({String id, String page, String about, bool bodyExtra}) slot,
      required DocumentSnapshot<Map<String, dynamic>>? doc,
    }
  ) async {
    final m = doc?.data();
    final overline = TextEditingController(text: (m?['overline'] as String?) ?? '');
    final title = TextEditingController(text: (m?['title'] as String?) ?? '');
    final body = TextEditingController(text: (m?['body'] as String?) ?? '');
    final bodyExtra = TextEditingController(
        text: (m?['bodyExtra'] as String?) ?? '');

    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit — ${slot.page} ${slot.about}'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Leave a field empty to keep that line as the site has it '
                  'today. Emptying every field restores the built-in copy.',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                const SizedBox(height: 12),
                _field(overline, 'Overline (small label)', null),
                const SizedBox(height: 10),
                _field(title, 'Title', null),
                const SizedBox(height: 10),
                _field(body, 'Body', null, maxLines: 4),
                if (slot.bodyExtra) ...[
                  const SizedBox(height: 10),
                  _field(bodyExtra, 'Extra body (optional)', null, maxLines: 3),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: MxColors.moss),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save copy'),
          ),
        ],
      ),
    );
    if (save != true) return;

    final map = <String, dynamic>{
      if (overline.text.trim().isNotEmpty) 'overline': overline.text.trim(),
      if (title.text.trim().isNotEmpty) 'title': title.text.trim(),
      if (body.text.trim().isNotEmpty) 'body': body.text.trim(),
      if (slot.bodyExtra && bodyExtra.text.trim().isNotEmpty)
        'bodyExtra': bodyExtra.text.trim(),
    };

    try {
      if (map.isEmpty) {
        // Whole slot blank -> restore built-in copy.
        await FbAdmin.db.collection('content').doc(slot.id).delete();
      } else {
        await FbAdmin.db.collection('content').doc(slot.id).set(map);
      }
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
    }
  }

  Future<void> _clear(BuildContext context, String id) async {
    final ok = await _confirmDelete(
      context,
      'Restore the built-in copy?',
      'Your custom text for this slot will be removed and the page will go '
      'back to its original words.',
    );
    if (ok != true) return;
    try {
      await FbAdmin.db.collection('content').doc(id).delete();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(FbAdmin.friendlyMessage(e))));
    }
  }
}

// ---------------------------------------------------------------------------
// Shared bits
// ---------------------------------------------------------------------------

Future<bool?> _confirmDelete(BuildContext context, String title, String message) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: MxColors.danger),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Remove'),
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
  String? helper,
}) {
  return TextFormField(
    controller: c,
    maxLines: maxLines,
    decoration: InputDecoration(
      labelText: label,
      helperText: helper,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
    ),
    validator: validator,
  );
}

String? _required(String? v) {
  if ((v?.trim() ?? '').isEmpty) return 'Required';
  return null;
}

String? _wholeNum(String? v) {
  final t = v?.trim() ?? '';
  if (t.isEmpty) return null;
  final i = int.tryParse(t);
  if (i == null) return 'Whole number';
  if (i < 0) return 'Cannot be negative';
  return null;
}
