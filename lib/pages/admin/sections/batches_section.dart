import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb.dart';
import '../../../models/batch.dart';
import '../admin_widgets.dart';

/// Grow-batch records: plan a batch, harvest it, and keep produced / sold /
/// waste quantities honest.
///
/// A batch is a farm record, kept entirely inside the admin area and written
/// straight to Firestore behind admin-only rules. It is NOT auto-synchronised
/// with shop sales - there is no trusted backend connecting the two yet - so
/// the sold/waste numbers on a batch are recorded by hand, and nothing here
/// pretends otherwise.
class BatchesSection extends StatefulWidget {
  const BatchesSection({super.key});

  @override
  State<BatchesSection> createState() => _BatchesSectionState();
}

class _BatchesSectionState extends State<BatchesSection> {
  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Batches',
            subtitle:
                'Farm grow records with MYCO-BATCH ids. Sold/waste quantities '
                'are entered by hand and are separate from shop orders for now.',
          ),
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: Fb.batches.orderBy('productionDate', descending: true).snapshots(),
            builder: (context, snap) {
              if (snap.hasError) {
                return StateNote(
                  icon: Icons.error_outline_rounded,
                  text: 'Batches could not be loaded.',
                  detail: Fb.friendlyMessage(snap.error!),
                  tone: StateTone.danger,
                );
              }
              if (!snap.hasData) {
                return const LoadingNote(label: 'Loading batches...');
              }
              final docs = snap.data!.docs;
              final batches = <Batch>[];
              final idsByYear = <int, int>{};
              for (final d in docs) {
                final m = d.data();
                final b = Batch.fromMap(
                  m,
                  id: d.id,
                  createdAt: fireTs(m['createdAt']),
                  updatedAt: fireTs(m['updatedAt']),
                );
                batches.add(b);
                final year = b.year ?? _yearOf(b.productionDate);
                if (year != null) {
                  idsByYear[year] = (idsByYear[year] ?? 0) + 1;
                }
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '${batches.length} batch${batches.length == 1 ? '' : 'es'} '
                        'recorded',
                        style: MxType.bodyXs(color: MxColors.stone),
                      ),
                      const Spacer(),
                      FilledButton.icon(
                        onPressed: () =>
                            _openEditor(nextId: nextBatchId(DateTime.now().year, idsByYear[DateTime.now().year] ?? 0)),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('New batch'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (batches.isEmpty)
                    const StateNote(
                      icon: Icons.agriculture_outlined,
                      text: 'No batches recorded yet.',
                      detail:
                          'Plan your first grow batch with "New batch" - it '
                          'gets the next MYCO-BATCH-<year> id automatically.',
                    )
                  else
                    for (final b in batches)
                      _batchRow(context, b),
                  const SizedBox(height: 4),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  int? _yearOf(String ymd) {
    final m = RegExp(r'^(\d{4})-').firstMatch(ymd);
    return m == null ? null : int.parse(m.group(1)!);
  }

  Widget _batchRow(BuildContext context, Batch b) {
    final statusColor = switch (b.status) {
      BatchStatus.planned => MxColors.stone,
      BatchStatus.inProduction => MxColors.warn,
      BatchStatus.harvested => MxColors.ok,
      BatchStatus.closed => MxColors.earth,
    };
    final low = b.status != BatchStatus.closed && b.remainingQty <= 0 && b.producedQty > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${b.batchId}  |  ${b.variety}',
                      style: MxType.bodySm(
                        color: MxColors.charcoal,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Produced ${b.productionDate}  |  '
                      'Expected ${b.expectedHarvestDate}'
                      '${b.hasActualHarvest ? '  |  Harvested ${b.actualHarvestDate}' : ''}'
                      '${b.grade == null || b.grade!.isEmpty ? '' : '  |  Grade ${b.grade}'}',
                      style: MxType.bodyXs(color: MxColors.stone),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  b.status.label,
                  style: MxType.bodyXs(
                    color: statusColor,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _qty('Produced', b.producedQty),
              _qty('Sold', b.soldQty),
              _qty('Waste', b.wasteQty),
              Expanded(
                child: Text(
                  b.producedQty == 0
                      ? (b.status == BatchStatus.harvested
                          ? 'Harvest not recorded yet'
                          : 'Nothing produced yet')
                      : '${b.remainingQty} remaining${low ? ' - sold out' : ''}',
                  textAlign: TextAlign.right,
                  style: MxType.bodyXs(
                    color: low || (b.producedQty == 0 && b.status == BatchStatus.harvested)
                        ? MxColors.warn
                        : MxColors.ok,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: () => _openEditor(existing: b),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _qty(String label, int value) {
    return Padding(
      padding: const EdgeInsets.only(right: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: MxType.bodySm(color: MxColors.charcoal, weight: FontWeight.w800),
          ),
          Text(label, style: MxType.bodyXs(color: MxColors.stone)),
        ],
      ),
    );
  }

  Future<void> _openEditor({Batch? existing, String nextId = ''}) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatchEditorDialog(
        existing: existing,
        suggestedId: nextId,
      ),
    );
  }
}

/// Form for creating or editing one grow batch. Validates every number and
/// date before touching Firestore; quantities can never be negative and
/// sold + waste can never exceed produced.
class BatchEditorDialog extends StatefulWidget {
  const BatchEditorDialog({super.key, this.existing, required this.suggestedId});

  final Batch? existing;
  final String suggestedId;

  @override
  State<BatchEditorDialog> createState() => _BatchEditorDialogState();
}

class _BatchEditorDialogState extends State<BatchEditorDialog> {
  final _form = GlobalKey<FormState>();
  late final _variety = TextEditingController(text: widget.existing?.variety ?? '');
  late final _produced = TextEditingController(
    text: (widget.existing?.producedQty ?? 0).toString(),
  );
  late final _sold = TextEditingController(
    text: (widget.existing?.soldQty ?? 0).toString(),
  );
  late final _waste = TextEditingController(
    text: (widget.existing?.wasteQty ?? 0).toString(),
  );
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String? _grade = widget.existing?.grade;
  late BatchStatus _status = widget.existing?.status ?? BatchStatus.planned;
  late DateTime? _production = _parse(widget.existing?.productionDate);
  late DateTime? _expected = _parse(widget.existing?.expectedHarvestDate);
  late DateTime? _actual = _parse(widget.existing?.actualHarvestDate);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _variety.dispose();
    _produced.dispose();
    _sold.dispose();
    _waste.dispose();
    _notes.dispose();
    super.dispose();
  }

  static DateTime? _parse(String? ymd) {
    final d = parseYmd(ymd);
    return d;
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  bool get isNew => widget.existing == null;

  Future<void> _save() async {
    if (_busy) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    if (_production == null || _expected == null) {
      setState(() => _error = 'Pick the production and expected harvest dates.');
      return;
    }
    final produced = int.parse(_produced.text.trim());
    final sold = int.parse(_sold.text.trim());
    final waste = int.parse(_waste.text.trim());
    final year = _production!.year;
    final candidate = Batch(
      id: widget.existing?.id ?? '',
      batchId: widget.existing?.batchId ?? widget.suggestedId,
      variety: _variety.text.trim(),
      productionDate: _ymd(_production!),
      expectedHarvestDate: _ymd(_expected!),
      actualHarvestDate: _actual == null ? null : _ymd(_actual!),
      producedQty: produced,
      soldQty: sold,
      wasteQty: waste,
      grade: _grade,
      notes: _notes.text,
      status: _status,
      year: year,
      createdAt: widget.existing?.createdAt,
      updatedAt: widget.existing?.updatedAt,
    );
    final errors = validateBatch(candidate);
    if (errors.isNotEmpty) {
      setState(() => _error = errors.join('\n'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final map = candidate.toMap();
      if (isNew) {
        map['createdAt'] = FieldValue.serverTimestamp();
        map['updatedAt'] = FieldValue.serverTimestamp();
        await Fb.batches.doc().set(map);
      } else {
        map['createdAt'] =
            widget.existing!.createdAt ?? FieldValue.serverTimestamp();
        map['updatedAt'] = FieldValue.serverTimestamp();
        // Full overwrite keeps the record free of stale optional fields.
        await Fb.batches.doc(widget.existing!.id).set(map);
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
    return AlertDialog(
      title: Text(isNew ? 'New grow batch' : 'Edit ${widget.existing!.batchId}'),
      content: SizedBox(
        width: 540,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!isNew)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      widget.existing!.batchId,
                      style: MxType.bodySm(
                        color: MxColors.stone,
                        weight: FontWeight.w700,
                      ),
                    ),
                  ),
                _text(_variety, 'Variety *',
                    (v) => (v ?? '').trim().isEmpty ? 'Variety is required' : null),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _datePick(
                        'Production date',
                        _production,
                        (d) => setState(() => _production = d),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _datePick(
                        'Expected harvest',
                        _expected,
                        (d) => setState(() => _expected = d),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _datePick(
                        'Actual harvest',
                        _actual,
                        (d) => setState(() => _actual = d),
                        clearable: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _number(_produced, 'Produced *'),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _number(_sold, 'Sold')),
                    const SizedBox(width: 10),
                    Expanded(child: _number(_waste, 'Waste')),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sold + waste can never exceed produced. '
                  'Produced = ${int.tryParse(_produced.text.trim()) ?? 0}, '
                  'sold + waste = '
                  '${(int.tryParse(_sold.text.trim()) ?? 0) + (int.tryParse(_waste.text.trim()) ?? 0)}',
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: _grade,
                        decoration: const InputDecoration(
                          labelText: 'Grade (optional)',
                        ),
                        items: [
                          for (final g in const ['A', 'B', 'C'])
                            DropdownMenuItem(value: g, child: Text(g)),
                          const DropdownMenuItem(
                            value: null,
                            child: Text('No grade'),
                          ),
                        ],
                        onChanged: (v) => setState(() => _grade = v),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<BatchStatus>(
                        initialValue: _status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: [
                          for (final s in BatchStatus.values)
                            DropdownMenuItem(value: s, child: Text(s.label)),
                        ],
                        onChanged: (v) => setState(() {
                          if (v != null) _status = v;
                        }),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _text(_notes, 'Notes', null, maxLines: 2),
                if (_error != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    style: MxType.bodyXs(color: MxColors.danger, weight: FontWeight.w600),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : 'Save batch'),
        ),
      ],
    );
  }

  Widget _text(
    TextEditingController c,
    String label,
    FormFieldValidator<String>? validator, {
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      maxLines: maxLines,
      validator: validator,
      inputFormatters: maxLines == 1
          ? [LengthLimitingTextInputFormatter(60)]
          : [LengthLimitingTextInputFormatter(500)],
    );
  }

  Widget _number(TextEditingController c, String label) {
    return TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      validator: (v) {
        final n = int.tryParse((v ?? '').trim());
        if (n == null) return 'Number required';
        return null;
      },
    );
  }

  Widget _datePick(
    String label,
    DateTime? value,
    ValueChanged<DateTime?> onPicked, {
    bool clearable = false,
  }) {
    return InkWell(
      onTap: () async {
        final base = value ?? (_production ?? DateTime.now());
        final picked = await showDatePicker(
          context: context,
          initialDate: base,
          firstDate: DateTime(2020),
          lastDate: DateTime(base.year + 1, 12, 31),
          helpText: label,
        );
        if (picked != null && context.mounted) {
          onPicked(DateTime(picked.year, picked.month, picked.day));
        }
      },
      borderRadius: BorderRadius.circular(MxRadius.sm),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.sm),
          border: Border.all(color: MxColors.line),
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, size: 16, color: MxColors.stone),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                value == null ? label : '$label: ${value.day}/${value.month}/${value.year}',
                style: MxType.bodyXs(
                  color: value == null ? MxColors.stone : MxColors.forest,
                  weight: FontWeight.w600,
                ),
              ),
            ),
            if (clearable && value != null)
              GestureDetector(
                onTap: () => onPicked(null),
                child: const Icon(Icons.close_rounded, size: 16, color: MxColors.stone),
              ),
          ],
        ),
      ),
    );
  }
}
