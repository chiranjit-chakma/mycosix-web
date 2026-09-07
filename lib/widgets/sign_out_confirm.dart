import 'package:flutter/material.dart';

import '../config/mx_colors.dart';

/// Asks for explicit confirmation before a customer signs out.
///
/// Returns `true` only when the customer confirms; anything else keeps the
/// session. The copy reassures: signing out only affects this device and
/// nothing is lost (cart, wishlist and orders all live on the account).
Future<bool> showSignOutConfirm(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: MxColors.cream,
      title: const Text('Log out?'),
      content: const Text(
        'You will be signed out on this device only. Your cart, wishlist '
        'and orders stay saved on your account — sign back in anytime.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Log out'),
        ),
      ],
    ),
  );
  return ok == true;
}
