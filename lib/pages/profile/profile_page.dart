import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../services/display_mode.dart';
import '../../state/customer_auth_controller.dart';
import '../../utils/validators.dart';
import '../../widgets/page.dart';
import '../../widgets/shell.dart';

/// Customer account page.
///
/// Signed out: sign in, create an account, or recover a password — all real
/// Firebase Auth flows with customer-safe error messages. In an *installed*
/// app (PWA, standalone display mode) the Wishlist and My Orders sections are
/// shown below the forms, locked and clearly asking for a sign-in, so an
/// installed user always sees where they belong; in a normal browser tab
/// those account sections stay hidden until a customer is signed in.
///
/// Signed in: the customer's name is the page — big, front and centre — with
/// their email small underneath, and one clean card linking to their
/// Wishlist and My Orders, their account details and sign out.
class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, this.returnRoute, this.initialMode});

  /// The named route to return to after a successful sign-in when the
  /// customer was sent here to unlock something. Always an in-app route.
  final String? returnRoute;

  /// Which auth tab to open with (defaults to sign-in).
  final AuthStartMode? initialMode;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

enum _AuthMode { signIn, register, reset }

class _ProfilePageState extends State<ProfilePage> {
  late _AuthMode _mode;

  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode == AuthStartMode.register
        ? _AuthMode.register
        : _AuthMode.signIn;
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  CustomerAuthController get _auth => context.read<CustomerAuthController>();

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    setState(() => _busy = true);
    final ok = switch (_mode) {
      _AuthMode.signIn => await _auth.signIn(
          email: _email.text,
          password: _password.text,
        ),
      _AuthMode.register => await _auth.register(
          name: _name.text,
          email: _email.text,
          password: _password.text,
        ),
      _AuthMode.reset => await _auth.sendPasswordReset(email: _email.text),
    };
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
                      ? _displayName(auth)
                      : _modeTitle,
                  style: MxType.h1(MediaQuery.of(context).size.width),
                ),
                const SizedBox(height: 8),
                Text(
                  status == CustomerAuthStatus.signedIn
                      ? (auth.email ?? '—')
                      : _modeSubtitle,
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                const SizedBox(height: 28),
                switch (status) {
                  CustomerAuthStatus.backendOffline => const _OfflinePanel(),
                  CustomerAuthStatus.resolving => const _ResolvingPanel(),
                  CustomerAuthStatus.signedOut => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AuthPanel(
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
                        // Installed-app users always see where their Wishlist
                        // and My Orders live, locked until they sign in. In a
                        // browser tab these stay out of the signed-out page.
                        if (isStandaloneDisplay()) ...[
                          const SizedBox(height: 28),
                          const _LockedSections(),
                        ],
                      ],
                    ),
                  CustomerAuthStatus.signedIn => _AccountHub(
                      auth: auth,
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

  /// The customer's name as shown on the account page. Prefers the name they
  /// gave when registering; older accounts that only have an email show the
  /// local part of their own email (clearly theirs) rather than a fake name.
  static String _displayName(CustomerAuthController auth) {
    final name = auth.displayName?.trim();
    if (name != null && name.isNotEmpty) return name;
    final email = auth.email;
    if (email == null || email.isEmpty) return 'there';
    final local = email.split('@').first.trim();
    if (local.isEmpty) return 'there';
    return local[0].toUpperCase() + local.substring(1);
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
                        tooltip: obscure ? 'Show password' : 'Hide password',
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

/// The signed-in account view: name front and centre, email small, and one
/// clean card linking to the customer's Wishlist, My Orders, details and
/// sign out.
class _AccountHub extends StatelessWidget {
  const _AccountHub({required this.auth, required this.onSignOut});

  final CustomerAuthController auth;
  final Future<void> Function() onSignOut;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        MxPanel(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (auth.message != null) ...[
                _FeedbackBanner(kind: 'error', text: auth.message!),
                const SizedBox(height: 14),
              ],
              if (auth.notice != null) ...[
                _FeedbackBanner(kind: 'ok', text: auth.notice!),
                const SizedBox(height: 14),
              ],
              _AccountTile(
                icon: Icons.favorite_border_rounded,
                title: 'Wishlist',
                subtitle: 'Products you saved',
                onTap: () => Navigator.of(context).pushNamed(Routes.wishlist),
              ),
              const Divider(color: MxColors.line, height: 1),
              _AccountTile(
                icon: Icons.receipt_long_outlined,
                title: 'My Orders',
                subtitle: 'Follow your orders',
                onTap: () => Navigator.of(context).pushNamed(Routes.myOrders),
              ),
              const Divider(color: MxColors.line, height: 1),
              _AccountTile(
                icon: Icons.email_outlined,
                title: auth.email ?? 'Email',
                subtitle: auth.memberSince != null
                    ? 'Member since ${_monthYear(auth.memberSince!)}'
                    : 'Your sign-in email',
                onTap: null,
              ),
              if (!auth.emailVerified) ...[
                const SizedBox(height: 14),
                const _UnverifiedCard(),
              ],
              const SizedBox(height: 20),
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

class _AccountTile extends StatelessWidget {
  const _AccountTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tile = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: MxColors.mossTint,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 21, color: MxColors.moss),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ],
            ),
          ),
          if (onTap != null)
            const Icon(Icons.chevron_right_rounded,
                size: 22, color: MxColors.stone),
        ],
      ),
    );
    if (onTap == null) return tile;
    return Semantics(
      button: true,
      label: title,
      hint: subtitle,
      child: InkWell(onTap: onTap, child: tile),
    );
  }
}

class _UnverifiedCard extends StatelessWidget {
  const _UnverifiedCard();

  @override
  Widget build(BuildContext context) {
    final auth = context.read<CustomerAuthController>();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
          const SizedBox(height: 4),
          Text(
            'Tap the link we emailed you to confirm this address. It only '
            'affects account notifications — you can keep ordering meanwhile.',
            style: MxType.bodyXs(color: MxColors.charcoalSoft),
          ),
          const SizedBox(height: 10),
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

/// Locked Wishlist / My Orders cards shown to installed-app users before
/// sign-in, so the sections always exist there — locked, never fake.
class _LockedSections extends StatelessWidget {
  const _LockedSections();

  @override
  Widget build(BuildContext context) {
    final page = context.findAncestorStateOfType<_ProfilePageState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('On this app', style: MxType.label(color: MxColors.earth)),
        const SizedBox(height: 12),
        _LockedTile(
          icon: Icons.favorite_border_rounded,
          title: 'Wishlist',
          subtitle:
              'Save products while you browse, and find them again on any '
              'device.',
          onSignIn: () => page?._switchMode(_AuthMode.signIn),
          onCreate: () => page?._switchMode(_AuthMode.register),
        ),
        const SizedBox(height: 10),
        _LockedTile(
          icon: Icons.receipt_long_outlined,
          title: 'My Orders',
          subtitle:
              'Follow your orders from confirmation to your door.',
          onSignIn: () => page?._switchMode(_AuthMode.signIn),
          onCreate: () => page?._switchMode(_AuthMode.register),
        ),
      ],
    );
  }
}

class _LockedTile extends StatelessWidget {
  const _LockedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onSignIn,
    required this.onCreate,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onSignIn;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return MxPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Icon(icon, size: 26, color: MxColors.stone),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: onSignIn,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Sign in'),
                    ),
                    const SizedBox(width: 4),
                    TextButton(
                      onPressed: onCreate,
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Create account'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Icon(Icons.lock_outline_rounded,
              size: 18, color: MxColors.stoneLight),
        ],
      ),
    );
  }
}
