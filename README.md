# MYCOSIX MUSHROOMS

Premium e-commerce site for **MYCOSIX**, a student oyster-mushroom farm
(six growers) delivering fresh, farm-grown mushrooms. Built with Flutter Web.

- Live site: https://mycosix.web.app
- Primary domain (when connected): https://mycosixmushroom.com
- Source: https://github.com/mycosixmushroom/MYCOSIX

## What is here

| Path | Purpose |
| --- | --- |
| `lib/` | Flutter app (customer storefront + admin area) |
| `lib/pages/admin/` | Hidden admin area (covert summon + gate/sign-in) and dashboard |
| `firebase.json` / `.firebaserc` | Firebase project config (project: `mycosix`) |
| `firestore.rules` / `firestore.indexes.json` / `storage.rules` | Real security rules + indexes (source of truth) |
| `functions/` | Cloud Functions source (orders via trusted `createOrder`) |
| `functions/scripts/seed_catalog.js` | Seeds/updates the Firestore product catalogue |
| `web/index.html` | Web bootstrap (fonts are bundled, no CDN) |
| `assets/` | Fonts, brand, photos, product images |
| `tool/` | Local SPA server + QA helpers |
| `test/` | Flutter tests (unit + layout) - 40 tests |

## Stack

- Flutter 3.x (Web, real-path URLs via PathUrlStrategy)
- Provider for state, SharedPreferences for browser storage
- Firebase: Authentication (Email/Password), Firestore, Hosting, Storage
- Spark (free) plan: **Cloud Functions cannot run** - order capture is built
  and ready in `functions/` but stays deferred until the plan supports it.

## Run locally

```bash
flutter pub get
flutter run -d chrome          # dev server
# or serve the built site with SPA fallback:
python tool/spa_server.py      # adjust port as needed, see tool/
```

Deep links like `/shop` need a host that falls back to `index.html`; the SPA
server in `tool/` does that for local preview.

## Test and build

```bash
flutter analyze
flutter test                    # 40 tests (units + responsive layout)
flutter build web --release     # output in build/web
```

The layout suite (`test/home_layout_test.dart`) pumps the home page at 10
viewport sizes (360 to 1600 px) and fails on any RenderFlex overflow.

## Firebase

Project **`mycosix`**. Service rules live as real files in this repo:
`firestore.rules`, `firestore.indexes.json`, `storage.rules`, `firebase.json`.

`firebase deploy` targets rules + indexes + hosting:

```bash
firebase deploy --only firestore:rules,firestore:indexes,storage,hosting
```

### Seed the product catalogue

```bash
node functions/scripts/seed_catalog.js        # creates/updates docs
node functions/scripts/seed_catalog.js --force   # overwrite image/gallery fields
```

## Admin area

The admin sign-in has no discoverable URL and is not linked anywhere on the
customer site. It exists only for the owner:

- A visitor who opens `/admin` is handed straight to the normal public home
  page — the admin area never renders for anyone who is not an owner.
- The owner summons it from the site itself using a private gesture / phrase
  (deliberately **not documented here**; the site owner knows it). Those
  triggers live in `lib/widgets/brand.dart` (wordmark long-press) and
  `lib/state/admin_reveal.dart` (typed-phrase listener, ignored while a text
  field is focused).
- Once summoned, access still passes through Firebase email/password sign-in
  and the `admins/{uid}` grant.

The owner phrase is stored in `lib/pages/admin/admin_access_lock.dart` as a
list of Unicode code points (never as a readable literal), so it cannot be
found by searching the source or the shipped bundle. To change it, replace
`AdminAccessLock.secretCodePoints` with the code points of a new phrase of the
same length, rebuild, and redeploy. Anyone with the compiled bundle can
eventually reconstruct it, so the phrase and the gesture are only obscurity in
front of the real boundary: Firebase Auth + the `admins/{uid}` grant + the
`firestore.rules` write guards.

## Security notes

- `mycosix-firebase-adminsdk.json` at the repo root is a **secret** service
  account key. It is ignored via `.gitignore` and must never be committed or
  pasted into the client bundle.
- Orders are only ever created server-side (trusted `createOrder` Cloud
  Function); the client cannot write to the orders collection by rule.

## Known limits / next steps

- Cloud Functions (`functions/`) are authored but not deployable on the Spark
  plan; wire them when the plan supports it and flip order capture to them.
- GitHub push requires a write-capable account on
  `github.com/mycosixmushroom/MYCOSIX` (the `chiranjit-chakma` token used for
  the Part 2 review is read-only).
