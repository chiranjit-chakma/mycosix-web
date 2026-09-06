/// A production batch of mushrooms, tracked by the farm team in the admin
/// area. Purely an admin record: batches are never exposed publicly and are
/// never synchronised with shop orders automatically (there is no authoritative
/// auto-sale hookup until a trusted order backend exists, so batch sold/waste
/// quantities are deliberately manual entries).
library;

/// Canonical batch statuses (mirrored in `firestore.rules`).
enum BatchStatus {
  planned('Planned'),
  inProduction('In Production'),
  harvested('Harvested'),
  closed('Closed');

  const BatchStatus(this.label);

  final String label;

  static BatchStatus fromLabel(String? label) {
    for (final s in BatchStatus.values) {
      if (s.label == label) return s;
    }
    return BatchStatus.planned;
  }
}

/// Plain-string mirror of [BatchStatus] used by the security rules allowlist.
const List<String> batchStatusLabels = <String>[
  'Planned',
  'In Production',
  'Harvested',
  'Closed',
];

/// Batch id shape, e.g. `MYCO-BATCH-2026-001`.
final RegExp batchIdPattern = RegExp(r'^MYCO-BATCH-\d{4}-\d{3,}$');

/// Builds the next sequential batch id for [year] given how many batches have
/// already been created in that year ([count]). 001, 002, ... 999+.
String nextBatchId(int year, int count) {
  final seq = (count + 1).toString().padLeft(3, '0');
  return 'MYCO-BATCH-$year-$seq';
}

/// A single grow batch.
///
/// Calendar dates are stored as plain `YYYY-MM-DD` strings (they are facts the
/// team records, not event timestamps). produced/sold/waste are whole units;
/// [remainingQty] is derived and never stored.
class Batch {
  const Batch({
    required this.id,
    required this.batchId,
    required this.variety,
    required this.productionDate,
    required this.expectedHarvestDate,
    this.actualHarvestDate,
    this.producedQty = 0,
    this.soldQty = 0,
    this.wasteQty = 0,
    this.grade,
    this.notes,
    this.status = BatchStatus.planned,
    this.year,
    this.createdAt,
    this.updatedAt,
  });

  /// Firestore document id. Empty before the batch is persisted.
  final String id;

  /// Human batch id, format `MYCO-BATCH-YYYY-NNN`.
  final String batchId;

  final String variety;

  /// `YYYY-MM-DD`.
  final String productionDate;

  /// `YYYY-MM-DD`.
  final String expectedHarvestDate;

  /// `YYYY-MM-DD`, when the harvest actually happened.
  final String? actualHarvestDate;

  final int producedQty;
  final int soldQty;
  final int wasteQty;

  final String? grade;
  final String? notes;
  final BatchStatus status;

  /// Calendar year of production (used to compute the next sequence number).
  final int? year;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get remainingQty => producedQty - soldQty - wasteQty;

  bool get hasActualHarvest =>
      actualHarvestDate != null && actualHarvestDate!.isNotEmpty;

  Batch copyWith({
    String? batchId,
    String? variety,
    String? productionDate,
    String? expectedHarvestDate,
    String? actualHarvestDate,
    bool clearActualHarvest = false,
    int? producedQty,
    int? soldQty,
    int? wasteQty,
    String? grade,
    String? notes,
    BatchStatus? status,
    DateTime? updatedAt,
  }) {
    return Batch(
      id: id,
      batchId: batchId ?? this.batchId,
      variety: variety ?? this.variety,
      productionDate: productionDate ?? this.productionDate,
      expectedHarvestDate: expectedHarvestDate ?? this.expectedHarvestDate,
      actualHarvestDate: clearActualHarvest
          ? null
          : (actualHarvestDate ?? this.actualHarvestDate),
      producedQty: producedQty ?? this.producedQty,
      soldQty: soldQty ?? this.soldQty,
      wasteQty: wasteQty ?? this.wasteQty,
      grade: grade ?? this.grade,
      notes: notes ?? this.notes,
      status: status ?? this.status,
      year: year,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toMap() => {
        'batchId': batchId,
        'variety': variety,
        'productionDate': productionDate,
        'expectedHarvestDate': expectedHarvestDate,
        if (actualHarvestDate != null) 'actualHarvestDate': actualHarvestDate,
        'producedQty': producedQty,
        'soldQty': soldQty,
        'wasteQty': wasteQty,
        if (grade != null && grade!.isNotEmpty) 'grade': grade,
        if (notes != null && notes!.trim().isNotEmpty) 'notes': notes!.trim(),
        'status': status.label,
        if (year != null) 'year': year,
      };

  factory Batch.fromMap(
    Map<String, dynamic> map, {
    required String id,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    final production = (map['productionDate'] ?? '') as String;
    return Batch(
      id: id,
      batchId: (map['batchId'] ?? '') as String,
      variety: (map['variety'] ?? '') as String,
      productionDate: production,
      expectedHarvestDate: (map['expectedHarvestDate'] ?? '') as String,
      actualHarvestDate: map['actualHarvestDate'] as String?,
      producedQty: ((map['producedQty'] ?? 0) as num).toInt(),
      soldQty: ((map['soldQty'] ?? 0) as num).toInt(),
      wasteQty: ((map['wasteQty'] ?? 0) as num).toInt(),
      grade: map['grade'] as String?,
      notes: map['notes'] as String?,
      status: BatchStatus.fromLabel(map['status'] as String?),
      year: (map['year'] as num?)?.toInt(),
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }
}

/// Parses a `YYYY-MM-DD` string, or returns null.
DateTime? parseYmd(String? value) {
  if (value == null) return null;
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  final dt = DateTime(y, mo, d);
  // Reject impossible dates like 2026-13-40 by round-tripping.
  if (dt.year != y || dt.month != mo || dt.day != d) return null;
  return dt;
}

/// Validates a batch's numbers and dates. Returns human messages; empty means
/// the batch is acceptable. Quantities are never allowed to go negative and
/// sold + waste may never exceed produced.
List<String> validateBatch(Batch b) {
  final errors = <String>[];
  if (b.variety.trim().isEmpty) errors.add('Enter a variety name.');
  if (parseYmd(b.productionDate) == null) {
    errors.add('Production date is not a valid date.');
  }
  if (parseYmd(b.expectedHarvestDate) == null) {
    errors.add('Expected harvest date is not a valid date.');
  }
  final production = parseYmd(b.productionDate);
  final expected = parseYmd(b.expectedHarvestDate);
  final actual = parseYmd(b.actualHarvestDate);
  if (production != null && expected != null && expected.isBefore(production)) {
    errors.add('Expected harvest cannot be before production.');
  }
  if (production != null && actual != null && actual.isBefore(production)) {
    errors.add('Actual harvest cannot be before production.');
  }
  if (b.producedQty < 0) errors.add('Produced quantity cannot be negative.');
  if (b.soldQty < 0) errors.add('Sold quantity cannot be negative.');
  if (b.wasteQty < 0) errors.add('Waste quantity cannot be negative.');
  if (b.producedQty == 0 && (b.soldQty > 0 || b.wasteQty > 0)) {
    errors.add('Nothing was produced, so nothing can be sold or wasted.');
  }
  if (b.soldQty + b.wasteQty > b.producedQty) {
    errors.add(
      'Sold (${b.soldQty}) + waste (${b.wasteQty}) cannot exceed '
      'produced (${b.producedQty}).',
    );
  }
  if (b.status == BatchStatus.harvested) {
    if (!b.hasActualHarvest) {
      errors.add('A harvested batch needs an actual harvest date.');
    }
    if (b.producedQty <= 0) {
      errors.add('A harvested batch needs a produced quantity.');
    }
  }
  return errors;
}
