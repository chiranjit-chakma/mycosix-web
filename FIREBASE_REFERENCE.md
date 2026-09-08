# MYCOSIX - Firebase Data Reference

> **What this file is:** everything stored in the MYCOSIX Firebase project (the data
> layer that powers the live site https://mycosix.web.app), captured from the live
> project on **2026-09-07**, re-captured on **2026-09-08** (this is the current snapshot). If Firebase is ever deleted, this file (plus the tools
> already in this repo) is the recipe to recreate it - by hand, or by pasting this
> file into an AI and asking it to recreate the documents.
>
> **What this file is NOT:** it does not change anything. It is a pure reference
> document. It adds no app code, makes no live writes, and contains no secret keys.

---

## Read this first - the 3 golden rules

1. **GitHub holds the app code; Firebase (Google cloud) holds the live data.**
   The app source, every asset, the security rules and the re-seeding tools are in
   this repo. The *data* (current products, settings, admin grant, orders) lives in
   the Firebase project `mycosix` on Google's servers. Keep that project and the
   Google sign-in (`chiranjitc.official@gmail.com`) safe - they are the other half
   of your backup.
2. **`mycosix-firebase-adminsdk.json` (the master key) is NOT in GitHub - on purpose.**
   It is the password to the whole project; anyone who finds it on GitHub could take
   over the site. A copy sits in the project folder on the owner's computer, and a
   fresh one can always be downloaded from Firebase console > Project settings >
   Service accounts > "Generate new private key". Keep one private copy somewhere
   safe that is not GitHub.
3. **The 6 real products already have an automatic re-creator in this repo:**
   `functions/scripts/seed_catalog.js` (see its header comment for usage). Running it
   rebuilds those six catalogue records exactly, and is safe to re-run (it keeps live
   stock unless you pass `--reset-stock`).

---

## Firebase project facts

| Thing | Value |
| --- | --- |
| Project id | `mycosix` |
| Live site | https://mycosix.web.app (Firebase Hosting) |
| Web app config (apiKey, authDomain, ...) | Already in the repo: `lib/firebase/firebase_options.dart` - a rebuild reads it from there |
| Sign-in method enabled | Email/Password + Google + **Phone (SMS one-time codes)** - verified 2026-09-08/09 via the Identity Toolkit management API. Phone was switched on on 2026-09-08 for the checkout WhatsApp-number verification (no code, no SMS template change needed - Firebase sends `%LOGIN_CODE% is your verification code for %APP_NAME%.`); email + Google were already on and are untouched |
| Authorized domains | `localhost`, `mycosix.firebaseapp.com`, `mycosix.web.app` (verified live 2026-09-08) |
| Admin sign-in email | `chiranjitc.official@gmail.com` |
| Admin password | **Not stored anywhere in this repo.** If forgotten: Firebase console > Authentication > user > reset password |
| Admin service-account key file | `mycosix-firebase-adminsdk.json` (in the project folder; NOT in GitHub - see rule 2) |
| Firebase Storage | NOT set up (re-verified 2026-09-08). Product photos are stored as *text inside the product document*, not in Storage (see products below) |

---

## Who can read / write each collection (from `firestore.rules`)

The rules file itself is in the repo (`firestore.rules`) - after a rebuild, redeploy it
with: `firebase deploy --only firestore:rules --project mycosix`

| Collection | Public customers | Admin |
| --- | --- | --- |
| `products` | read | read + create/update/delete |
| `siteConfig` (single doc `public`) | read | read + write |
| `orders` | owner may read orders linked to their own account (`customerId` == their uid); create ONLY the "captured order" allowlist (checkout fallback); never delete. Since 2026-09-08 a captured order's `phone` must be the **canonical `+91XXXXXXXXXX`** number and proven server-side (`phoneVerified: true` in the order, then the rules' `phoneProofHolds`): either on the caller's own Firebase auth token (`phone_number` claim - Firebase only adds that claim after it verified the one-time code itself), or an admin attestation on the caller's own `customers/{uid}` document (`phone` == the order's phone and `phoneVerified: true` - those fields are admin-only). The browser can never write an unverified number or forge the marker | read; update status-only |
| `admins` | read own grant only | (grants made via console/admin SDK - rules forbid app writes) |
| `customers` (per customer `{uid}`) | owner may read their own doc; owner creates it on first sign-in (email pinned, status `active`); owner may only update `displayName` | read all (admin Customers section); may update `status` (`active`/`disabled`) and, since 2026-09-08, the WhatsApp attestation fields (`phone`, `phoneVerified`, `phoneVerifiedBy`, `phoneVerifiedAt` - the Customers screen verifies/unverifies a number live through these); never delete |
| `carts` (per customer `{uid}`) | owner-only read/write of their own cart mirror; delete own | no access (not business data) |
| `wishlists` (per customer `{uid}`) | owner-only read/write of their own saved-product list (bounded, 120 ids max); delete own | no access (not business data) |
| `team`, `content` | no | admin only (currently unused - future editorial) |
| `batches`, `inventoryMovements`, `orderRequests` | no | admin only (currently unused - future admin records) |

---

## Collections with live data today (captured 2026-09-08)

At re-capture (2026-09-08) six collections hold live data: `products` (8 documents), `siteConfig` (1), `orders` (11), `admins` (2 - the second admin `mycosixmushroom@gmail.com` was granted on 2026-09-08), and - new since the first capture - the customer-account collections `customers`, `carts` and `wishlists` (3 documents each; rows are private customer data and are deliberately NOT reproduced in this file). The account collections are still auto-created on first use: `customers/{uid}` the first time someone registers, `carts/{uid}` the first time that customer changes their cart while signed in, and `wishlists/{uid}` the first time they save a product. `team`, `content`, `batches`, `inventoryMovements`, `orderRequests` remain defined in the rules for future features and hold **no documents** today. What changed since 2026-09-07: the admin restocked `oyster-pickle-250` (0 -> 6), one `New Trending Mushroom` sold (5 -> 4), the `chandan mushroom` admin test entry was deleted from the Products screen, and 6 new orders arrived (5 -> 11 total; 4 of 11 are linked to signed-in customer accounts). Rules/app update 2026-09-08 (evening): no data changed; the rules gained the admin WhatsApp-number attestation described above, and the app now keeps the admin area on its own separate login (`mycosix-admin`) so an admin session never touches the customer session in the same browser.

### 1) `products` - 8 documents

**Field meaning (the app reads these):**
- `id` - stable product id, also the document id.
- `image` - the cover photo. Two possible kinds:
  - an **app asset path** such as `assets/products/oyster.webp` - the actual photo file
    is bundled in the app and is IN this GitHub repo, or
  - a long **inline photo text** starting `data:image/png;base64,...` - a photo added
    through the admin area is stored as this text INSIDE the document. Such a photo
    exists ONLY in Firebase; GitHub cannot restore it. (No live product uses this
    today - see note below.)
- `gallery` - list of extra photos (same two kinds as `image`).
- `name`, `variant`, `category`, `weight`, `description`, `price` (INR), `stock`
  (units left), `available` (true/false - false = hidden from the shop), `sortKey`
  (ordering in the shop, lowest first), `videoUrl` (optional YouTube link), `createdAt`,
  `updatedAt`.

**Live product list (values as read from Firebase on 2026-09-08):**

| id | name | category | weight | price (INR) | stock | available | sortKey |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `fresh-oyster-250` | Fresh Oyster Mushrooms | Fresh | 250 g | 80 | 41 | true | 0 |
| `fresh-oyster-500` | Fresh Oyster Mushrooms - Family Pack | Fresh | 500 g | 150 | 30 | true | 1 |
| `fresh-oyster-1kg` | Fresh Oyster Mushrooms - Party Pack | Fresh | 1 kg | 280 | 25 | true | 2 |
| `oyster-slices-50` | Dried Oyster Mushroom Slices | Dried | 50 g | 120 | 18 | true | 3 |
| `oyster-powder-100` | Oyster Mushroom Powder | Dried | 100 g | 180 | 12 | true | 4 |
| `oyster-pickle-250` | Oyster Mushroom Pickle | Preserved | 250 g | 160 | 6 | true | 5 |
| `mzQNBGFab6dxcJCtRFmh` | New Trending Mushroom | Mushrooms | 56 | 300 | 4 | true | 6 |
| `u1E60lkd0AE1IxcDTMTr` | Video link test1 | Mushrooms | 20 | 200 | 3 | true | 7 |

Notes:
- The **6 real products** (first six rows) - including their full names, descriptions,
  photos (asset paths), price/stock defaults - are exactly reproducible by running
  `node scripts/seed_catalog.js` from the `functions/` folder (see rule 3 and that
  file's header). Their cover/gallery photo files live in `assets/` in this repo.
- The **last 2 products** are admin test entries (a third test entry, `chandan mushroom`, existed at first capture but was deleted by the admin since). Their `image` and `gallery` are
  empty (no photo), so there is no photo data to lose. `Video link test1` also holds a
  `videoUrl` (`https://youtube.com/shorts/267pDJFeark?si=zKZBs8gq0-1gFLmu`).
- `oyster-pickle-250` was `stock: 0` (sold out) at first capture but `available: true`; the admin restocked it since (`stock: 6` today).
- IMPORTANT: because the 6 real product photos are **asset paths**, and the admin test
  products have **no photos**, there is currently nothing in `products` that only
  exists in Firebase. If you later add a photo via the admin area it becomes inline
  text inside the document - at that point that specific photo would only live in
  Firebase and should be treated as non-restorable from GitHub.

### 2) `siteConfig` - 1 document: `siteConfig/public`

The single settings document the site reads for delivery/contact info. **Recreate this
exact document** - without it the site falls back to built-in defaults.

| Field | Live value (2026-09-08) |
| --- | --- |
| `whatsappNumber` | `916363816465` |
| `deliveryFee` | `39` |
| `deliveryEnabled` | `true` |
| `currency` | `INR` |
| `serviceArea` | `Mysore, Karnataka` |
| `orderLeadTime` | `Same day or next morning` |
| `instagramUrl` | `https://instagram.com/mycosix_mushroom` |
| `updatedAt` | server timestamp |

### 3) `orders` - 11 documents (NOT reproduced in this file)

**An order holds the customer's private details (name, phone, delivery location), so
real order rows are deliberately not copied here or into GitHub.** If Firebase is
deleted, past order history cannot be rebuilt - that is the one data type you must
protect by keeping the Firebase project alive.

Schema change on 2026-09-08 (checkout WhatsApp verification): every NEW order's
`phone` is stored canonical (`+91XXXXXXXXXX`) and gains `phoneVerified: true` - the
security rules only accept that when the number is the `phone_number` claim on the
caller's own Firebase auth token, i.e. the customer proved the number with a one-time
SMS code. Older orders keep whatever format they were saved in and are unaffected;
admins never see OTPs or tokens (none exist - codes go straight from the customer's
browser to Firebase).

**Schema** (for reference when re-creating the rules or pasting into an AI):

| Field | Meaning |
| --- | --- |
| `orderId` | Customer-facing id, format `MYC-XXXXXXXX` (8 chars from A-HJ-NP-Z2-9) |
| `customerName`, `phone` | required; `email` optional |
| `latitude`, `longitude`, `mapsUrl` | chosen delivery pin |
| `building`, `apartment`, `landmark`, `instructions` | optional address detail |
| `items` | list of lines: `productId`, `productName`, `variant?`, `weight?`, `quantity` (+ `unitPrice`, `lineTotal` when verified) |
| `subtotal`, `deliveryFee`, `total`, `currency` | the amounts shown and agreed at checkout |
| `verified` | `true` = economics from the trusted backend; `false` = browser-captured reference order (checkout fallback) |
| `customerId` | (accounts, 2026-09-07) the signed-in customer's Firebase Auth uid, when they placed the order. Stamped by the trusted backend from the auth token (function) and by checkout on a captured order; security rules pin it to `request.auth.uid`, so a browser can never write someone else's id. Absent for guest orders. Lets the customer's "My Orders" view query only their own orders |
| `status` | one of the canonical labels below |
| `createdAt`, `updatedAt`, `deliveredAt?` | timestamps; `deliveredAt` stamped only when marked Delivered |

**Order status flow** (exact strings; enforced in rules and `lib/models/order_status.dart`):
`New` -> `Contacted` -> `Confirmed` -> `Preparing` -> `Out for Delivery` -> `Delivered`
(terminal). `Cancelled` (terminal) at any earlier step.

### 4) `admins` - 2 documents

The admin grant. A signed-in user is an admin only if a document exists at
`admins/<their Firebase Auth uid>`. Rules forbid the app from creating it - it is made
by the project owner (console or an admin-SDK script).

| Document id (= Auth uid) | Fields |
| --- | --- |
| `JhLVvcXJLZepu8ABW1gC5ZqMKjA2` | `email`: `chiranjitc.official@gmail.com`; `grantedAt`: timestamp 2026-09-05; `note`: "granted by project owner (free-plan provisioning)" |
| `qRPwFKd78cd7FPRB1LdJdw6CIi52` | `email`: `mycosixmushroom@gmail.com`; `grantedAt`: timestamp 2026-09-08; `note`: "granted by project owner (free-plan provisioning)" |

To re-grant after a rebuild: in Firebase console > Authentication, make sure the user
exists (Email/Password or Google - the uid stays the same across providers on one
email once linked), copy its **uid**, then create a document `admins/<uid>` with
`{ "email": "<that email>" }`. The second admin (`mycosixmushroom@gmail.com`) was
provisioned on 2026-09-08 the same way from the Auth record (no password needed from
the owner - the account already existed).

---

## What is already in GitHub that does the rebuilding for you

| File in this repo | What it is for |
| --- | --- |
| `firestore.rules` | Security rules for every collection (the schema tables above come from here). Since 2026-09-08 the orders `create` gate proves the canonical phone server-side (`phoneProofHolds`): the caller's auth-token `phone_number` claim, or an admin attestation on the caller's own `customers/{uid}` profile |
| `firestore.indexes.json` | Firestore composite indexes (products category+sortKey; orders customerId+createdAt) |
| `storage.rules` | Storage rules (deny-all; Storage not enabled today) |
| `firebase.json` | Hosting config |
| `functions/scripts/seed_catalog.js` | Re-creates the 6 real products (safe re-run) |
| `functions/index.js` + `functions/test/` | Trusted order backend + tests (optional; not deployed on the free plan). Mirrors the attestation phone proof inside its transaction (24 tests pass) |
| `lib/firebase/firebase_options.dart` | The web app's Firebase project config |
| `assets/` | Every product/brand photo that products reference as asset paths |

---

## Scenario: rebuild from nothing - exact steps

### (A) Same Firebase project, but you lost the data (or a new computer)

1. Get the master key: Firebase console > Project settings > Service accounts >
   "Generate new private key" -> save as `mycosix-firebase-adminsdk.json`.
2. From this repo folder, on a machine with Flutter + Node installed:
   - `flutter pub get`
   - `flutter build web --release`
   - `firebase login` (sign in as `chiranjitc.official@gmail.com`)
   - `firebase deploy --only hosting,firestore:rules --project mycosix`
3. Re-create the settings + admin grant (console or a script using the admin key):
   - document `siteConfig/public` with the values in the table above,
   - make sure Authentication > Email/Password is enabled and the admin user exists,
   - create `admins/<admin-auth-uid>` with the email field.
4. Re-create the catalogue:
   - `cd functions` then `$env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\mycosix-firebase-adminsdk.json"`
     then `node scripts/seed_catalog.js` (the 6 real products).
   - Re-type the 3 admin test products from the table if you want them back.
5. You are back up. (New customer orders start fresh.)

### (B) Even the Firebase project itself was deleted

Everything in (A), except step 2's project no longer exists, so first create a new one:
1. Firebase console > Add project (e.g. `mycosix-2`), enable Hosting, Firestore,
   and Email/Password authentication.
2. Regenerate the web config: Firebase console > Project settings > Your apps >
   add a web app, and replace the values in `lib/firebase/firebase_options.dart`
   (the file format is the same). This is the one app file GitHub cannot hand you -
   it must come from the new project.
3. Generate a new master key (step 1 of A).
4. Deploy with `--project <new-project-id>`, then do A-3, A-4.
5. Change `firebase.json`/hosting if you want a different site name.

---

## What this file will NOT bring back (honest list)

1. **A deleted Firebase project's id and web config.** If you delete the project you
   must create a new one and regenerate `firebase_options.dart` (scenario B).
2. **The admin account password.** Reset it in Firebase console if forgotten.
3. **Past orders** (customer private data) and any sales analytics built from them.
4. **Photos added via the admin area** after this date, because those are stored as
   inline text inside the product document (only in Firebase). Currently none exist -
   the 6 real catalogue photos are asset files already in GitHub.
5. Anything added to Firebase after this file's capture date. Re-capture by reading
   the live project if you need a newer snapshot.
