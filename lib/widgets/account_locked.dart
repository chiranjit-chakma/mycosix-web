import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../router/routes.dart';
import 'page.dart';
import 'shell.dart';

/// Full-page locked state for an account-only view (Wishlist, My Orders).
///
/// Shown when a customer reaches one of those pages without a session — an
/// installed-PWA user opening the section before signing in, or a direct
/// link. It never pretends to hold data it cannot read: it explains what the
/// section does and offers clear Sign in / Create account actions.
class LockedAccountPage extends StatelessWidget {
  const LockedAccountPage({
    super.key,
    required this.title,
    required this.icon,
    required this.message,
    this.returnRoute,
  });

  /// Page heading, e.g. "Wishlist" or "My Orders".
  final String title;

  final IconData icon;
  final String message;

  /// The route this locked page is shown under, so a successful sign-in
  /// returns the customer here — where their real data then loads.
  final String? returnRoute;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    return MxShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 120),
          MxPage(
            maxWidth: 680,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('YOUR ACCOUNT'.toUpperCase(), style: MxType.overline()),
                const SizedBox(height: 12),
                Text(title, style: MxType.h1(width)),
                const SizedBox(height: 32),
                MxPanel(
                  child: Column(
                    children: [
                      Icon(icon, size: 34, color: MxColors.stone),
                      const SizedBox(height: 14),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: MxType.bodySm(color: MxColors.charcoalSoft),
                      ),
                      const SizedBox(height: 22),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          OutlinedButton(
                            onPressed: () => _open(context, AuthStartMode.signIn),
                            child: const Text('Sign in'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton(
                            onPressed: () =>
                                _open(context, AuthStartMode.register),
                            style: FilledButton.styleFrom(
                              backgroundColor: MxColors.forest,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Create account'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _open(BuildContext context, AuthStartMode mode) {
    Navigator.of(context).pushNamed(
      Routes.profile,
      arguments: ProfileRouteRequest(
        startMode: mode,
        returnRoute: returnRoute,
      ),
    );
  }
}
