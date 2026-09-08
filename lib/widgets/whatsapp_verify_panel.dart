import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/mx_colors.dart';
import '../config/mx_type.dart';
import '../services/whatsapp_otp.dart';
import '../utils/phone.dart';

/// Cooldown before a new code may be requested.
const _kResendCooldown = Duration(seconds: 30);

/// Wrong-code attempts allowed before a new code is forced.
const _kMaxAttempts = 5;

/// The published temporary code while the owner's fallback is switched on
/// (real SMS codes are not available yet). Accepted entirely client-side; the
/// orders rules/functions accept the phoneVerified marker while the flag is on.
const _kTempCode = '123456';

/// Phases of the verification mini-flow inside the panel.
enum _Phase { intro, sending, code, verifying }

/// Inline one-time-code verification of the checkout's WhatsApp number.
///
/// Shown only when the number still needs proving (no signed-in account
/// carries it). The panel walks the customer through: an explanation, the
/// SMS request, the 6-digit code, wrong-code retries with a small attempt
/// budget, resend with a cooldown, and expiry - and only then reports
/// [WhatsAppVerifyPanel.onVerified], at which point the checkout places the
/// order. Nothing else on the page is touched while it is open, and
/// cancelling leaves the session exactly as it was.
class WhatsAppVerifyPanel extends StatefulWidget {
  const WhatsAppVerifyPanel({
    super.key,
    required this.service,
    required this.canonicalPhone,
    required this.onVerified,
    required this.onCancel,
    this.sessionPhone,
    this.sessionEmail,
    this.autoRequestCode = false,
    this.fallbackAvailable = false,
  });

  /// The gateway that talks to Firebase Phone Auth (injected so tests can
  /// substitute a fake).
  final WhatsAppOtpService service;

  /// The number being proven, already canonical ('+91XXXXXXXXXX').
  final String canonicalPhone;

  /// Called once Firebase has verified the code. [freshSession] is true when
  /// a brand-new sign-in session was created for this number (guest checkout,
  /// or a replaced account session) - the checkout then signs it out again
  /// after the order is placed.
  final void Function({required bool freshSession}) onVerified;

  /// Called when the customer closes the panel without verifying.
  final VoidCallback onCancel;

  /// The signed-in account's own verified phone, when the customer is signed
  /// in under a DIFFERENT number. The panel then explains the order will be a
  /// guest order and their current sign-in ends when they verify.
  final String? sessionPhone;

  /// The signed-in account's email (for the disclosure copy), when known.
  final String? sessionEmail;

  /// When true, a freshly mounted panel in its intro phase requests a code
  /// in the frame after mounting. The checkout's compact 'Send OTP' offer
  /// re-opens the panel with this set, so the tap that says 'send' really
  /// sends; it only ever fires from the intro phase, once per mount, and a
  /// normal mount (default false) still waits for the customer to tap send.
  final bool autoRequestCode;

  /// True while the owner's temporary-code fallback is switched on
  /// (siteConfig/public whatsappCodeFallback). The intro then offers the
  /// published temporary code (123456) next to the SMS button, and an
  /// auto-requested open lands on the temp-code entry instead of firing a
  /// doomed SMS request.
  final bool fallbackAvailable;

  @override
  State<WhatsAppVerifyPanel> createState() => _WhatsAppVerifyPanelState();
}

class _WhatsAppVerifyPanelState extends State<WhatsAppVerifyPanel> {
  _Phase _phase = _Phase.intro;
  String? _verificationId;
  String? _notice;
  String? _errorMessage;
  int _attemptsLeft = _kMaxAttempts;
  bool _tempCodeMode = false;
  Timer? _ticker;
  int _secondsLeft = 0;
  final _code = TextEditingController();
  final _codeFocus = FocusNode();

  bool get _guestHandoff =>
      widget.sessionPhone != null &&
      widget.sessionPhone != widget.canonicalPhone;

  bool get _coolingDown => _secondsLeft > 0;

  /// Switches the panel to the temporary-code path: no SMS is requested or
  /// sent; the customer enters the published code and the panel reports
  /// verified with freshSession false (no auth session is created, so a
  /// guest placing an order this way stays a guest and a signed-in customer
  /// keeps their session - the orders gate accepts the marker while the
  /// owner's fallback flag is on).
  void _enterTempCode() {
    setState(() {
      _tempCodeMode = true;
      _phase = _Phase.code;
      _notice =
          'Temporary mode is on: enter the 6-digit code 123456 below. No '
          'SMS will arrive - your order is placed as soon as the code '
          'matches.';
      _errorMessage = null;
      _attemptsLeft = _kMaxAttempts;
      _code.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _codeFocus.requestFocus();
    });
  }

  @override
  void initState() {
    super.initState();
    _code.addListener(_codeChanged);
    // While the owner's fallback is on, a freshly mounted panel goes straight
    // to the temporary-code entry - the SMS path cannot work yet, so no
    // dead 'Send verification code' button is ever shown. With the flag off
    // this block is inert and behaviour is exactly as before.
    if (widget.fallbackAvailable || widget.autoRequestCode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _phase != _Phase.intro) return;
        if (widget.fallbackAvailable) {
          _enterTempCode();
        } else {
          _sendCode();
        }
      });
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _code.removeListener(_codeChanged);
    _code.dispose();
    _codeFocus.dispose();
    super.dispose();
  }

  void _codeChanged() {
    if (_phase == _Phase.code) setState(() {});
  }

  void _startTicker() {
    _ticker?.cancel();
    _secondsLeft = _kResendCooldown.inSeconds;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final left = _secondsLeft - 1;
      if (left <= 0) {
        _ticker?.cancel();
        setState(() => _secondsLeft = 0);
      } else {
        setState(() => _secondsLeft = left);
      }
    });
  }

  /// Requests a fresh code: first time, resend, and retry after a failure all
  /// land here. A new SMS invalidates the previous code and resets the
  /// attempt budget.
  Future<void> _sendCode() async {
    setState(() {
      _phase = _Phase.sending;
      _errorMessage = null;
      _notice = null;
    });
    final request = await widget.service.requestCode(widget.canonicalPhone);
    if (!mounted) return;
    if (request.ok) {
      setState(() {
        _verificationId = request.verificationId;
        _phase = _Phase.code;
        _attemptsLeft = _kMaxAttempts;
        _code.clear();
        _notice =
            'We sent a 6-digit code by SMS to '
            '${humanizeWhatsAppPhone(widget.canonicalPhone)}. It can take a '
            'minute to arrive - and it expires after a short while.';
      });
      _startTicker();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _codeFocus.requestFocus();
      });
    } else {
      setState(() {
        _phase = _Phase.intro;
        _errorMessage = request.message;
      });
    }
  }

  Future<void> _verify() async {
    final code = _code.text.trim();
    if (code.length < 6 || _phase == _Phase.verifying) return;
    // Temporary-code mode: never touches the service - the published code is
    // accepted locally and the orders rules/functions accept the marker
    // while the owner's fallback flag is on. No resend exists in this mode,
    // so the attempt budget resets instead of locking a customer out.
    if (_tempCodeMode) {
      if (code == _kTempCode) {
        widget.onVerified(freshSession: false);
        return;
      }
      setState(() {
        _attemptsLeft -= 1;
        if (_attemptsLeft <= 0) _attemptsLeft = _kMaxAttempts;
        _errorMessage =
            'That code is not right. The temporary code is 123456 - '
            '$_attemptsLeft attempt${_attemptsLeft == 1 ? '' : 's'} left.';
        _code.clear();
      });
      _codeFocus.requestFocus();
      return;
    }
    final id = _verificationId;
    if (id == null) return;
    setState(() {
      _phase = _Phase.verifying;
      _errorMessage = null;
    });
    final result = await widget.service.verifyCode(
      verificationId: id,
      code: code,
      canonicalPhone: widget.canonicalPhone,
    );
    if (!mounted) return;
    if (result.verified) {
      widget.onVerified(freshSession: result.freshSession);
      return;
    }
    setState(() {
      _phase = _Phase.code;
      _notice = null;
      switch (result.failure) {
        case OtpFailure.wrongCode:
          _attemptsLeft -= 1;
          if (_attemptsLeft <= 0) {
            _errorMessage =
                'Too many wrong attempts. Please request a new code.';
            // The copy asks for a new code, so make one possible right away
            // instead of waiting out the resend cooldown.
            _secondsLeft = 0;
            _ticker?.cancel();
          } else {
            _errorMessage =
                'That code is not right. $_attemptsLeft '
                'attempt${_attemptsLeft == 1 ? '' : 's'} left.';
          }
        case OtpFailure.expired:
          _errorMessage = 'That code has expired. Please request a new one.';
          // Same as above: the expired code is dead, so a new one must be
          // requestable immediately.
          _secondsLeft = 0;
          _ticker?.cancel();
        case OtpFailure.limited:
          _errorMessage = result.message;
        case OtpFailure.offline:
        case OtpFailure.notEnabled:
        case OtpFailure.onAnotherAccount:
        case OtpFailure.other:
          _errorMessage = result.message;
        // The service never returns a verified=false result without a
        // failure; be defensive anyway (e.g. a future caller).
        case null:
          _errorMessage =
              result.message ?? 'The code could not be verified. Try again.';
      }
      _code.clear();
    });
    _codeFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final busy = _phase == _Phase.sending || _phase == _Phase.verifying;
    return Container(
      key: const Key('whatsapp-verify-panel'),
      padding: EdgeInsets.all(width >= 480 ? 22 : 18),
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
                  style: MxType.h4(color: MxColors.charcoal),
                ),
              ),
              IconButton(
                onPressed: busy ? null : widget.onCancel,
                tooltip: 'Close verification',
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.close_rounded,
                  size: 18,
                  color: MxColors.stone,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _tempCodeMode
                ? 'Temporary mode is on for now: enter the 6-digit code '
                      '123456 below to place your order - no SMS is needed and '
                      'nothing is charged.'
                : 'Before we take your order we need to confirm this number is '
                      'reachable. A 6-digit code is sent by SMS to '
                      '${humanizeWhatsAppPhone(widget.canonicalPhone)} - your order is '
                      'placed only after the code is verified. Nothing is charged.',
            style: MxType.bodySm(color: MxColors.stone),
          ),
          if (_guestHandoff && !_tempCodeMode) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MxColors.warnSoft,
                borderRadius: BorderRadius.circular(MxRadius.sm),
                border: Border.all(
                  color: MxColors.warn.withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: MxColors.warn,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This number is different from the phone on your '
                      'signed-in account, so this order is placed as a guest '
                      'and your current sign-in ends when you verify. You can '
                      'sign back in any time.',
                      style: MxType.bodyXs(color: MxColors.charcoalSoft),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (_notice != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _tempCodeMode ? Icons.bolt_rounded : Icons.sms_outlined,
                  size: 15,
                  color: MxColors.moss,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _notice!,
                    style: MxType.bodyXs(color: MxColors.charcoalSoft),
                  ),
                ),
              ],
            ),
          ],
          if (_errorMessage != null) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  size: 15,
                  color: MxColors.danger,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: MxType.bodyXs(
                      color: MxColors.danger,
                      weight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 14),
          if (_phase == _Phase.sending)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 10),
                  Text('Sending your code...'),
                ],
              ),
            ),
          if (_phase == _Phase.code) ...[
            TextField(
              key: const Key('whatsapp-otp-code'),
              controller: _code,
              focusNode: _codeFocus,
              enabled: !busy,
              autofillHints: const [AutofillHints.oneTimeCode],
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              maxLength: 6,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              onSubmitted: (_) => _verify(),
              style: TextStyle(
                fontSize: 22,
                letterSpacing: 10,
                fontWeight: FontWeight.w700,
                color: MxColors.charcoal,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                labelText: '6-digit code',
                hintText: '000000',
                counterText: '',
                prefixIcon: const Icon(Icons.pin_outlined, size: 20),
                filled: true,
                fillColor: MxColors.parchment,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MxRadius.md),
                  borderSide: const BorderSide(color: MxColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(MxRadius.md),
                  borderSide: const BorderSide(color: MxColors.line),
                ),
              ),
            ),
            if (_phase == _Phase.code && !busy && !_tempCodeMode) ...[
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  key: const Key('whatsapp-otp-resend'),
                  onPressed: (_verificationId == null || _coolingDown)
                      ? null
                      : _sendCode,
                  icon: const Icon(Icons.refresh_rounded, size: 15),
                  label: Text(
                    _coolingDown
                        ? 'Resend code in $_secondsLeft s'
                        : 'Resend code',
                  ),
                ),
              ),
            ],
          ],
          if (widget.fallbackAvailable &&
              _phase == _Phase.intro &&
              !_tempCodeMode) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('whatsapp-otp-use-temp-code'),
                onPressed: _enterTempCode,
                icon: const Icon(Icons.bolt_rounded, size: 16),
                label: const Text(
                  'SMS not working? Use the temporary code 123456 for now',
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: _phase == _Phase.code
                      ? FilledButton(
                          key: const Key('whatsapp-otp-verify'),
                          onPressed: _code.text.trim().length == 6 && !busy
                              ? _verify
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: MxColors.forest,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: MxColors.stoneLight
                                .withValues(alpha: 0.25),
                            disabledForegroundColor: MxColors.stone,
                          ),
                          child: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Verify & place order'),
                        )
                      : FilledButton.icon(
                          key: const Key('whatsapp-otp-send'),
                          onPressed: busy ? null : _sendCode,
                          style: FilledButton.styleFrom(
                            backgroundColor: MxColors.forest,
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.sms_outlined, size: 17),
                          label: const Text('Send verification code'),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
