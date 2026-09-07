import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../state/customer_auth_controller.dart';
import '../../utils/validators.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

/// Customer account page.
///
/// Signed out: sign in, create an account, or recover a password — all real
/// Firebase Auth flows with customer-safe error messages. Signed in: the
/// session card (verification status, resend link, sign out).
///
/// [returnRoute] is the page to return to after a successful sign-in when the
/// customer was sent here to unlock something (a wishlist save, an order
/// action). It is always a named route in this app's own route table — never
/// a raw URL from outside.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.returnRoute});

  final String? returnRoute;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

enum _AuthMode { signIn, register, reset }

class _ProfilePageState extends State<ProfilePage> {
  _AuthMode _mode = _AuthMode.signIn;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  CustomerAuthController get _auth =>
      context.read<CustomerAuthController>();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    bool ok;
    switch (_mode) {
      case _AuthMode.signIn:
        ok = await _auth.signIn(
          email: _email.text,
          password: _password.text,
        );
      case _AuthMode.register:
        ok = await _auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
        );
      case _AuthMode.reset:
        ok = await _auth.sendPasswordReset(email: _email.text);
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (!ok) return;
    // Reset stays on the form (a notice confirms the send). Sign-in and
    // registration either return to the page that sent the customer here, or
    // land on the account view below.
    if (_mode == _AuthMode.reset) {
      _switchMode(_AuthMode.signIn);
    } else if (widget.returnRoute != null) {
      Navigator.of(context).pushReplacementNamed(widget.returnRoute!);
    }
  }

  void _switchMode(_AuthMode mode) {
    _auth.clearMessage();
    _password.clear();
    _confirm.clear();
    setState(() => _mode = mode);
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<CustomerAuthController>();
    final status = resolveCustomerAuthStatus(
      backendAvailable: auth.backendAvailable,
      resolving: auth.resolving,
      signedIn: auth.user != null,
    );

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
                Text(
                  status == CustomerAuthStatus.signedIn
                      ? 'Hello ${auth.displayName ?? auth.email ?? 'there'}'
                      : _modeTitle,
                  style: MxType.h1(MediaQuery.of(context).size.width),
                ),
                const SizedBox(height: 10),
                Text(
                  status == CustomerAuthStatus.signedIn
                      ? 'You are signed in to your MYCOSIX account.'
                      : _modeSubtitle,
                  style: MxType.bodySm(color: MxColors.stone),
                ),
                const SizedBox(height: 32),
                switch (status) {
                  CustomerAuthStatus.backendOffline => const _OfflinePanel(),
                  CustomerAuthStatus.resolving => const _ResolvingPanel(),
                  CustomerAuthStatus.signedOut => _AuthPanel(
                      mode: _mode,
                      formKey: _formKey,
                      name: _name,
                      email: _email,
                      password: _password,
                      confirm: _confirm,
                      obscure: _obscure,
                      busy: _busy,
                      onToggleObscure: () =>
                          setState(() => _obscure = !_obscure),
                      onSubmit: _submit,
                      onSwitchMode: _switchMode,
                    ),
                  CustomerAuthStatus.signedIn => _AccountPanel(
                      onSignOut: () => _auth.signOut(),
                    ),
                },
                const SizedBox(height: 96),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _modeTitle => switch (_mode) {
        _AuthMode.signIn => 'Welcome back',
        _AuthMode.register => 'Create your account',
        _AuthMode.reset => 'Reset your password',
      };

  String get _modeSubtitle => switch (_mode) {
        _AuthMode.signIn =>
          'Sign in to save products to your wishlist, keep your cart across '
          'devices, and follow your orders.',
        _AuthMode.register =>
          'One account for your wishlist, your cart and your orders — across '
          'the website and the installed app.',
        _AuthMode.reset =>
          'Enter your account email and we will send you a reset link.',
      };
}

/// Full-width feedback banner (error or confirmation) above the form.
class _FeedbackBanner extends StatelessWidget {
  const _FeedbackBanner({required this.kind, required this.text});

  final String kind; // 'error' | 'ok'
  final String text;

  @override
  Widget build(BuildContext context) {
    final isError = kind == 'error';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: isError
            ? MxColors.danger.withValues(alpha: 0.08)
            : MxColors.ok.withValues(alpha: 0.10),
        border: Border.all(
          color: isError
              ? MxColors.danger.withValues(alpha: 0.35)
              : MxColors.ok.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : Icons.check_circle_outline,
            size: 18,
            color: isError ? MxColors.danger : MxColors.ok,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: MxType.bodySm(
                color: isError ? MxColors.danger : MxColors.ok,
                weight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflinePanel extends StatelessWidget {
  const _OfflinePanel();

  @override
  Widget build(BuildContext context) {
    return MxPanel(
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined,
              size: 34, color: MxColors.stone),
          const SizedBox(height: 14),
          Text(
            'We cannot reach the sign-in service right now. Please check your '
            'connection and try again in a moment — your cart keeps working '
            'in the meantime.',
            textAlign: TextAlign.center,
            style: MxType.bodySm(color: MxColors.charcoalSoft),
          ),
        ],
      ),
    );
  }
}

class _ResolvingPanel extends StatelessWidget {
  const _ResolvingPanel();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 48),
        child: CircularProgressIndicator(color: MxColors.moss),
      ),
    );
  }
}

class _AuthPanel extends StatelessWidget {
  const _AuthPanel({
    required this.mode,
    required this.formKey,
    required this.name,
    required this.email,
    required this.password,
    required this.confirm,
    required this.obscure,
    required this.busy,
    required this.onToggleObscure,
    required this.onSubmit,
    required this.onSwitchMode,
  });

  final _AuthMode mode;
  final GlobalKey<FormState> formKey;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController password;
  final TextEditingController confirm;
  final bool obscure;
  final bool busy;
  final VoidCallback onToggleObscure;
  final Future<void> Function() onSubmit;
  final void Function(_AuthMode) onSwitchMode;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<CustomerAuthController>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mode tabs (reset is reached from a link under the sign-in form).
        if (mode != _AuthMode.reset)
          Row(
            children: [
              Expanded(
                child: _ModeTab(
                  label: 'Sign in',
                  selected: mode == _AuthMode.signIn,
                  onTap: () => onSwitchMode(_AuthMode.signIn),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ModeTab(
                  label: 'Create account',
                  selected: mode == _AuthMode.register,
                  onTap: () => onSwitchMode(_AuthMode.register),
                ),
              ),
            ],
          ),
        if (mode != _AuthMode.reset) const SizedBox(height: 22),

        MxPanel(
          padding: const EdgeInsets.all(26),
          child: Form(
            key: formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (auth.message != null) ...[
                  _FeedbackBanner(kind: 'error', text: auth.message!),
                  const SizedBox(height: 18),
                ],
                if (auth.notice != null) ...[
                  _FeedbackBanner(kind: 'ok', text: auth.notice!),
                  const SizedBox(height: 18),
                ],

                if (mode == _AuthMode.register) ...[
                  TextFormField(
                    controller: name,
                    textInputAction: TextInputAction.next,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: 'Full name *',
                      hintText: 'What should we call you?',
                      prefixIcon: Icon(Icons.person_outline_rounded, size: 20),
                    ),
                    validator: FormValidators.name,
                  ),
                  const SizedBox(height: 14),
                ],

                TextFormField(
                  controller: email,
                  textInputAction: TextInputAction.next,
                  keyboardType: TextInputType.emailAddress,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  decoration: const InputDecoration(
                    labelText: 'Email *',
                    hintText: 'you@example.com',
                    prefixIcon: Icon(Icons.mail_outline_rounded, size: 20),
                  ),
                  validator: FormValidators.email,
                ),
                const SizedBox(height: 14),

                if (mode != _AuthMode.reset) ...[
                  TextFormField(
                    controller: password,
                    textInputAction: mode == _AuthMode.register
                        ? TextInputAction.next
                        : TextInputAction.done,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: InputDecoration(
                      labelText: 'Password *',
                      hintText: mode == _AuthMode.register
                          ? 'At least 8 characters'
                          : 'Your password',
                      prefixIcon:
                          const Icon(Icons.lock_outline_rounded, size: 20),
                      suffixIcon: IconButton(
                        onPressed: onToggleObscure,
                        tooltip: obscure
                            ? 'Show password'
                            : 'Hide password',
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                        ),
                      ),
                    ),
                    validator: mode == _AuthMode.register
                        ? FormValidators.newPassword
                        : FormValidators.password,
                  ),
                  const SizedBox(height: 14),
                ],

                if (mode == _AuthMode.register) ...[
                  TextFormField(
                    controller: confirm,
                    textInputAction: TextInputAction.done,
                    obscureText: obscure,
                    autocorrect: false,
                    enableSuggestions: false,
                    autovalidateMode: AutovalidateMode.onUserInteraction,
                    decoration: const InputDecoration(
                      labelText: 'Confirm password *',
                      hintText: 'Same password again',
                      prefixIcon: Icon(Icons.lock_outline_rounded, size: 20),
                    ),
                    validator: (value) =>
                        value != password.text ? 'Passwords do not match' : null,
                  ),
                  const SizedBox(height: 14),
                ],

                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: busy ? null : onSubmit,
                    style: FilledButton.styleFrom(
                      backgroundColor: MxColors.forest,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 17),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    child: busy
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            switch (mode) {
                              _AuthMode.signIn => 'Sign in',
                              _AuthMode.register => 'Create account',
                              _AuthMode.reset => 'Send reset link',
                            },
                            style: const TextStyle(
                              fontFamily: 'Manrope',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                  ),
                ),

                if (mode == _AuthMode.signIn) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: () => onSwitchMode(_AuthMode.reset),
                      child: const Text('Forgot your password?'),
                    ),
                  ),
                ],
                if (mode == _AuthMode.reset) ...[
                  const SizedBox(height: 14),
                  Center(
                    child: TextButton(
                      onPressed: () => onSwitchMode(_AuthMode.signIn),
                      child: const Text('Back to sign in'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: selected ? MxColors.forest : MxColors.creamSoft,
          border: Border.all(
            color: selected ? MxColors.forest : MxColors.line,
          ),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 13,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: selected ? Colors.white : MxColors.charcoalSoft,
            ),
          ),
        ),
      ),
    );
  }
}

class _AccountPanel extends StatelessWidget {
  const _AccountPanel({required this.onSignOut});

  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<CustomerAuthController>();
    final name = auth.displayName;
    final email = auth.email ?? '—';
    final initial =
        (name?.isNotEmpty == true) ? name!.characters.first.toUpperCase() : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MxPanel(
          padding: const EdgeInsets.all(26),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 27,
                    backgroundColor: MxColors.mossSoft,
                    foregroundColor: MxColors.forest,
                    child: initial != null
                        ? Text(
                            initial,
                            style: const TextStyle(
                              fontFamily: 'Fraunces',
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : const Icon(Icons.person_rounded, size: 26),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (name?.isNotEmpty == true) ...[
                          Text(
                            name!,
                            style: MxType.h4(color: MxColors.charcoal),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          email,
                          style: MxType.bodySm(color: MxColors.stone),
                        ),
                      ],
                    ),
                  ),
                  _VerifiedChip(verified: auth.emailVerified),
                ],
              ),
              if (auth.memberSince != null) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Member since ${_monthYear(auth.memberSince!)}',
                    style: MxType.bodyXs(),
                  ),
                ),
              ],
              const SizedBox(height: 22),
              if (auth.message != null) ...[
                _FeedbackBanner(kind: 'error', text: auth.message!),
                const SizedBox(height: 18),
              ],
              if (auth.notice != null) ...[
                _FeedbackBanner(kind: 'ok', text: auth.notice!),
                const SizedBox(height: 18),
              ],
              if (!auth.emailVerified) ...[
                _UnverifiedCard(auth: auth),
                const SizedBox(height: 18),
              ],
              const _CartSyncNote(),
              const SizedBox(height: 22),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout_rounded, size: 19),
                  label: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static String _monthYear(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[d.month - 1]} ${d.year}';
  }
}

class _VerifiedChip extends StatelessWidget {
  const _VerifiedChip({required this.verified});

  final bool verified;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: verified
            ? MxColors.ok.withValues(alpha: 0.12)
            : MxColors.earth.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            verified
                ? Icons.verified_outlined
                : Icons.mark_email_unread_outlined,
            size: 13,
            color: verified ? MxColors.ok : MxColors.earth,
          ),
          const SizedBox(width: 5),
          Text(
            verified ? 'Verified' : 'Not verified',
            style: TextStyle(
              fontFamily: 'Manrope',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: verified ? MxColors.ok : MxColors.earth,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnverifiedCard extends StatelessWidget {
  const _UnverifiedCard({required this.auth});

  final CustomerAuthController auth;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MxColors.mossTint,
        border: Border.all(color: MxColors.mossSoft),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Verify your email',
            style: MxType.bodySm(
              color: MxColors.forest,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap the link we emailed you to confirm this address. It only '
            'affects account notifications — you can keep ordering meanwhile.',
            style: MxType.bodyXs(color: MxColors.charcoalSoft),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: () => auth.resendEmailVerification(),
                child: const Text('Resend link'),
              ),
              TextButton(
                onPressed: () => auth.refreshUser(),
                child: const Text("I've tapped it — refresh"),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CartSyncNote extends StatelessWidget {
  const _CartSyncNote();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.sync_rounded, size: 16, color: MxColors.moss),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Your cart is saved to your account, so it follows you between '
            'this browser and the installed app.',
            style: MxType.bodyXs(color: MxColors.stone),
          ),
        ),
      ],
    );
  }
}
