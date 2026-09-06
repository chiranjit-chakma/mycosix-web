/// A logged change to a product's stock quantity.
///
/// Written by the admin area whenever stock is changed (inventory or product
/// sections). The change is recorded as a movement with the previous and new
/// stock levels so every adjustment is auditable and the history does not
/// depend on remembering the old value. Only admins can write/read these; a
/// trusted order backend can later append `sale` movements when it decrements
/// stock, in the same shape.
library;

/// Canonical movement types (mirrored in `firestore.rules`).
enum InventoryMovementType {
  /// A manual stock adjustment made by the farm team.
  adjustment('Adjustment'),

  /// A stock decrease recorded because a shop order went out. Until a trusted
  /// backend decrements automatically, an admin records sales here by hand.
  sale('Sale');

  const InventoryMovementType(this.label);

  final String label;

  static InventoryMovementType fromLabel(String? label) {
    for (final t in InventoryMovementType.values) {
      if (t.label == label) return t;
    }
    return InventoryMovementType.adjustment;
  }
}

/// Plain-string mirror of [InventoryMovementType] for the rules allowlist.
const List<String> inventoryMovementTypeLabels = <String>[
  'Adjustment',
  'Sale',
];

/// One recorded stock change for one product.
class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.productName,
    required this.movementType,
    required this.previousStock,
    required this.newStock,
    this.note,
    this.linkedOrderId,
    this.recordedAt,
    this.recordedByEmail,
  });

  /// Firestore document id. Empty before the movement is persisted.
  final String id;

  final String productId;
  final String productName;
  final InventoryMovementType movementType;

  /// Stock before the change (>= 0).
  final int previousStock;

  /// Stock after the change (>= 0).
  final int newStock;

  /// Change applied: newStock - previousStock (negative = stock went down).
  int get delta => newStock - previousStock;

  final String? note;

  /// Set when the movement is a sale of a specific shop order.
  final String? linkedOrderId;

  final DateTime? recordedAt;
  final String? recordedByEmail;

  Map<String, Object?> toMap() => {
        'productId': productId,
        'productName': productName.trim(),
        'movementType': movementType.label,
        'previousStock': previousStock,
        'newStock': newStock,
        if (note != null && note!.trim().isNotEmpty) 'note': note!.trim(),
        if (linkedOrderId != null && linkedOrderId!.isNotEmpty)
          'linkedOrderId': linkedOrderId,
        if (recordedByEmail != null && recordedByEmail!.isNotEmpty)
          'recordedByEmail': recordedByEmail,
      };

  factory InventoryMovement.fromMap(
    Map<String, dynamic> map, {
    required String id,
    DateTime? recordedAt,
  }) {
    return InventoryMovement(
      id: id,
      productId: (map['productId'] ?? '') as String,
      productName: (map['productName'] ?? '') as String,
      movementType:
          InventoryMovementType.fromLabel(map['movementType'] as String?),
      previousStock: ((map['previousStock'] ?? 0) as num).toInt(),
      newStock: ((map['newStock'] ?? 0) as num).toInt(),
      note: map['note'] as String?,
      linkedOrderId: map['linkedOrderId'] as String?,
      recordedAt: recordedAt,
      recordedByEmail: map['recordedByEmail'] as String?,
    );
  }
}
