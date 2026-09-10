import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../config/mx_colors.dart';
import '../../../config/mx_type.dart';
import '../../../firebase/fb_admin.dart';
import '../../../state/auth_controller.dart';
import '../../../utils/admin_emails.dart';
import '../admin_widgets.dart';

/// Admins manager.
///
/// Who runs the shop: the roster of every admin grant, an "add an
/// administrator" action, and the signed-in admin's own secret code. It lives
/// inside the dashboard, so everyone who reaches it is already an admin - the
/// Firestore rules re-check every write below against the `admins/{uid}` grant
/// and the `adminCodes/{email}` rows, so a capability here is never implied by
/// being on the page.
///
/// * **Roster** — every `admins/{uid}` grant (readable to any admin), each
///   showing the email it was granted for and when it was added. A legacy
///   grant from before per-email codes existed has no email stored yet and
///   shows its id until that admin signs in and sets their own code.
/// * **Add an administrator** — an admin picks an email and a secret code for
///   that person. The code is stored unreadably in `adminCodes/{email}` and
///   never shown back; the invitee signs in (Google or email) and enters the
///   code once to unlock the area. Codes are exact - the person can only use
///   the one set for their email.
/// * **My admin code** — each admin can change only their own code. There is
///   no way (and no rule) to change another administrator's code once it has
///   been claimed.
///
/// Removing an admin is a deliberate, owner-only action and is done in the
/// Firebase console (delete the `admins/{uid}` row and its `adminCodes/{email}`
/// row) - no client can revoke an admin, by design.
class AdminsSection extends StatelessWidget {
  const AdminsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminPage(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionHeader(
            title: 'Admins',
            subtitle:
                'Who can manage the shop. Invite an administrator with an email '
                'and a secret code just for them; every admin can change only '
                'their own code.',
          ),
          const SizedBox(height: 16),
          _AddAdminCard(),
          SizedBox(height: 16),
          _MyCodeCard(),
          SizedBox(height: 24),
          _RosterCard(),
          SizedBox(height: 14),
          Text(
            'Removing an admin is done in the Firebase console - delete their '
            'row under admins and adminCodes. Codes are stored so no client can '
            'read them, and are never shown back on this page.',
            style: MxType.bodyXs(color: MxColors.stoneLight),
          ),
        ],
      ),
    );
  }
}

/// Shared card wrapper (light surface + border), matching the rest of the
/// admin area.
class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: MxColors.creamSoft,
        borderRadius: BorderRadius.circular(MxRadius.lg),
        border: Border.all(color: MxColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: MxType.h4(color: MxColors.charcoal)),
          const SizedBox(height: 2),
          Text(subtitle, style: MxType.bodyXs(color: MxColors.stone)),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

/// Green / red one-line result under an action, or nothing while idle.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.ok});

  final String text;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Text(
        text,
        style: MxType.bodyXs(
          color: ok ? MxColors.ok : MxColors.danger,
          weight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Writes (or updates) the unreadable code row for [emailDoc]. A single helper
/// backs both "add an administrator" and "change my own code": Firestore routes
/// the same call to the create or the update rule depending on whether a row
/// exists, and the rules decide who may write what:
///
///  * first an update `{code, updatedAt}` - allowed when the row exists and the
///    writer is (B) its own admin, or (C) any admin resetting a not-yet-claimed
///    invite;
///  * when no row exists yet the update fails, so fall back to a create
///    `{code, addedBy, addedAt}` - allowed to any admin (the owner setting
///    their first code, or opening a fresh invite).
///
/// The rules reject both when the invite has already been claimed by someone
/// who is now an admin and the writer is a different person - which is exactly
/// the boundary the owner asked for: only that admin can change their own code.
Future<void> _persistAdminCode(
  String emailDoc,
  String code,
  String actorUid,
) async {
  final doc = FbAdmin.adminCodes.doc(emailDoc);
  try {
    await doc.update({
      'code': code,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    return;
  } catch (_) {
    // No row for this email yet: fall through to the create path.
  }
  await doc.set({
    'code': code,
    'addedBy': actorUid,
    'addedAt': FieldValue.serverTimestamp(),
  });
}

/// Human message for a refused code write. A `permission-denied` from the
/// rules means the write did not match any allowed case; the wording differs
/// for inviting someone else vs changing your own code.
String _codeWriteError(Object e, {required bool invitingSomeoneElse}) {
  if (e is FirebaseException && e.code == 'permission-denied') {
    return invitingSomeoneElse
        ? 'That email already has an administrator or a claimed invite. An '
            'invite code can be reset only until it is claimed - after that, '
            'only that administrator can change their own code.'
        : 'Your code could not be changed on this account. Sign in as the '
            'administrator that owns this email first.';
  }
  return FbAdmin.friendlyMessage(e);
}

class _AddAdminCard extends StatefulWidget {
  const _AddAdminCard();

  @override
  State<_AddAdminCard> createState() => _AddAdminCardState();
}

class _AddAdminCardState extends State<_AddAdminCard> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _code = TextEditingController();
  bool _busy = false;
  String? _status; // non-null = show a result line (success when _ok)
  bool _ok = false;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final email = adminEmailKey(_email.text);
    final code = _code.text.trim();
    final auth = context.read<AuthController>();
    final uid = auth.user?.uid;
    if (uid == null) return;
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _persistAdminCode(email, code, uid);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = true;
        _status = 'Admin invited for $email. Share the code with them '
            'privately - they sign in here and enter it once to unlock admin.';
        _code.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _status = _codeWriteError(e, invitingSomeoneElse: true);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _Card(
      title: 'Add an administrator',
      subtitle:
          'Enter the person’s email and a secret code for them. Codes are '
          'compared exactly - only that email can use this code.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _email,
              enabled: !_busy,
              keyboardType: TextInputType.emailAddress,
              autofillHints: const [AutofillHints.email],
              decoration: const InputDecoration(
                labelText: 'Their email',
                prefixIcon: Icon(Icons.mail_outline_rounded),
                helperText:
                    'The account they will sign in with (Google or email).',
              ),
              validator: (v) => isPlausibleAdminEmail(v ?? '')
                  ? null
                  : 'Enter a real email address',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _code,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Secret code for them',
                prefixIcon: Icon(Icons.key_rounded),
                helperText:
                    '4+ characters. You must tell them this code - it is never '
                    'shown again.',
              ),
              validator: (v) => adminCodeError(v ?? ''),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _add,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: Text(_busy ? 'Inviting…' : 'Add admin'),
              ),
            ),
            if (_status != null) _StatusLine(text: _status!, ok: _ok),
          ],
        ),
      ),
    );
  }
}

class _MyCodeCard extends StatefulWidget {
  const _MyCodeCard();

  @override
  State<_MyCodeCard> createState() => _MyCodeCardState();
}

class _MyCodeCardState extends State<_MyCodeCard> {
  final _formKey = GlobalKey<FormState>();
  final _code = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _status;
  bool _ok = false;

  @override
  void dispose() {
    _code.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final auth = context.read<AuthController>();
    final email = (auth.user?.email ?? '').trim().toLowerCase();
    final uid = auth.user?.uid;
    if (email.isEmpty || uid == null) {
      setState(() {
        _status =
            'This account has no email on it, so it cannot hold a personal code.';
        _ok = false;
      });
      return;
    }
    final code = _code.text.trim();
    setState(() {
      _busy = true;
      _status = null;
    });
    try {
      await _persistAdminCode(email, code, uid);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = true;
        _status =
            'Your admin code is updated. Use it when you sign in on a new device.';
        _code.clear();
        _confirm.clear();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _ok = false;
        _status = _codeWriteError(e, invitingSomeoneElse: false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final email =
        context.watch<AuthController>().user?.email ?? 'your account';
    return _Card(
      title: 'My admin code',
      subtitle:
          'Change only your own code ($email). Other administrators are changed '
          'only by themselves.',
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _code,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New code',
                prefixIcon: Icon(Icons.key_rounded),
              ),
              validator: (v) => adminCodeError(v ?? ''),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _confirm,
              enabled: !_busy,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Repeat new code',
                prefixIcon: Icon(Icons.check_circle_outline_rounded),
              ),
              validator: (v) {
                final a = _code.text.trim();
                final b = (v ?? '').trim();
                if (adminCodeError(b) != null) return adminCodeError(b);
                if (a != b) return 'The two codes do not match';
                return null;
              },
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.settings_backup_restore_rounded,
                        size: 18),
                label: Text(_busy ? 'Saving…' : 'Change my code'),
              ),
            ),
            if (_status != null) _StatusLine(text: _status!, ok: _ok),
          ],
        ),
      ),
    );
  }
}

/// The roster of every admin grant. Streamed live from Firestore; only admins
/// can read it (rules), and the reader here is always an admin because the
/// whole section lives inside the dashboard.
class _RosterCard extends StatelessWidget {
  const _RosterCard();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FbAdmin.admins.snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return _Card(
            title: 'Current admins',
            subtitle: 'Who holds an admin grant right now.',
            child: StateNote(
              icon: Icons.error_outline_rounded,
              text: 'Could not load the admin list.',
              detail: FbAdmin.friendlyMessage(snap.error!),
              tone: StateTone.danger,
            ),
          );
        }
        if (snap.connectionState != ConnectionState.active) {
          return _Card(
            title: 'Current admins',
            subtitle: 'Who holds an admin grant right now.',
            child: const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            ),
          );
        }
        final myUid = context.read<AuthController>().user?.uid;
        final docs = [...?snap.data?.docs]
          ..sort((a, b) {
            final aSelf = a.id == myUid ? 0 : 1;
            final bSelf = b.id == myUid ? 0 : 1;
            if (aSelf != bSelf) return aSelf - bSelf;
            final ae =
                ((a.data()['email'] as String?) ?? '').toLowerCase();
            final be =
                ((b.data()['email'] as String?) ?? '').toLowerCase();
            if (ae != be) return ae.compareTo(be);
            return a.id.compareTo(b.id);
          });
        return _Card(
          title: 'Current admins',
          subtitle:
              '${docs.length} admin${docs.length == 1 ? '' : 's'} '
              '${docs.length == 1 ? 'has' : 'have'} access right now.',
          child: docs.isEmpty
              ? const StateNote(
                  icon: Icons.people_outline_rounded,
                  text:
                      'No admin grants yet. Add the first administrator above, '
                      'or use the owner-set access code on the sign-in page.',
                )
              : Column(
                  children: [
                    for (final doc in docs) _rosterRow(context, doc, myUid),
                  ],
                ),
        );
      },
    );
  }

  Widget _rosterRow(
    BuildContext context,
    DocumentSnapshot<Map<String, dynamic>> doc,
    String? myUid,
  ) {
    final m = doc.data() ?? const <String, dynamic>{};
    final email = (m['email'] as String?)?.trim();
    final added = m['addedAt'];
    final me = doc.id == myUid;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: me ? MxColors.mossTint : Colors.transparent,
        borderRadius: BorderRadius.circular(MxRadius.md),
        border: Border.all(color: me ? MxColors.mossSoft : MxColors.line),
      ),
      child: Row(
        children: [
          Icon(
            me ? Icons.account_circle_rounded : Icons.admin_panel_settings_outlined,
            size: 22,
            color: me ? MxColors.moss : MxColors.earth,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  email ?? 'Admin account ${_shortUid(doc.id)}',
                  style: MxType.bodySm(
                    color: MxColors.charcoal,
                    weight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _addedLabel(added, hasEmail: email != null, docId: doc.id),
                  style: MxType.bodyXs(color: MxColors.stone),
                ),
              ],
            ),
          ),
          if (me)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(
                color: MxColors.moss,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'You',
                style: MxType.bodyXs(
                  color: MxColors.cream,
                  weight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _addedLabel(Object? added,
      {required bool hasEmail, required String docId}) {
    if (added is Timestamp) return 'Admin since ${shortWhen(added.toDate())}';
    if (hasEmail) return 'Admin';
    return 'No email on record (legacy grant). $docId';
  }

  String _shortUid(String uid) =>
      uid.length <= 10 ? uid : '${uid.substring(0, 8)}…';
}
