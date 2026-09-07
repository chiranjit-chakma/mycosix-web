# MYCOSIX - Firebase Data Reference

> **What this file is:** everything stored in the MYCOSIX Firebase project (the data
> layer that powers the live site https://mycosix.web.app), captured from the live
> project on **2026-09-07**. If Firebase is ever deleted, this file (plus the tools
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
| Sign-in method enabled | Email/Password (the only one) |
| Admin sign-in email | `chiranjitc.official@gmail.com` |
| Admin password | **Not stored anywhere in this repo.** If forgotten: Firebase console > Authentication > user > reset password |
| Admin service-account key file | `mycosix-firebase-adminsdk.json` (in the project folder; NOT in GitHub - see rule 2) |
| Firebase Storage | NOT set up. Product photos are stored as *text inside the product document*, not in Storage (see products below) |

---

## Who can read / write each collection (from `firestore.rules`)

The rules file itself is in the repo (`firestore.rules`) - after a rebuild, redeploy it
with: `firebase deploy --only firestore:rules --project mycosix`

| Collection | Public customers | Admin |
| --- | --- | --- |
| `products` | read | read + create/update/delete |
| `siteConfig` (single doc `public`) | read | read + write |
| `orders` | no read; create ONLY the "captured order" allowlist (checkout fallback); never delete | read; update status-only |
| `admins` | read own grant only | (grants made via console/admin SDK - rules forbid app writes) |
| `team`, `content` | no | admin only (currently unused - future editorial) |
| `batches`, `inventoryMovements`, `orderRequests` | no | admin only (currently unused - future admin records) |

---

## Collections with live data today (captured 2026-09-07)

Only **4 collections** exist: `products`, `siteConfig`, `orders`, `admins`.
`team`, `content`, `batches`, `inventoryMovements`, `orderRequests` are defined in the
rules for future features but hold **no documents** today.

### 1) `products` - 9 documents

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

**Live product list (values as read from Firebase on 2026-09-07):**

| id | name | category | weight | price (INR) | stock | available | sortKey |
| --- | --- | --- | --- | --- | --- | --- | --- |
| `fresh-oyster-250` | Fresh Oyster Mushrooms | Fresh | 250 g | 80 | 41 | true | 0 |
| `fresh-oyster-500` | Fresh Oyster Mushrooms - Family Pack | Fresh | 500 g | 150 | 30 | true | 1 |
| `fresh-oyster-1kg` | Fresh Oyster Mushrooms - Party Pack | Fresh | 1 kg | 280 | 25 | true | 2 |
| `oyster-slices-50` | Dried Oyster Mushroom Slices | Dried | 50 g | 120 | 18 | true | 3 |
| `oyster-powder-100` | Oyster Mushroom Powder | Dried | 100 g | 180 | 12 | true | 4 |
| `oyster-pickle-250` | Oyster Mushroom Pickle | Preserved | 250 g | 160 | 0 | true | 5 |
| `mzQNBGFab6dxcJCtRFmh` | New Trending Mushroom | Mushrooms | 56 | 300 | 5 | true | 6 |
| `nOtFI79mEzsMSH2MNPKy` | chandan mushroom | Mushrooms | 30 | 400 | 100 | true | 67 |
| `u1E60lkd0AE1IxcDTMTr` | Video link test1 | Mushrooms | 20 | 200 | 3 | true | 7 |

Notes:
- The **6 real products** (first six rows) - including their full names, descriptions,
  photos (asset paths), price/stock defaults - are exactly reproducible by running
  `node scripts/seed_catalog.js` from the `functions/` folder (see rule 3 and that
  file's header). Their cover/gallery photo files live in `assets/` in this repo.
- The **last 3 products** are admin test entries. Their `image` and `gallery` are
  empty (no photo), so there is no photo data to lose. `Video link test1` also holds a
  `videoUrl` (`https://youtube.com/shorts/267pDJFeark?si=zKZBs8gq0-1gFLmu`).
- `oyster-pickle-250` has `stock: 0` (sold out) but `available: true`.
- IMPORTANT: because the 6 real product photos are **asset paths**, and the admin test
  products have **no photos**, there is currently nothing in `products` that only
  exists in Firebase. If you later add a photo via the admin area it becomes inline
  text inside the document - at that point that specific photo would only live in
  Firebase and should be treated as non-restorable from GitHub.

### 2) `siteConfig` - 1 document: `siteConfig/public`

The single settings document the site reads for delivery/contact info. **Recreate this
exact document** - without it the site falls back to built-in defaults.

| Field | Live value (2026-09-07) |
| --- | --- |
| `whatsappNumber` | `916363816465` |
| `deliveryFee` | `39` |
| `deliveryEnabled` | `true` |
| `currency` | `INR` |
| `serviceArea` | `Mysore, Karnataka` |
| `orderLeadTime` | `Same day or next morning` |
| `instagramUrl` | `https://instagram.com/mycosix_mushroom` |
| `updatedAt` | server timestamp |

### 3) `orders` - 5 documents (NOT reproduced in this file)

**An order holds the customer's private details (name, phone, delivery location), so
real order rows are deliberately not copied here or into GitHub.** If Firebase is
deleted, past order history cannot be rebuilt - that is the one data type you must
protect by keeping the Firebase project alive.

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
| `status` | one of the canonical labels below |
| `createdAt`, `updatedAt`, `deliveredAt?` | timestamps; `deliveredAt` stamped only when marked Delivered |

**Order status flow** (exact strings; enforced in rules and `lib/models/order_status.dart`):
`New` -> `Contacted` -> `Confirmed` -> `Preparing` -> `Out for Delivery` -> `Delivered`
(terminal). `Cancelled` (terminal) at any earlier step.

### 4) `admins` - 1 document

The admin grant. A signed-in user is an admin only if a document exists at
`admins/<their Firebase Auth uid>`. Rules forbid the app from creating it - it is made
by the project owner.

| Document id (= Auth uid) | Fields |
| --- | --- |
| `JhLVvcXJLZepu8ABW1gC5ZqMKjA2` | `email`: `chiranjitc.official@gmail.com`; `grantedAt`: timestamp 2026-09-05; `note`: "granted by project owner (free-plan provisioning)" |

To re-grant after a rebuild: in Firebase console > Authentication, make sure the user
`chiranjitc.official@gmail.com` exists (Email/Password), copy its **uid**, then create a
document `admins/<uid>` with `{ "email": "chiranjitc.official@gmail.com" }`.

---

## What is already in GitHub that does the rebuilding for you

| File in this repo | What it is for |
| --- | --- |
| `firestore.rules` | Security rules for every collection (the schema tables above come from here) |
| `firestore.indexes.json` | Firestore composite index (products category+sortKey) |
| `storage.rules` | Storage rules (deny-all; Storage not enabled today) |
| `firebase.json` | Hosting config |
| `functions/scripts/seed_catalog.js` | Re-creates the 6 real products (safe re-run) |
| `functions/index.js` + `functions/test/` | Trusted order backend + tests (optional; not deployed on the free plan) |
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
