import 'package:flutter/material.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../services/whatsapp_otp.dart';
import '../../utils/phone.dart';
import '../../widgets/whatsapp_verify_panel.dart';

/// The checkout's WhatsApp-verification slot, rendered directly beneath the
/// WhatsApp-number field, keyed to the canonical number the field holds.
///
/// The slot exists so the send-OTP option, the code entry and the verified
/// state always live NEXT TO the number they belong to - visible as soon as
/// the field holds a complete valid number, instead of appearing only after
/// the place-order button is tapped. It renders exactly one of:
///  - nothing, while the field holds no complete number yet,
///  - the full [WhatsAppVerifyPanel] (intro with its send button, then the
///    6-digit code entry + verify action) while the number needs proving,
///  - a compact 'Send OTP' offer after the customer closed the panel
///    (re-opening it auto-starts a fresh code request, so the tap that says
///    'send' really sends),
///  - a green verified row once the number is proven (carried by the
///    signed-in account, attested by an admin, or verified here with a code).
class CheckoutVerifySlot extends StatelessWidget {
  const CheckoutVerifySlot({
    super.key,
    required this.canonicalPhone,
    required this.proven,
    required this.showPanel,
    required this.autoRequestCode,
    required this.service,
    this.sessionPhone,
    this.sessionEmail,
    required this.onVerified,
    required this.onOpenPanel,
    required this.onDismiss,
  });

  /// The canonical '+91XXXXXXXXXX' number the field holds, or null when the
  /// field does not yet hold a complete valid number (slot renders nothing).
  final String? canonicalPhone;

  /// Whether this number needs no code (account claim / admin attestation /
  /// verified earlier in this checkout) - the slot then shows the verified
  /// row instead of any verification UI.
  final bool proven;

  /// Whether the full verification panel should be shown. When false (and
  /// not proven), the compact 'Send OTP' offer is shown instead.
  final bool showPanel;

  /// Passed to the panel: a freshly mounted intro-phase panel immediately
  /// requests a code (see [WhatsAppVerifyPanel.autoRequestCode]).
  final bool autoRequestCode;

  final WhatsAppOtpService service;

  /// The signed-in account's own verified phone / email when the customer is
  /// signed in under a DIFFERENT number (guest-handoff disclosure copy).
  final String? sessionPhone;
  final String? sessionEmail;

  /// Called once Firebase verified the code ([freshSession] tells the page
  /// whether a throwaway session was created and must be signed out again).
  final void Function({required bool freshSession}) onVerified;

  /// Called when the customer asks to send a code from the compact offer.
  final VoidCallback onOpenPanel;

  /// Called when the customer closes the open panel.
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final c = canonicalPhone;
    if (c == null) return const SizedBox.shrink();

    if (proven) {
      return Container(
        key: ValueKey<String>('verified-$c'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: MxColors.ok.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(MxRadius.md),
          border: Border.all(color: MxColors.ok.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.verified_rounded, size: 18, color: MxColors.ok),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Verified: ${humanizeWhatsAppPhone(c)} - orders on this '
                'number go straight through, no code needed.',
                style: MxType.bodySm(
                  color: MxColors.charcoalSoft,
                  weight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (showPanel) {
      return WhatsAppVerifyPanel(
        key: ValueKey<String>('verify-$c'),
        service: service,
        canonicalPhone: c,
        sessionPhone: sessionPhone,
        sessionEmail: sessionEmail,
        autoRequestCode: autoRequestCode,
        onVerified: onVerified,
        onCancel: onDismiss,
      );
    }

    // The compact offer left behind after the customer closed the panel.
    return Container(
      key: const Key('whatsapp-otp-offer'),
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: const BoxDecoration(
                  color: MxColors.moss,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.verified_user_outlined,
                  size: 18,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Verify your WhatsApp number',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A 6-digit code is sent by SMS to '
            '${humanizeWhatsAppPhone(c)} to confirm this number before your '
            'order is placed.',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('whatsapp-otp-offer-open'),
              onPressed: onOpenPanel,
              style: FilledButton.styleFrom(
                backgroundColor: MxColors.forest,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.sms_outlined, size: 17),
              label: const Text('Send OTP'),
            ),
          ),
        ],
      ),
    );
  }
}
