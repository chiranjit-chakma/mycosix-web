import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../admin_widgets.dart';

/// Content + team records. Nothing here is invented: only documents that
/// actually exist in Firestore are shown. New records should hold genuine
/// information, so they are added in the Firebase console (kept out of the UI
/// to avoid accidental placeholder content ever reaching the live site).
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
                'Live editorial/team records from Firestore. Documents '
                'added here appear on the site.',
          ),
          const SizedBox(height: 16),
          const _Block(title: 'Content', hint: 'content'),
          const SizedBox(height: 24),
          const _Block(title: 'Team', hint: 'team'),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.hint});

  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: Fb.db.collection(hint).snapshots(),
      builder: (context, snap) {
        final docs =
            snap.data?.docs ?? const <DocumentSnapshot<Map<String, dynamic>>>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: MxType.labelLg(color: MxColors.moss),
                  ),
                ),
                Text(
                  docs.isEmpty ? '' : '${docs.length} record(s)',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (snap.hasError)
              StateNote(
                icon: Icons.error_outline_rounded,
                text: 'Could not load $hint records.',
                detail: Fb.friendlyMessage(snap.error!),
                tone: StateTone.danger,
              )
            else if (!snap.hasData)
              const LoadingNote(label: 'Loading...')
            else if (docs.isEmpty)
              StateNote(
                icon: Icons.article_outlined,
                text: 'No $hint records yet.',
                detail:
                    'Add genuine records in the Firebase console under the '
                    '"$hint" collection - nothing is shown here until it '
                    'really exists.',
              )
            else ...[
              for (final d in docs) _docRow(context, hint: hint, doc: d),
            ],
          ],
        );
      },
    );
  }

  Widget _docRow(
    BuildContext context, {
    required String hint,
    required DocumentSnapshot<Map<String, dynamic>> doc,
  }) {
    final m = doc.data() ?? const <String, dynamic>{};
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
                  doc.id,
                  style: MxType.bodyXs(
                    color: MxColors.moss,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  previewMap(m),
                  style: MxType.bodyXs(color: MxColors.charcoalSoft),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Delete this record',
            icon: const Icon(
              Icons.delete_outline_rounded,
              size: 19,
              color: MxColors.danger,
            ),
            onPressed: () => _delete(context, hint, doc.id),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, String hint, String id) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this record?'),
        content: const Text(
          'Removing it will take it off the live site immediately.',
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
    if (ok != true) return;
    try {
      await Fb.db.collection(hint).doc(id).delete();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(Fb.friendlyMessage(e))));
    }
  }
}
