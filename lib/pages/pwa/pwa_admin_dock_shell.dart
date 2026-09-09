import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../router/routes.dart';
import '../../services/display_mode.dart';
import '../../state/site_config_controller.dart';
import 'pwa_dock.dart';
import 'pwa_registry.dart';
import 'pwa_root.dart'
    show adminDockIndex, kPwaSectionLabels, pagerIndexForDock, pwaDockIcons, pwaDockLabels;

/// Wraps the admin gate's visible bodies so that, on the installed phone app
/// with the owner's Admin-in-navigation toggle ON, the SAME floating dock as
/// the home sections stays visible at the bottom of the Admin page.
///
/// The owner wanted "the whole navigation bar visible on Admin like the other
/// pages": with this shell the Admin page carries Farm / Shop / Home / Journey
/// / Admin / Profile on a dock that rests centred on Admin, so tapping a
/// section closes the Admin page and lands on it. Everywhere else - a browser
/// tab, a desktop PWA, the toggle OFF, or the gate's covert states (this shell
/// only ever wraps the revealed bodies) - the child renders exactly as before.
///
/// The dock is presentation only and never an authorisation signal: the gate
/// body below still demands the server-verified admin grant before any admin
/// content is shown, and this shell is never applied to the hidden/hand-off
/// states that a stranger reaching /admin would see.
class PwaAdminDockShell extends StatefulWidget {
  const PwaAdminDockShell({super.key, required this.child, this.forceDock});

  /// The gate body this shell may put a dock under (rendered unchanged when
  /// the dock does not apply).
  final Widget child;

  /// Test hook: forces the dock on/off without needing the phone display mode
  /// (the test VM always reports non-standalone). Production leaves this null
  /// and the dock is driven by [isStandaloneMobile] + the live toggle.
  final bool? forceDock;

  @override
  State<PwaAdminDockShell> createState() => _PwaAdminDockShellState();
}

class _PwaAdminDockShellState extends State<PwaAdminDockShell> {
  /// The five primary pager sections, in pager index order. A dock tap that
  /// leaves Admin maps onto these routes (never with arguments, exactly like a
  /// dock tap on the home shell).
  static const List<String> _sectionRoutes = <String>[
    Routes.farm,
    Routes.shop,
    Routes.home,
    Routes.journey,
    Routes.profile,
  ];

  static final int _sectionCount = kPwaSectionLabels.length;

  /// Whether an editable text field currently holds keyboard focus - the
  /// signal that the platform keyboard is over the bottom of the screen.
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    FocusManager.instance.removeListener(_onFocusChanged);
    super.dispose();
  }

  static bool _hasEditableFocus() {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText || ctx.widget is TextField) return true;
    var editing = false;
    ctx.visitAncestorElements((e) {
      if (e.widget is EditableText || e.widget is TextField) {
        editing = true;
        return false;
      }
      return true;
    });
    return editing;
  }

  void _onFocusChanged() {
    final editing = _hasEditableFocus();
    if (editing != _editing && mounted) {
      setState(() => _editing = editing);
    }
  }

  /// Whether the phone dock applies: only on the installed phone app with the
  /// owner's toggle on; tests can force either side.
  bool _dockApplies() {
    final force = widget.forceDock;
    if (force != null) return force;
    return isStandaloneMobile() &&
        liveSiteSettings(context).adminNavShortcutEnabled;
  }

  /// A dock selection on the Admin page. The strip rests on the Admin slot
  /// (this page), so tapping it again simply stays. Every other destination is
  /// a primary section: prefer the live paging shell beneath, which pops this
  /// Admin page and glides to that section in one step; without a shell (an
  /// /admin deep link landing as the first route) replace this page with the
  /// section route.
  bool _onDockSelect(int dock) {
    if (dock == adminDockIndex(_sectionCount)) return false; // Already here.
    final route = _sectionRoutes[pagerIndexForDock(
      dock: dock,
      adminOn: true,
      sectionCount: _sectionCount,
    )];
    if (PwaRegistry.switchSection(route)) return true;
    Navigator.of(context).pushReplacementNamed(route);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    if (!_dockApplies()) return widget.child;
    // The dock slips away while the keyboard is over it (editable focus or a
    // deep platform inset), exactly as on the home shell, so it never crowds
    // the field being typed into.
    final keyboardOpen =
        _editing || MediaQuery.viewInsetsOf(context).bottom > 80.0;
    return ColoredBox(
      color: MxColors.cream,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: widget.child),
          if (!keyboardOpen) _buildDock(),
        ],
      ),
    );
  }

  Widget _buildDock() {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(12, 6, 12, 10),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: PwaDock(
            key: const Key('admin-phone-dock'),
            // The strip rests centred on the Admin slot - the page we are on.
            index: adminDockIndex(_sectionCount),
            labels: pwaDockLabels(adminOn: true),
            icons: pwaDockIcons(adminOn: true),
            onSelect: _onDockSelect,
            // A fixed, fully-expanded dock: the Admin page has no single
            // unifying scroll to compress with, so it stays roomy.
            compression: const AlwaysStoppedAnimation<double>(0),
          ),
        ),
      ),
    );
  }
}
