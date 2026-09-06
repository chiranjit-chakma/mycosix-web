import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../state/auth_controller.dart';
import '../../widgets/brand.dart';
import 'sections/analytics_section.dart';
import 'sections/batches_section.dart';
import 'sections/content_team_section.dart';
import 'sections/dashboard_section.dart';
import 'sections/inventory_section.dart';
import 'sections/orders_section.dart';
import 'sections/products_section.dart';
import 'sections/requests_section.dart';
import 'sections/settings_section.dart';

enum _Area {
  dashboard,
  orders,
  analytics,
  inventory,
  batches,
  requests,
  products,
  contentTeam,
  settings,
}

/// The real admin dashboard shell. Only reached when the gate has confirmed a
/// signed-in, authorised administrator - every section reads/writes Firestore
/// behind security rules (never through a client-side privilege flag).
class AdminScaffold extends StatefulWidget {
  const AdminScaffold({super.key});

  @override
  State<AdminScaffold> createState() => _AdminScaffoldState();
}

class _AdminScaffoldState extends State<AdminScaffold> {
  _Area _area = _Area.dashboard;

  static const _nav = <(_Area, String, IconData)>[
    (_Area.dashboard, 'Overview', Icons.space_dashboard_outlined),
    (_Area.orders, 'Orders', Icons.receipt_long_outlined),
    (_Area.analytics, 'Analytics', Icons.bar_chart_rounded),
    (_Area.inventory, 'Inventory', Icons.warehouse_outlined),
    (_Area.batches, 'Batches', Icons.agriculture_outlined),
    (_Area.requests, 'Requests', Icons.forum_outlined),
    (_Area.products, 'Products', Icons.inventory_2_outlined),
    (_Area.contentTeam, 'Content & team', Icons.groups_outlined),
    (_Area.settings, 'Settings', Icons.settings_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final wide = width >= 980;
    return Scaffold(
      backgroundColor: MxColors.cream,
      body: wide ? _wide() : _narrow(),
    );
  }

  Widget _wide() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: 248,
          color: MxColors.forest,
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
                  child: MxLogo(dark: true, size: 34, showFull: true),
                ),
                const Divider(color: MxColors.lineDark, height: 1),
                const SizedBox(height: 10),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final (area, label, icon) in _nav)
                          _NavItem(
                            label: label,
                            icon: icon,
                            selected: _area == area,
                            onTap: () => setState(() => _area = area),
                          ),
                      ],
                    ),
                  ),
                ),
                const _AccountFooter(),
              ],
            ),
          ),
        ),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _narrow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: MxColors.forest,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              child: Row(
                children: [
                  MxLogo(dark: true, size: 26, showFull: true),
                  const Spacer(),
                  const _AccountFooter(compact: true),
                ],
              ),
            ),
          ),
        ),
        Container(
          color: MxColors.forestDeep,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                for (final (area, label, icon) in _nav)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: ChoiceChip(
                      label: Text(label),
                      avatar: Icon(icon, size: 16),
                      selected: _area == area,
                      onSelected: (_) => setState(() => _area = area),
                      selectedColor: MxColors.mossSoft,
                      backgroundColor: MxColors.forestRaised,
                      labelStyle: MxType.bodyXs(
                        color: _area == area ? MxColors.forest : MxColors.cream,
                        weight: FontWeight.w700,
                      ),
                      showCheckmark: false,
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(child: _content()),
      ],
    );
  }

  Widget _content() {
    return SafeArea(
      top: false,
      child: switch (_area) {
        _Area.dashboard => const DashboardSection(),
        _Area.orders => const OrdersSection(),
        _Area.analytics => const AnalyticsSection(),
        _Area.inventory => const InventorySection(),
        _Area.batches => const BatchesSection(),
        _Area.requests => const RequestsSection(),
        _Area.products => const ProductsSection(),
        _Area.contentTeam => const ContentTeamSection(),
        _Area.settings => const SettingsSection(),
      },
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = selected
        ? MxColors.glow
        : MxColors.cream.withValues(alpha: 0.72);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
      child: Material(
        color: selected ? MxColors.forestRaised : Colors.transparent,
        borderRadius: BorderRadius.circular(MxRadius.md),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(MxRadius.md),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 19, color: fg),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: MxType.bodySm(
                    color: selected
                        ? MxColors.glow
                        : MxColors.cream.withValues(alpha: 0.8),
                    weight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountFooter extends StatelessWidget {
  const _AccountFooter({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final email = auth.user?.email ?? 'Signed in';
    Future<void> signOut() async {
      final leave = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Sign out?'),
          content: const Text(
            'You will need to sign in again to manage the shop.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      if (leave == true && context.mounted) {
        await auth.signOut();
      }
    }

    if (compact) {
      return IconButton(
        tooltip: 'Sign out ($email)',
        icon: const Icon(Icons.logout_rounded, color: MxColors.cream, size: 20),
        onPressed: signOut,
      );
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MxColors.forestRaised,
        borderRadius: BorderRadius.circular(MxRadius.md),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.account_circle_outlined,
            color: MxColors.glow,
            size: 22,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              email,
              overflow: TextOverflow.ellipsis,
              style: MxType.bodyXs(color: MxColors.cream),
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            icon: const Icon(
              Icons.logout_rounded,
              color: MxColors.cream,
              size: 18,
            ),
            onPressed: signOut,
          ),
        ],
      ),
    );
  }
}
