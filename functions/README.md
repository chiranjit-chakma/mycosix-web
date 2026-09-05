# MYCOSIX trusted backend (Cloud Functions)

The website never writes to `orders` directly. Orders are placed through the
`createOrder` HTTPS callable in `index.js`, which validates the draft, reads the
real product catalogue + site config from Firestore, computes authoritative
prices, and writes the order (and stock decrements) in one transaction.

## Layout

- `index.js` — the `createOrder` callable + pure, testable order core.
- `test/create_order.test.js` — 15 behavioural tests against an in-memory fake
  Firestore (no emulator, no network): `npm test` (`node --test test/`).
- `scripts/seed_catalog.js` — admin-only catalogue seeder (see below).

## The core is pure

`index.js` exports `placeOrder(db, data)`, which talks only to a minimal
Firestore interface (`collection().doc()`, `runTransaction`). The Firebase
Functions wiring is a thin wrapper around it, so the whole order path is tested
offline.

## Deploying (project owner)

```powershell
# 1. Authenticate (one-time per machine / after token expiry)
firebase login
firebase projects:list          # confirm the project is "mycosix"

# 2. From this repo root, publish security rules + indexes
firebase deploy --only firestore:rules,firestore:indexes,storage

# 3. Enable the function (requires the Blaze plan) and deploy
firebase deploy --only functions
```

`createOrder` runs on Node 20 (see `package.json` engines).

## Seeding the real catalogue

Products are seeded server-side only, mirroring
`lib/repositories/product_repository.dart` exactly (same ids, names, prices,
images, `sortKey`). Safe by default: existing documents are left untouched, so
live inventory is never clobbered.

```powershell
# Download a service-account key first:
#   Firebase console > Project settings > Service accounts > Generate new private key
$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\to\mycosix-firebase-adminsdk.json"
cd functions

node scripts/seed_catalog.js                # create the six products (missing only)
node scripts/seed_catalog.js --force        # refresh catalogue fields, keep live stock
node scripts/seed_catalog.js --reset-stock  # also restore catalogue stock levels
node scripts/seed_catalog.js --dry-run      # list what would happen, touch nothing
```

## Granting an admin

Add a document to the `admins` collection whose **document id is the admin's
Firebase Auth uid** (any fields are fine — only the doc id matters, e.g.
`{ "email": "you@example.com" }`). The Firestore rules check exactly this:

```
Firestore Database > admins > Add document
  document id = <the auth uid>     # Authentication > Users > uid
```

There is no "sign-up as admin" path in the app; grants are provisioned here by
the project owner only.
