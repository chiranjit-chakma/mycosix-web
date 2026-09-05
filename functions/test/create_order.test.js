/**
 * Behavioural tests for the trusted order function core, run against an
 * in-memory fake Firestore (no emulator, no network). `node --test test/`.
 */

'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const { _test } = require('../index.js');
const { placeOrder, cleanse, DEFAULTS } = _test;

/* ------------------------------------------------------------------ *
 * Minimal in-memory Firestore
 * ------------------------------------------------------------------ */
function clone(v) {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

function makeDb(seed = {}) {
  const store = new Map();
  for (const [path, data] of Object.entries(seed)) {
    store.set(path, clone(data));
  }
  let counter = 0;

  function snapshot(parts) {
    const path = parts.join('/');
    return {
      exists: store.has(path),
      id: parts[parts.length - 1],
      data: () => clone(store.get(path) || {}),
    };
  }

  function ref(parts) {
    return {
      parts,
      id: parts[parts.length - 1],
      get: async () => snapshot(parts),
    };
  }

  function collection(name) {
    return {
      doc(id) {
        if (id === undefined) {
          id = '__auto' + String(++counter).padStart(6, '0');
        }
        return ref([name, id]);
      },
    };
  }

  return {
    collection,
    runTransaction: async (fn) => {
      const tx = {
        get: async (r) => snapshot(r.parts),
        set: async (r, data) => {
          store.set(r.parts.join('/'), clone(data));
        },
        update: async (r, patch) => {
          const path = r.parts.join('/');
          store.set(path, Object.assign(store.get(path) || {}, clone(patch)));
        },
      };
      return fn(tx);
    },
    dump: () => clone(Object.fromEntries(store)),
  };
}

/* ------------------------------------------------------------------ *
 * Fixtures
 * ------------------------------------------------------------------ */
const OYSTER = {
  id: 'oyster',
  name: 'Fresh Oyster Mushroom',
  variant: 'Fresh',
  weight: '250 g',
  price: 120,
  stock: 10,
  available: true,
};
const DRIED = {
  id: 'dried',
  name: 'Dried Slices',
  variant: 'Dried',
  weight: '100 g',
  price: 200,
  stock: 3,
  available: true,
};
const CONFIG = {
  deliveryFee: 39,
  deliveryEnabled: true,
  currency: 'INR',
};

function seededDb(overrides = {}) {
  const seed = Object.assign(
    {
      'products/oyster': Object.assign({}, OYSTER),
      'products/dried': Object.assign({}, DRIED),
      'siteConfig/public': Object.assign({}, CONFIG),
    },
    overrides,
  );
  return makeDb(seed);
}

function draft(overrides = {}) {
  return Object.assign(
    {
      customerName: 'Test Customer',
      phone: '+91 98765 43210',
      email: 'customer@example.com',
      latitude: 17.385,
      longitude: 78.4867,
      mapsUrl: 'https://maps.app.goo.gl/AbCdEf123',
      building: '4th floor',
      instructions: 'Ring the bell twice',
      items: [
        { productId: 'oyster', quantity: 2 },
        { productId: 'dried', quantity: 1 },
      ],
    },
    overrides,
  );
}

function approx(a, b) {
  assert.ok(
    Math.abs(a - b) < 0.001,
    `expected ${a} ~ ${b}`,
  );
}

function expectRejected(promise, code, re) {
  return promise.then(
    () => {
      throw new Error('expected order to be rejected');
    },
    (err) => {
      assert.equal(err.name, 'DomainError');
      assert.equal(err.code, code);
      if (re) assert.match(err.message, re);
    },
  );
}

/* ------------------------------------------------------------------ *
 * Tests
 * ------------------------------------------------------------------ */
test('places a valid order with trusted pricing and stock', async () => {
  const db = seededDb();
  const d = draft();
  const res = await placeOrder(db, d);

  assert.equal(typeof res.id, 'string');
  assert.ok(res.id.length > 0);
  assert.equal(res.order.status, 'New');
  assert.equal(res.order.currency, 'INR');
  assert.match(res.order.orderId, /^MYC-[A-HJ-NP-Z2-9]{8}$/);
  assert.equal(res.order.orderId.length, 12);
  assert.equal(res.order.customerName, 'Test Customer');
  assert.equal(res.order.phone, '919876543210');
  assert.equal(res.order.email, 'customer@example.com');
  assert.equal(typeof res.order.createdAt, 'string');
  assert.equal(typeof res.order.updatedAt, 'string');

  // 2 x 120 + 1 x 200 = 440, + 39 delivery = 479.
  approx(res.order.subtotal, 440);
  approx(res.order.deliveryFee, 39);
  approx(res.order.total, 479);
  assert.equal(res.order.items.length, 2);
  assert.equal(res.order.items[0].productName, 'Fresh Oyster Mushroom');
  assert.equal(res.order.items[0].quantity, 2);
  assert.equal(res.order.items[0].unitPrice, 120);
  assert.equal(res.order.items[0].lineTotal, 240);

  // Stock decremented atomically and persisted.
  const all = db.dump();
  assert.equal(all['products/oyster'].stock, 8);
  assert.equal(all['products/dried'].stock, 2);
  assert.ok(all['orders/' + res.id], 'order document persisted');
  assert.equal(all['orders/' + res.id].orderId, res.order.orderId);
});

test('ignores any prices sent by the browser', async () => {
  const db = seededDb();
  const d = draft({
    items: [
      { productId: 'oyster', quantity: 1, price: 1, name: 'Hacked' },
    ],
    subtotal: 1,
    total: 1,
  });
  const res = await placeOrder(db, d);
  approx(res.order.subtotal, 120);
  approx(res.order.total, 159);
  assert.equal(res.order.items[0].productName, 'Fresh Oyster Mushroom');
});

test('rejects when a product is unavailable', () => {
  const db = seededDb({
    'products/oyster': Object.assign({}, OYSTER, { stock: 5, available: false }),
  });
  return expectRejected(
    placeOrder(db, draft()),
    'failed-precondition',
    /not available right now/,
  );
});

test('rejects when stock is insufficient and writes nothing', async () => {
  const db = seededDb({
    'products/dried': Object.assign({}, DRIED, { stock: 1 }),
  });
  await expectRejected(
    placeOrder(db, draft({
      items: [{ productId: 'dried', quantity: 2 }],
    })),
    'failed-precondition',
    /only has 1 left in stock/,
  );
  const all = db.dump();
  assert.equal(all['products/dried'].stock, 1, 'stock untouched');
  const orderPaths = Object.keys(all).filter((p) => p.startsWith('orders/'));
  assert.equal(orderPaths.length, 0, 'no order written');
});

test('rejects coordinates far outside the service area', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(db, draft({ latitude: 0, longitude: 0 })),
    'failed-precondition',
    /outside the area/,
  );
});

test('rejects out-of-range coordinates as malformed input', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(db, draft({ latitude: 200, longitude: 0 })),
    'invalid-argument',
  );
});

test('rejects a quantity above the per-line ceiling', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(db, draft({ items: [{ productId: 'oyster', quantity: 13 }] })),
    'invalid-argument',
    /between 1 and 12/,
  );
});

test('rejects a non-integer / zero quantity', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(db, draft({ items: [{ productId: 'oyster', quantity: 0 }] })),
    'invalid-argument',
  );
});

test('rejects a malformed phone number', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(db, draft({ phone: '123' })),
    'invalid-argument',
    /valid phone number/,
  );
});

test('rejects a maps link that is not a Google Maps link', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(db, draft({ mapsUrl: 'https://evil.example.com/x' })),
    'invalid-argument',
    /Google Maps link/,
  );
});

test('rejects when delivery is paused in siteConfig', () => {
  const db = seededDb({
    'siteConfig/public': { deliveryFee: 39, deliveryEnabled: false },
  });
  return expectRejected(
    placeOrder(db, draft()),
    'failed-precondition',
    /not accepting delivery orders/,
  );
});

test('rejects duplicate product ids', () => {
  const db = seededDb();
  return expectRejected(
    placeOrder(
      db,
      draft({ items: [
        { productId: 'oyster', quantity: 1 },
        { productId: 'oyster', quantity: 1 },
      ] }),
    ),
    'invalid-argument',
    /appears more than once/,
  );
});

test('uses bundled defaults when siteConfig/public does not exist', async () => {
  const db = makeDb({
    'products/oyster': { name: 'Fresh Oyster Mushroom', price: 120, stock: 5, available: true },
  });
  const res = await placeOrder(
    db,
    draft({ items: [{ productId: 'oyster', quantity: 1 }] }),
  );
  approx(res.order.deliveryFee, DEFAULTS.deliveryFee);
  assert.equal(res.order.currency, 'INR');
});

test('omits blank optional fields from the stored order', async () => {
  const db = seededDb();
  const res = await placeOrder(
    db,
    draft({ building: '   ', instructions: '', email: '   ' }),
  );
  assert.equal(res.order.building, undefined);
  assert.equal(res.order.instructions, undefined);
  assert.equal(res.order.email, undefined);
});

test('cleanse rejects a completely empty order', () => {
  assert.throws(() => cleanse({}), (err) => err.code === 'invalid-argument');
});
