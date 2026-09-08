import 'package:flutter/material.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';

/// The "Continue with Twitter" button on the account page. The Twitter/X mark
/// is drawn as a plain white "X" on a black circle (not the logo artwork) so
/// the site never embeds a third-party trademark asset.
class TwitterSignInButton extends StatelessWidget {
  const TwitterSignInButton({
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
        key: const Key('twitter-sign-in-button'),
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
                  const _TwitterX(),
                  const SizedBox(width: 10),
                  Text(
                    'Continue with Twitter',
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

/// A plain black circle with a white "X" - a neutral stand-in for the
/// Twitter/X mark, kept small and flat.
class _TwitterX extends StatelessWidget {
  const _TwitterX();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        shape: BoxShape.circle,
      ),
      child: const Text(
        'X',
        style: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }
}
