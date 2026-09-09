# MYCOSIX Mushrooms

Premium e-commerce website for **MYCOSIX**, a student oyster-mushroom farm
(six growers) delivering fresh, farm-grown mushrooms around Mysore, Karnataka. Built
with Flutter Web.

- Live site: https://mycosix.web.app
- Primary domain (when connected): https://mycosixmushroom.com
- Working source (private, write-capable): https://github.com/chiranjit-chakma/mycosix-web
- Legacy org repo (read-only for this account): https://github.com/mycosixmushroom/MYCOSIX

## Where things live

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter app — customer storefront + hidden admin area |
| `lib/pages/` | Screens, one folder per page (`home`, `shop`, `product`, `checkout`, `cart`, `about`, `farm`, `team`, `journey`, `contact`, `admin/`…) |
| `lib/widgets/` | Reusable UI (shell, top bar, product grid/cards, page + section scaffolding, CTA, image) |
| `lib/state/` | Controllers (cart, products, location, admin reveal) |
| `lib/repositories/` | Data access (products, cart, orders) — UI depends only on these interfaces |
| `lib/services/` | WhatsApp handoff, URL launcher |
| `lib/config/` | Brand tokens (`mx_colors`), fluid type (`mx_type`), site config (`mx_config`) |
| `lib/router/` | Routes + app navigator (real-path URLs) |
| `lib/models/` | Product, cart item, order draft/order/store order, delivery location |
| `lib/firebase/` | Firebase web options |
| `assets/brand/` | Brand web assets: `mushroom-1.webp` (250 g product photo), `mycosix-logo.webp`, `mycosix-tile.webp` |
| `assets/products/` | Product photos shipped with the app (webp, decoded from `source-images/`) |
| `assets/images/` | Farm/process/journal photos used across the site |
| `assets/fonts/` | Bundled fonts (Fraunces + Manrope) — no CDN dependency |
| `source-images/` | **Original** photos/artwork the assets above are derived from (see below) |
| `functions/` | Cloud Functions source — trusted `createOrder` for orders; `scripts/seed_catalog.js` seeds the Firestore catalogue |
| `firestore.rules` / `firestore.indexes.json` / `storage.rules` | Real security rules + indexes (source of truth) |
| `firebase.json` / `.firebaserc` | Firebase project config (project: `mycosix`) |
| `tool/` | Dev helpers: CDP browser QA harnesses (`cdp_*.js`), icon/image generators (`gen_*.py`) |
| `test/` | Flutter tests (unit + responsive layout) |
| `web/` | Web bootstrap (`index.html`) |

## Source images

`source-images/` holds the original, full-resolution photos so anyone with the
repo can regenerate the shipped assets:

| Source | Used as |
| --- | --- |
| `source-images/fresh-oyster-250g.png` | `assets/brand/mushroom-1.webp` (the 250 g product hero — a background-removed cutout) |
| `source-images/fresh-oyster-family-500g.png` | `assets/products/oyster_family.webp` |
| `source-images/fresh-oyster-party-1kg.png` | `assets/products/oyster_party.webp` |
| `source-images/dried-oyster-slices.png` | `assets/products/oyster_dried.webp` |
| `source-images/oyster-powder-100g.png` | `assets/products/oyster_powder.webp` |
| `source-images/oyster-pickle-250g.png` | `assets/products/oyster_pickle.webp` |
| `source-images/mycosix-logo-emblem.jpeg` | black-background emblem source for the logo mark |

The webp files are optimised derivatives (≈1100 px longest edge). `tool/gen_icons.py`
and `tool/gen_images.py` cover the older procedural placeholder assets; the real
photography above supersedes them.

## Stack

- Flutter 3.x — Web, real-path URLs via `PathUrlStrategy`
- Provider for state, SharedPreferences for browser storage
- Firebase: Authentication (Email/Password), Firestore, Hosting; Storage rules included
- Spark (free) plan: **Cloud Functions cannot run** — automated server-side
  order capture is built and ready in `functions/` but stays deferred until the
  plan supports it (today orders hand off to WhatsApp; see *Order flow*).

## Run locally

```bash
flutter pub get
flutter run -d chrome            # dev server with hot reload
```

Release preview (matches what is deployed):

```bash
flutter build web --release       # output in build/web
# serve build/web with any static server that rewrites unknown paths to index.html
# (deep links like /shop need the rewrite; flutter run does it for you)
```

The `tool/cdp_*.js` harnesses drive a headless Chrome against a locally served
build for console-error / route QA (they need the `ws` package under
`node_modules`).

## Test and build

```bash
flutter analyze
flutter test                      # unit + responsive layout tests
flutter build web --release
```

`test/home_layout_test.dart` pumps the whole home page at 10 viewport sizes
(360 → 1600 px), fails on any RenderFlex overflow, and asserts the hero fills
the first viewport (the next section is not visible on load) at every size.

## Firebase

Project **`mycosix`**. Rules live as real files in this repo. Deploy all of:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage,hosting
```

### Seed / update the product catalogue

```bash
# needs the service-account key — see Security notes below
GOOGLE_APPLICATION_CREDENTIALS=mycosix-firebase-adminsdk.json \
  node functions/scripts/seed_catalog.js --force
```

`--force` refreshes image/gallery fields and keeps live stock; `--dry-run`
shows changes without writing; `--reset-stock` also resets stock from the file.

## Order flow

Orders are customer-initiated and hand off to WhatsApp (the site never sends
messages itself). The checkout shows a location pin + details and opens
WhatsApp with the full order for the customer to press **Send**.

After an order is placed the **cart is cleared**, so the next order starts
fresh — this is deliberate. When the trusted `createOrder` backend is reachable
(after the plan upgrade) the flow validates and records the order server-side
first; until then the WhatsApp handoff still works with an honest notice.

## Admin area

The admin area exists only for the owner. Entry is always gated server-side
(Firebase email/password sign-in + the `admins/{uid}` grant, enforced by
`firestore.rules`); nothing in the app ever grants access on its own.

- A visitor who opens `/admin` unsummoned is handed straight to the normal
  public home page.
- The owner summons the admin sign-in from the Shop page by submitting the
  owner-set access code in the product search box (it reads like a code, not a
  product name). Because the real code is compared only in the security rules
  — never in the app or the shipped bundle — the app treats any submitted
  single word with no product match as the summon and opens the admin
  sign-in. The trigger lives in `lib/pages/shop/shop_page.dart`, the shared
  summoner state in `lib/state/admin_reveal.dart`.
- Inside the admin area, the toggle beside Logout ("Show Admin in the site
  navigation") adds or removes an "Admin" entry in the main navigation beside
  Home / Shop / Journey etc. When it is on, tapping it reaches this same
  sign-in/dashboard; when it is off the only public way in is the shop
  search-bar summon (or a direct `/admin` visit by an already signed-in
  administrator).

The owner-set code lives only in the `secrets/adminGate` document that the
rules engine compares against — no client, administrator or not, can read it,
so it never appears in the source or the shipped bundle. It is obscurity in
front of the real boundary: Firebase Auth + the `admins/{uid}` grant + the
`firestore.rules` write guards.

## Security notes

- `mycosix-firebase-adminsdk.json` at the repo root is a **secret** service
  account key. It is ignored via `.gitignore` and must never be committed,
  shared, or pasted into the client bundle.
- Orders are only ever created server-side (trusted `createOrder` Cloud
  Function); by rule the client cannot write to the orders collection.

## Known limits / next steps

- Cloud Functions (`functions/`) are authored but not deployable on the Spark
  plan; wire them when the plan supports it and flip order capture to them.
- To push, use the write-capable private repo `chiranjit-chakma/mycosix-web`
  (`git push` from `main`). The org repo `mycosixmushroom/MYCOSIX` is
  read-only for this account.
