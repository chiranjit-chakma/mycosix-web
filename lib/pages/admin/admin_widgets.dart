import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../models/order_status.dart';
import '../../models/product.dart';
import '../../models/store_order.dart';
import '../../utils/money.dart';

/// Shared visual pieces for the admin area (desktop-first, brand tokens).

/// Human, short timestamp. No locale-sensitive date packages - plain ASCII.
String shortWhen(DateTime? t) {
  if (t == null) return '-';
  final diff = DateTime.now().difference(t);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  String two(int v) => v.toString().padLeft(2, '0');
  return '${two(t.day)}/${two(t.month)}, ${two(t.hour)}:${two(t.minute)}';
}

Color statusColor(OrderStatus s) {
  switch (s) {
    case OrderStatus.newOrder:
      return MxColors.earth;
    case OrderStatus.contacted:
      return MxColors.stone;
    case OrderStatus.confirmed:
      return MxColors.moss;
    case OrderStatus.preparing:
      return MxColors.warn;
    case OrderStatus.outForDelivery:
      return MxColors.mossDeep;
    case OrderStatus.delivered:
      return MxColors.ok;
    case OrderStatus.cancelled:
      return MxColors.danger;
  }
}

/// Small status pill for order rows / detail.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});

  final OrderStatus status;

  @override
  Widget build(BuildContext context) {
    final c = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            status.label,
            style: MxType.bodyXs(color: c, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

/// Standard page frame for admin sections (scroll, gutters, max width).
class AdminPage extends StatelessWidget {
  const AdminPage({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1240),
          child: child,
        ),
      ),
    );
  }
}

/// Standard section heading inside the admin content column.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: MxType.h3()),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(subtitle!, style: MxType.bodySm(color: MxColors.stone)),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Error / empty / loading text panels for Firestore-backed admin lists.
class StateNote extends StatelessWidget {
  const StateNote({
    super.key,
    required this.icon,
    required this.text,
    this.detail,
    this.tone = StateTone.neutral,
  });

  final IconData icon;
  final String text;
  final String? detail;
  final StateTone tone;

  @override
  Widget build(BuildContext context) {
    final c = switch (tone) {
      StateTone.neutral => MxColors.stone,
      StateTone.warn => MxColors.warn,
      StateTone.danger => MxColors.danger,
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 8),
          Text(
            text,
            style: MxType.bodySm(
              color: MxColors.charcoal,
              weight: FontWeight.w600,
            ),
          ),
          if (detail != null) ...[
            const SizedBox(height: 4),
            Text(detail!, style: MxType.bodyXs(color: MxColors.stone)),
          ],
        ],
      ),
    );
  }
}

enum StateTone { neutral, warn, danger }

/// Loading spinner panel.
class LoadingNote extends StatelessWidget {
  const LoadingNote({super.key, this.label = 'Loading...'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 32),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4),
          ),
          const SizedBox(height: 10),
          Text(label, style: MxType.bodySm(color: MxColors.stone)),
        ],
      ),
    );
  }
}

/// Money via the exact same formatter the customer site uses, so admin
/// figures can never disagree with a customer's.
String rupees(num v) => formatRupees(v);

/// Reads a Firestore timestamp/DateTime out of a raw document map.
DateTime? fireTs(Object? v) {
  if (v is DateTime) return v.toLocal();
  if (v != null) {
    try {
      return (v as dynamic).toDate().toLocal() as DateTime;
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Compact preview of an arbitrary document (content/team rows).
String previewMap(Map<String, dynamic> m, {int max = 90}) {
  final parts = <String>[];
  for (final e in m.entries) {
    final v = e.value;
    if (v == null || v is Map || v is List) continue;
    final t = v.toString().trim();
    if (t.isEmpty) continue;
    parts.add('${e.key}: $t');
    if (parts.join(' | ').length > max) break;
  }
  var out = parts.join(' | ');
  if (out.length > max) out = '${out.substring(0, max)}...';
  return out.isEmpty ? '(empty document)' : out;
}

/// Maps a Firestore order document to the typed model the admin UI shows.
StoreOrder orderFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data() ?? const <String, dynamic>{};
  return StoreOrder.fromMap(
    m,
    id: d.id,
    createdAt: fireTs(m['createdAt']),
    updatedAt: fireTs(m['updatedAt']),
    deliveredAt: fireTs(m['deliveredAt']),
  );
}

/// Maps a Firestore product document to the typed product model.
Product productFromDoc(DocumentSnapshot<Map<String, dynamic>> d) {
  final m = d.data() ?? const <String, dynamic>{};
  return Product.fromFirestoreMap(m).copyWith(
    createdAt: fireTs(m['createdAt']),
    updatedAt: fireTs(m['updatedAt']),
  );
}

bool orderOpen(StoreOrder o) =>
    o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled;

bool orderNeedsAttention(StoreOrder o) =>
    o.status == OrderStatus.newOrder || o.status == OrderStatus.contacted;
