import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';

/// The "Continue with Google" button on the account page. The Google G is
/// drawn as a plain monogram (not the logo artwork) so the site never embeds
/// a third-party trademark asset.
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.onPressed,
    this.busy = false,
  });

  /// Called when the customer taps the button. Null while [busy].
  final VoidCallback? onPressed;

  /// True while a sign-in is in flight; disables the button and shows a
  /// spinner.
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        key: const Key('google-sign-in-button'),
        onPressed: busy ? null : onPressed,
        style: OutlinedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: MxColors.charcoal,
          side: const BorderSide(color: MxColors.line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(999),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18),
        ),
        child: busy
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: MxColors.moss,
                ),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const _GoogleG(),
                  const SizedBox(width: 10),
                  Text(
                    'Continue with Google',
                    style: MxType.bodySm(
                      color: MxColors.charcoal,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// A plain white circle with a blue "G" - a neutral stand-in for the Google
/// mark, kept small and flat.
class _GoogleG extends StatelessWidget {
  const _GoogleG();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
      ),
      child: const Text(
        'G',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF4285F4),
          height: 1.0,
        ),
      ),
    );
  }
}
