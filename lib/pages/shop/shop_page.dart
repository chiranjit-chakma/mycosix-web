import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../config/mx_colors.dart';
import '../../config/mx_type.dart';
import '../../models/product.dart';
import '../../state/admin_reveal.dart';
import '../../state/auth_controller.dart';
import '../../state/products_controller.dart';
import '../../widgets/delivery_paused_notice.dart';
import '../../widgets/page.dart';
import '../../widgets/product_card.dart';
import '../../widgets/shell.dart';

/// The shop: every product, searchable and filterable by category.
///
/// The search box is a product search first: typing filters the catalogue and
/// ordinary queries are never anything else. When a search is *submitted*
/// (the search/enter key) with a single code-like word that matches nothing
/// in the catalogue, it doubles as the owner's door to the admin area — the
/// "type your code in the shop search" summon restored from earlier rounds.
/// The typed value is never treated as a credential: the owner-set admin code
/// lives only in the security rules and no client can read it, so the app can
/// only (a) let the rules verify the word for an account already signed into
/// the admin session, or (b) show a signed-out visitor the labelled admin
/// door. The real boundary stays server-side (admin sign-in + the admins/{uid}
/// grant enforced by Firestore rules), exactly as for the "Admin" entry on the
/// account page.
class ShopPage extends StatefulWidget {
  const ShopPage({super.key, this.embedded = false});

  /// Installed-PWA paging: when true, renders only the page content (no
  /// shell, top bar or footer) so the horizontal app shell can host the
  /// section. The browser website keeps the default full-shell form.
  final bool embedded;

  @override
  State<ShopPage> createState() => _ShopPageState();
}

class _ShopPageState extends State<ShopPage> {
  String _category = 'All';
  String _query = '';
  final _search = TextEditingController();

  /// Set when a signed-out visitor submits a code-like word that matches no
  /// product: the empty state then shows the labelled owner door to the admin
  /// area. Cleared the moment the text changes again.
  bool _showOwnerDoor = false;

  static const _categories = ['All', 'Fresh', 'Dried', 'Preserved'];

  /// A submitted search looks like a possible owner code when it is one word
  /// (no spaces) of at least six characters. Everything else — multi-word
  /// queries, short words, anything the catalogue matches — is purely a
  /// product search and is never treated as a summon.
  static bool _isCodeShaped(String text) {
    final t = text.trim();
    return t.length >= 6 && !t.contains(RegExp(r'\s'));
  }

  /// Whether any product in the whole catalogue contains [token] (ignoring
  /// case), independent of the category chip. A token a product matches is a
  /// real search term, never a code attempt.
  static bool _anyProductContains(List<Product> all, String token) {
    final needle = token.trim().toLowerCase();
    for (final p in all) {
      final hay =
          '${p.name} ${p.variant} ${p.category} ${p.weight} ${p.description}'
              .toLowerCase();
      if (hay.contains(needle)) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // A cold /shop visit (deep link, or a refresh while on the shop) must load
    // the catalog itself — home usually starts it, but the shop works alone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProductsController>().fetchAll();
    });
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _showOwnerDoor = false;
    });
  }

  /// Submit (the search/enter key). Product searches behave exactly as before.
  /// A code-like word that matches nothing opens the way to the admin area:
  ///  - signed into the admin session and already an administrator: straight
  ///    to the admin area (no code re-entry — a valid session is enough);
  ///  - signed into the admin session but not yet granted: the typed word is
  ///    submitted to the rules for verification — right opens the admin area,
  ///    wrong stays an ordinary (empty) search and reveals nothing;
  ///  - not signed into the admin session: the app cannot verify the word
  ///    (the real code is unreadable by clients), so it stays on the shop and
  ///    surfaces the labelled owner door in the "no matches" state instead of
  ///    yanking a customer to a sign-in page.
  Future<void> _onSearchSubmitted(String value) async {
    final text = value.trim();
    final products = context.read<ProductsController>();
    if (!_isCodeShaped(text) ||
        !products.loaded ||
        _anyProductContains(products.products, text)) {
      if (mounted && _showOwnerDoor) {
        setState(() => _showOwnerDoor = false);
      }
      return;
    }

    AuthController? auth;
    try {
      auth = context.read<AuthController>();
    } on ProviderNotFoundException {
      auth = null;
    }

    final signedInAdminSession = auth?.user != null;
    if (signedInAdminSession) {
      // Let the server decide: an un-granted account is admitted only if the
      // rules verify the typed word as the owner-set admin code.
      if (auth!.isAdmin != true) {
        final result = await auth.grantAdminWithCode(text);
        if (!mounted) return;
        if (result != AdminCodeGrant.granted) return; // wrong word: silent
      }
      _search.clear();
      if (mounted) setState(() => _query = '');
      AdminReveal.shared.openAdmin();
      return;
    }

    // Signed-out visitor: no client-side copy of the code exists to compare
    // with, so the word alone is not enough to open the door silently. Point
    // the owner at the labelled admin door in the empty state below.
    if (mounted) setState(() => _showOwnerDoor = true);
  }

  List<Product> _visible(List<Product> all) {
    final q = _query.trim().toLowerCase();
    final out = <Product>[];
    for (final p in all) {
      if (_category != 'All' && p.category != _category) continue;
      if (q.isNotEmpty) {
        final hay =
            '${p.name} ${p.variant} ${p.category} ${p.weight} '
                    '${p.description}'
                .toLowerCase();
        if (!hay.contains(q)) continue;
      }
      out.add(p);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final products = context.watch<ProductsController>();
    final all = products.products;
    final filtered = _visible(all);

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 120),
        MxPage(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('THE SHOP'.toUpperCase(), style: MxType.overline()),
              const SizedBox(height: 12),
              Text('Fresh from the grow room', style: MxType.h1(width)),
              const SizedBox(height: 14),
              Text(
                'Every pack is harvested to order. When it is gone, it is gone — '
                'the next harvest is on its way.',
                style: MxType.body(width),
              ),
              const SizedBox(height: 22),
              // The banner appears only when an admin has paused delivery.
              const DeliveryPausedNotice(),
              const SizedBox(height: 22),
              // Search across the whole catalogue.
              SizedBox(
                width: double.infinity,
                child: TextField(
                  controller: _search,
                  onChanged: _onSearchChanged,
                  onSubmitted: _onSearchSubmitted,
                  textInputAction: TextInputAction.search,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    hintText: 'Search the harvest, e.g. dried, powder, 250 g…',
                    hintStyle: MxType.bodySm(color: MxColors.stone),
                    prefixIcon: const Icon(
                      Icons.search_rounded,
                      color: MxColors.moss,
                    ),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(
                              Icons.close_rounded,
                              color: MxColors.stone,
                            ),
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                          ),
                    filled: true,
                    fillColor: MxColors.creamSoft,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 15,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MxRadius.md),
                      borderSide: const BorderSide(color: MxColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(MxRadius.md),
                      borderSide: const BorderSide(
                        color: MxColors.moss,
                        width: 1.4,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Category filter chips
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final c in _categories)
                    _FilterChip(
                      label: c,
                      selected: _category == c,
                      onTap: () => setState(() => _category = c),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        if (!products.loaded)
          MxPage(
            child: SizedBox(
              height: 260,
              child: Center(
                child: CircularProgressIndicator(
                  color: MxColors.moss,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          )
        else if (filtered.isEmpty)
          MxPage(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(
                children: [
                  const Icon(
                    Icons.inbox_outlined,
                    size: 40,
                    color: MxColors.stoneLight,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _query.trim().isEmpty
                        ? 'No products in this category yet.'
                        : 'No matches for “${_query.trim()}”.',
                    style: MxType.bodySm(),
                  ),
                  const SizedBox(height: 4),
                  if (_query.trim().isNotEmpty)
                    Text(
                      'Try a different word, or browse a category.',
                      style: MxType.bodyXs(color: MxColors.stone),
                    ),
                  // A signed-out visitor who submitted a code-like word (see
                  // [_onSearchSubmitted]) sees the labelled door to the admin
                  // area here — the app cannot compare the word itself, so it
                  // points the owner at the real (server-gated) entry rather
                  // than silently doing nothing.
                  if (_showOwnerDoor) ...[
                    const SizedBox(height: 18),
                    OutlinedButton.icon(
                      onPressed: () => AdminReveal.shared.openAdmin(),
                      icon: const Icon(
                        Icons.admin_panel_settings_outlined,
                        size: 17,
                        color: MxColors.moss,
                      ),
                      label: const Text('Shop owner? Sign in to Admin'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: MxColors.forest,
                        side: const BorderSide(color: MxColors.line),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          )
        else
          MxPage(child: ProductGrid(products: filtered, spacing: 22)),
        const SizedBox(height: 60),
      ],
    );
    if (widget.embedded) return body;
    return MxShell(child: body);
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
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
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? MxColors.forest : MxColors.creamSoft,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: selected ? MxColors.forest : MxColors.line),
        ),
        child: Text(
          label,
          style: MxType.label(
            color: selected ? Colors.white : MxColors.charcoalSoft,
            weight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
