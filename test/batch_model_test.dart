import 'package:flutter_test/flutter_test.dart';
import 'package:mycosix/models/batch.dart';

void main() {
  group('batch id', () {
    test('nextBatchId sequences within a year', () {
      expect(nextBatchId(2026, 0), 'MYCO-BATCH-2026-001');
      expect(nextBatchId(2026, 1), 'MYCO-BATCH-2026-002');
      expect(nextBatchId(2026, 41), 'MYCO-BATCH-2026-042');
      expect(nextBatchId(2026, 998), 'MYCO-BATCH-2026-999');
    });

    test('nextBatchId resets each year', () {
      expect(nextBatchId(2027, 0), 'MYCO-BATCH-2027-001');
    });

    test('batchIdPattern matches valid ids and rejects junk', () {
      expect(batchIdPattern.hasMatch('MYCO-BATCH-2026-001'), isTrue);
      expect(batchIdPattern.hasMatch('MYCO-BATCH-2026-9999'), isTrue);
      expect(batchIdPattern.hasMatch('BATCH-2026-001'), isFalse);
      expect(batchIdPattern.hasMatch('MYCO-BATCH-26-001'), isFalse);
    });
  });

  group('parseYmd', () {
    test('parses a real date', () {
      final d = parseYmd('2026-09-06');
      expect(d, isNotNull);
      expect(d!.year, 2026);
      expect(d.month, 9);
      expect(d.day, 6);
    });

    test('rejects impossible and malformed dates', () {
      expect(parseYmd('2026-13-01'), isNull);
      expect(parseYmd('2026-02-30'), isNull);
      expect(parseYmd('06/09/2026'), isNull);
      expect(parseYmd(''), isNull);
      expect(parseYmd(null), isNull);
      expect(parseYmd('2026-9-6'), isNull); // must be zero padded
    });
  });

  group('validateBatch', () {
    Batch base({int produced = 100, int sold = 0, int waste = 0}) => Batch(
          id: '',
          batchId: 'MYCO-BATCH-2026-001',
          variety: 'Oyster',
          productionDate: '2026-09-01',
          expectedHarvestDate: '2026-09-10',
          producedQty: produced,
          soldQty: sold,
          wasteQty: waste,
        );

    test('valid batch has no errors', () {
      expect(validateBatch(base(produced: 100, sold: 40, waste: 5)), isEmpty);
    });

    test('sold + waste cannot exceed produced', () {
      final errors = validateBatch(base(produced: 10, sold: 8, waste: 5));
      expect(errors.any((e) => e.contains('cannot exceed')), isTrue);
    });

    test('negative quantities are rejected', () {
      expect(validateBatch(base(produced: -1)), isNotEmpty);
      expect(validateBatch(base(sold: -2)), isNotEmpty);
      expect(validateBatch(base(waste: -2)), isNotEmpty);
    });

    test('cannot sell/waste from a batch that produced nothing', () {
      expect(validateBatch(base(produced: 0, sold: 1)), isNotEmpty);
      expect(validateBatch(base(produced: 0, waste: 1)), isNotEmpty);
    });

    test('expected harvest cannot precede production', () {
      final b = base().copyWith(
        productionDate: '2026-09-10',
        expectedHarvestDate: '2026-09-01',
      );
      expect(validateBatch(b), isNotEmpty);
    });

    test('variety is required', () {
      final b = base().copyWith(variety: '   ');
      expect(validateBatch(b), isNotEmpty);
    });
  });

  group('Batch maths', () {
    test('remainingQty is produced minus sold minus waste', () {
      final b = Batch(
        id: 'x',
        batchId: 'MYCO-BATCH-2026-001',
        variety: 'Oyster',
        productionDate: '2026-09-01',
        expectedHarvestDate: '2026-09-10',
        producedQty: 120,
        soldQty: 45,
        wasteQty: 5,
      );
      expect(b.remainingQty, 70);
    });

    test('round-trips through toMap/fromMap', () {
      final original = Batch(
        id: 'doc1',
        batchId: 'MYCO-BATCH-2026-007',
        variety: 'Pink Oyster',
        productionDate: '2026-09-01',
        expectedHarvestDate: '2026-09-12',
        actualHarvestDate: '2026-09-11',
        producedQty: 90,
        soldQty: 60,
        wasteQty: 3,
        grade: 'A',
        notes: 'Cold front week',
        status: BatchStatus.harvested,
        year: 2026,
        createdAt: DateTime(2026, 9, 1),
        updatedAt: DateTime(2026, 9, 12),
      );
      final restored = Batch.fromMap(
        original.toMap(),
        id: 'doc1',
        createdAt: original.createdAt,
        updatedAt: original.updatedAt,
      );
      expect(restored.batchId, original.batchId);
      expect(restored.variety, original.variety);
      expect(restored.actualHarvestDate, '2026-09-11');
      expect(restored.producedQty, 90);
      expect(restored.soldQty, 60);
      expect(restored.wasteQty, 3);
      expect(restored.grade, 'A');
      expect(restored.notes, 'Cold front week');
      expect(restored.status, BatchStatus.harvested);
      expect(restored.year, 2026);
      expect(restored.createdAt, original.createdAt);
    });

    test('optional actualHarvest is omitted when empty', () {
      final b = Batch(
        id: '',
        batchId: 'MYCO-BATCH-2026-001',
        variety: 'Oyster',
        productionDate: '2026-09-01',
        expectedHarvestDate: '2026-09-10',
      );
      expect(b.toMap().containsKey('actualHarvestDate'), isFalse);
    });
  });
}
