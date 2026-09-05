import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../router/routes.dart';
import '../../state/admin_reveal.dart';
import '../../state/auth_controller.dart';
import '../../widgets/brand.dart';
import 'admin_access_lock.dart';
import 'admin_scaffold.dart';

/// Entry point for the hidden admin area.
///
/// Nothing at /admin is visible until it is summoned: a signed-in
/// administrator (persisted Firebase session) lands on the real gate body; a
/// visitor who has long-pressed the wordmark sees the access-code door
/// ([AdminAccessLock]); one who has typed the owner phrase goes straight to
/// the sign-in page; and everyone else — including a direct /admin visit — is
/// handed off to the public home route, so the admin page has no discoverable
/// URL. All authorisation decisions come from [AuthController] state, never
/// from a client flag.
class AdminGate extends StatelessWidget {
  const AdminGate({super.key, this.lock});

  /// Overridable for tests; production uses [AdminAccessLock.shared].
  final AdminAccessLock? lock;

  @override
  Widget build(BuildContext context) {
    final l = lock ?? AdminAccessLock.shared;
    final auth = context.watch<AuthController>();
    return ListenableBuilder(
      listenable: AdminReveal.shared,
      builder: (context, _) {
        // A persisted session always reaches the real gate body — an admin
        // who is signed in never needs to summon anything.
        if (auth.user != null) return const _AdminGateBody();
        switch (AdminReveal.shared.stage) {
          case AdminRevealStage.door:
            return ValueListenableBuilder<bool>(
              valueListenable: l.unlocked,
              builder: (context, unlocked, _) =>
                  unlocked ? const _AdminGateBody() : _AccessDoorView(lock: l),
            );
          case AdminRevealStage.signIn:
            return const _AdminGateBody();
          case AdminRevealStage.hidden:
            // Not summoned: while auth is still restoring (persisted session
            // check) show nothing; afterwards hand off to the public site.
            if (auth.resolving) return const _CovertQuiet();
            return const _CovertHandoff();
        }
      },
    );
  }
}

class _AdminGateBody extends StatelessWidget {
  const _AdminGateBody();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthController>();
    final status = resolveAdminGate(
      backendAvailable: auth.backendAvailable,
      resolving: auth.resolving,
      signedIn: auth.user != null,
      isAdmin: auth.isAdmin,
    );
    switch (status) {
      case AdminGateStatus.backendOffline:
        return const _BackendOfflineView();
      case AdminGateStatus.resolving:
        return const _AdminChrome(child: _ResolvingView());
      case AdminGateStatus.signInRequired:
        return const AdminSignInView();
      case AdminGateStatus.notAdmin:
        return _NotAuthorizedView(auth: auth);
      case AdminGateStatus.admin:
        return const AdminScaffold();
    }
  }
}

/// Shared light frame (cream background + brand lockup + escape to the site).
class _AdminChrome extends StatelessWidget {
  const _AdminChrome({required this.child, this.tag = 'Admin'});

  final Widget child;
  final String tag;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MxColors.cream,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _BrandRow(tag: tag),
                  const SizedBox(height: 28),
                  child,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BrandRow extends StatelessWidget {
  const _BrandRow({this.tag = 'Admin'});

  final String tag;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const MxLogo(size: 40, showFull: false),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('MYCOSIX', style: MxType.labelLg(color: MxColors.forest)),
            Text(tag, style: MxType.bodyXs(color: MxColors.stone)),
          ],
        ),
      ],
    );
  }
}

class _ResolvingView extends StatelessWidget {
  const _ResolvingView();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.6),
        ),
      ),
    );
  }
}

/// Firebase not initialised: say so plainly. No fake login is offered.
class _BackendOfflineView extends StatelessWidget {
  const _BackendOfflineView();

  @override
  Widget build(BuildContext context) {
    return _AdminChrome(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.lg),
          border: Border.all(color: MxColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              color: MxColors.stone,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              'The admin area needs a live backend.',
              textAlign: TextAlign.center,
              style: MxType.h4(color: MxColors.charcoal),
            ),
            const SizedBox(height: 8),
            Text(
              'Firebase is not connected in this build, so there is nothing to '
              'sign in to yet. The admin dashboard appears automatically once '
              'the Firebase backend is connected.',
              textAlign: TextAlign.center,
              style: MxType.bodySm(color: MxColors.stone),
            ),
            const SizedBox(height: 20),
            Center(child: _LeaveButton(onPressed: () => _goHome(context))),
          ],
        ),
      ),
    );
  }
}

/// Signed in but not granted administrator access.
class _NotAuthorizedView extends StatelessWidget {
  const _NotAuthorizedView({required this.auth});

  final AuthController auth;

  @override
  Widget build(BuildContext context) {
    final email = auth.user?.email ?? 'this account';
    final uid = auth.user?.uid;
    return _AdminChrome(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.lg),
          border: Border.all(color: MxColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.lock_outline_rounded,
              color: MxColors.warn,
              size: 30,
            ),
            const SizedBox(height: 12),
            Text(
              'This account is not an administrator.',
              textAlign: TextAlign.center,
              style: MxType.h4(color: MxColors.charcoal),
            ),
            const SizedBox(height: 8),
            Text(
              '$email is signed in, but it has not been granted admin access '
              'on this project.',
              textAlign: TextAlign.center,
              style: MxType.bodySm(color: MxColors.stone),
            ),
            if (uid != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: MxColors.cream,
                  borderRadius: BorderRadius.circular(MxRadius.sm),
                  border: Border.all(color: MxColors.line),
                ),
                child: SelectableText(
                  'Your account ID: $uid',
                  textAlign: TextAlign.center,
                  style: MxType.bodyXs(color: MxColors.charcoalSoft),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The owner can grant access by adding this ID to the admins '
                'list in the Firebase console.',
                textAlign: TextAlign.center,
                style: MxType.bodyXs(color: MxColors.stoneLight),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => _goHome(context),
                  child: const Text('Back to site'),
                ),
                const SizedBox(width: 12),
                FilledButton.tonal(
                  onPressed: () => auth.signOut(),
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

void _goHome(BuildContext context) {
  Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
}

/// Email/password sign-in. No hardcoded credentials are ever used; failures
/// surface as customer-safe messages.
class AdminSignInView extends StatefulWidget {
  const AdminSignInView({super.key});

  @override
  State<AdminSignInView> createState() => _AdminSignInViewState();
}

class _AdminSignInViewState extends State<AdminSignInView> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _inlineError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthController>();
    auth.clearMessage();
    setState(() {
      _busy = true;
      _inlineError = null;
    });
    await auth.signIn(_email.text, _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _inlineError = auth.message;
    });
  }

  Future<void> _reset() async {
    final auth = context.read<AuthController>();
    final e = _email.text.trim();
    if (e.isEmpty) {
      setState(() => _inlineError = 'Enter the email first, then reset.');
      return;
    }
    setState(() => _busy = true);
    final ok = await auth.sendPasswordReset(e);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _inlineError = ok ? 'Password reset email sent to $e.' : auth.message;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.read<AuthController>();
    final message = _inlineError ?? (auth.resolving ? null : auth.message);
    return _AdminChrome(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.lg),
          border: Border.all(color: MxColors.line),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Sign in to the admin area',
                textAlign: TextAlign.center,
                style: MxType.h3(color: MxColors.charcoal),
              ),
              const SizedBox(height: 4),
              Text(
                'Administrator email + password (set up in Firebase).',
                textAlign: TextAlign.center,
                style: MxType.bodyXs(color: MxColors.stone),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autofillHints: const [AutofillHints.username],
                decoration: const InputDecoration(
                  labelText: 'Email',
                  prefixIcon: Icon(Icons.mail_outline_rounded),
                ),
                validator: (v) {
                  final t = v?.trim() ?? '';
                  final ok = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(t);
                  return ok ? null : 'Enter a valid email address';
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _password,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock_outline_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').length >= 6 ? null : 'Enter your password',
              ),
              if (message != null) ...[
                const SizedBox(height: 12),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: MxType.bodyXs(
                    color: message.startsWith('Password reset email sent')
                        ? MxColors.ok
                        : MxColors.danger,
                  ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      )
                    : const Text('Sign in'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: _busy ? null : _reset,
                  child: const Text('Forgot password?'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Locked prompt shown until the access code opens the sign-in page.
class _AccessDoorView extends StatefulWidget {
  const _AccessDoorView({required this.lock});

  final AdminAccessLock lock;

  @override
  State<_AccessDoorView> createState() => _AccessDoorViewState();
}

class _AccessDoorViewState extends State<_AccessDoorView> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  void _submit() {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = widget.lock.tryUnlock(_code.text);
    if (!mounted) return;
    // On success AdminGate's listener swaps this view for the real admin body;
    // on a wrong code, surface the error and let the admin try again.
    if (!ok) {
      setState(() {
        _busy = false;
        _error = 'That code is not recognised.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _AdminChrome(
      tag: 'Private',
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: MxColors.creamSoft,
          borderRadius: BorderRadius.circular(MxRadius.lg),
          border: Border.all(color: MxColors.line),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(
                Icons.lock_outline_rounded,
                color: MxColors.earth,
                size: 28,
              ),
              const SizedBox(height: 12),
              Text(
                'Restricted area',
                textAlign: TextAlign.center,
                style: MxType.h3(color: MxColors.charcoal),
              ),
              const SizedBox(height: 6),
              Text(
                'This page is private. Enter the access code to continue.',
                textAlign: TextAlign.center,
                style: MxType.bodySm(color: MxColors.stone),
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _code,
                autofocus: true,
                obscureText: _obscure,
                autocorrect: false,
                enableSuggestions: false,
                onFieldSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: 'Access code',
                  prefixIcon: const Icon(Icons.key_rounded),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                    onPressed: () => setState(() => _obscure = !_obscure),
                  ),
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter the access code' : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: MxType.bodyXs(color: MxColors.danger),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: _busy ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: const Text('Continue'),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.center,
                child: TextButton(
                  onPressed: () => _goHome(context),
                  child: const Text('Back to the site'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LeaveButton extends StatelessWidget {
  const _LeaveButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      child: const Text('Back to the site'),
    );
  }
}

/// Featureless cream page shown at /admin while a persisted session check is
/// still running. Nothing advertises that a private area exists.
class _CovertQuiet extends StatelessWidget {
  const _CovertQuiet();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MxColors.cream,
      body: SizedBox.shrink(),
    );
  }
}

/// Not summoned and not signed in: replace the /admin route with the public
/// home route so a direct visit only ever lands on the normal site.
class _CovertHandoff extends StatefulWidget {
  const _CovertHandoff();

  @override
  State<_CovertHandoff> createState() => _CovertHandoffState();
}

class _CovertHandoffState extends State<_CovertHandoff> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _handoff());
  }

  void _handoff() {
    if (!mounted) return;
    // If the admin summoned the area in the same frame, let AdminGate rebuild
    // into the door/sign-in instead of handing off.
    if (AdminReveal.shared.stage != AdminRevealStage.hidden) return;
    Navigator.of(context).pushNamedAndRemoveUntil(Routes.home, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: MxColors.cream,
      body: SizedBox.shrink(),
    );
  }
}
