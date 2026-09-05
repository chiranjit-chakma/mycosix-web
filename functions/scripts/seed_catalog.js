/**
 * Admin-only catalogue seeder for MYCOSIX.
 *
 * Seeds the six real MYCOSIX products into Firestore (`products`), mirroring
 * the bundled catalogue in `lib/repositories/product_repository.dart` so the
 * shop, the trusted `createOrder` function and the admin area all read the
 * same records. Product ids are stable (the same ids the Dart catalogue uses),
 * and every document carries `sortKey` for shop ordering.
 *
 * This is a backend tool run by the project owner. It uses a service-account
 * credential (admin SDK) and therefore bypasses security rules - it must never
 * be bundled into the web app.
 *
 * Usage (from the functions/ directory):
 *   # 1. Download a service-account key:
 *   #    Firebase console > Project settings > Service accounts >
 *   #    "Generate new private key"  (JSON).
 *   #
 *   # 2. Point Google's libraries at it, then run:
 *   $env:GOOGLE_APPLICATION_CREDENTIALS = "C:\path\mycosix-firebase-adminsdk.json"
 *   node scripts/seed_catalog.js                # add only missing products
 *   node scripts/seed_catalog.js --force        # refresh name/price/desc, keep live stock
 *   node scripts/seed_catalog.js --reset-stock  # also restore catalogue stock levels
 *
 * Safe by default: existing documents are left untouched, so admin inventory
 * adjustments are never clobbered by a re-run.
 */

'use strict';

const admin = require('firebase-admin');

const PRODUCTS = [
  {
    id: 'fresh-oyster-250',
    name: 'Fresh Oyster Mushrooms',
    description:
      'Plump, velvety oyster mushrooms harvested at peak freshness. Grown on pasteurised straw and sawdust in a climate-controlled room, they are clean, mild-flavoured mushrooms that cook in minutes.',
    category: 'Fresh',
    image: 'assets/brand/mushroom-1.webp',
    gallery: [
      'assets/brand/mushroom-1.webp',
      'assets/products/oyster_bouquet.jpg',
      'assets/products/oyster_fry.jpg',
    ],
    variant: 'Fresh',
    weight: '250 g',
    price: 80,
    stock: 40,
    available: true,
    sortKey: 0,
  },
  {
    id: 'fresh-oyster-500',
    name: 'Fresh Oyster Mushrooms \u2014 Family Pack',
    description:
      'A generous half-kilo of fresh oyster mushrooms for family meals. Perfect for stir-fries, curries, soups and grilled dishes across the week.',
    category: 'Fresh',
    image: 'assets/products/oyster_family.webp',
    gallery: [
      'assets/products/oyster_family.webp',
      'assets/products/oyster_cluster.jpg',
      'assets/products/oyster_bouquet.jpg',
    ],
    variant: 'Fresh',
    weight: '500 g',
    price: 150,
    stock: 30,
    available: true,
    sortKey: 1,
  },
  {
    id: 'fresh-oyster-1kg',
    name: 'Fresh Oyster Mushrooms \u2014 Party Pack',
    description:
      'A full kilogram for gatherings, restaurants and bulk cooking. Order a day ahead and we harvest to order so it reaches you at its absolute freshest.',
    category: 'Fresh',
    image: 'assets/products/oyster_party.webp',
    gallery: [
      'assets/products/oyster_party.webp',
      'assets/products/oyster_cluster.jpg',
      'assets/products/oyster_bouquet.jpg',
    ],
    variant: 'Fresh',
    weight: '1 kg',
    price: 280,
    stock: 25,
    available: true,
    sortKey: 2,
  },
  {
    id: 'oyster-slices-50',
    name: 'Dried Oyster Mushroom Slices',
    description:
      'Sun-dried oyster slices with a deep, savoury umami. Rehydrate in warm water for 15 minutes and use anywhere you would use fresh mushrooms.',
    category: 'Dried',
    image: 'assets/products/oyster_dried.webp',
    gallery: [
      'assets/products/oyster_dried.webp',
      'assets/products/oyster_bouquet.jpg',
    ],
    variant: 'Dried',
    weight: '50 g',
    price: 120,
    stock: 18,
    available: true,
    sortKey: 3,
  },
  {
    id: 'oyster-powder-100',
    name: 'Oyster Mushroom Powder',
    description:
      'Stone-ground oyster mushroom powder \u2014 a natural umami booster for soups, gravies, marinades and seasoning blends. Nothing added, nothing taken away.',
    category: 'Dried',
    image: 'assets/products/oyster_powder.webp',
    gallery: [
      'assets/products/oyster_powder.webp',
      'assets/products/oyster_dried.webp',
    ],
    variant: 'Dried',
    weight: '100 g',
    price: 180,
    stock: 12,
    available: true,
    sortKey: 4,
  },
  {
    id: 'oyster-pickle-250',
    name: 'Oyster Mushroom Pickle',
    description:
      'Tangy, spicy mushroom pickle made in small batches with cold-pressed oil and whole spices. A fiery side for rice, roti and parathas.',
    category: 'Preserved',
    image: 'assets/products/oyster_pickle.webp',
    gallery: [
      'assets/products/oyster_pickle.webp',
      'assets/products/oyster_bouquet.jpg',
    ],
    variant: 'Preserved',
    weight: '250 g',
    price: 160,
    stock: 0,
    available: false,
    sortKey: 5,
  },
];

const FORCE = process.argv.includes('--force');
const RESET_STOCK = process.argv.includes('--reset-stock');
const DRY = process.argv.includes('--dry-run');

async function main() {
  if (DRY) {
    // Offline: just list what a real run would do, no credentials needed.
    for (const p of PRODUCTS) {
      console.log('would ' + (FORCE ? 'update ' : 'create if missing  ') + p.id + '  sortKey=' + p.sortKey);
    }
    console.log('\nDry run - nothing written. Remove --dry-run to seed for real.');
    return;
  }

  if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
    console.error(
      'No service-account credential found.\n' +
        'Set GOOGLE_APPLICATION_CREDENTIALS to the downloaded JSON key first.\n' +
        'See Firebase console > Project settings > Service accounts.',
    );
    process.exit(1);
  }

  if (!admin.apps.length) {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
    });
  }
  const db = admin.firestore();
  const col = db.collection('products');

  let created = 0;
  let updated = 0;
  let skipped = 0;

  for (const p of PRODUCTS) {
    const ref = col.doc(p.id);
    const existing = await ref.get();

    if (existing.exists && !FORCE) {
      console.log('skip  ' + p.id + ' (already seeded; use --force to refresh)');
      skipped++;
      continue;
    }

    const data = Object.assign({}, p, { updatedAt: admin.firestore.FieldValue.serverTimestamp() });
    if (!existing.exists) {
      data.createdAt = admin.firestore.FieldValue.serverTimestamp();
    }
    if (existing.exists && !RESET_STOCK) {
      // Keep the live inventory count the admins have been managing.
      delete data.stock;
    }

    if (DRY) {
      console.log('would ' + (existing.exists ? 'update' : 'create') + '  ' + p.id);
    } else {
      await ref.set(data, { merge: true });
      console.log((existing.exists ? 'update ' : 'create ') + p.id + '  sortKey=' + p.sortKey + (RESET_STOCK ? '  stock reset' : ''));
    }
    if (existing.exists) {
      updated++;
    } else {
      created++;
    }
  }

  console.log('\nDone. created=' + created + ' updated=' + updated + ' skipped=' + skipped + (DRY ? ' (dry run)' : ''));
  console.log(
    '\nNext: publish Firestore rules, then add your admin uids.\n' +
      '  Firebase console > Firestore Database > Rules  (deploy firestore.rules)\n' +
      '  Firebase console > Firestore Database > admins > Add document\n' +
      '    document id = the admin account uid (or the email, see below)\n' +
      '    field: { email: "admin@example.com" }  (any fields are fine - only the doc id matters)\n' +
      '  To find a uid: Firebase console > Authentication > Users > the account uid.',
  );
}

main().catch((err) => {
  console.error('Seed failed:', err);
  process.exit(1);
});
