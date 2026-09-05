/**
 * MYCOSIX trusted order backend.
 *
 * The website NEVER writes to `orders` directly. Orders are placed through
 * this callable, which:
 *   1. validates the draft (no prices are accepted from the browser),
 *   2. reads the real product catalogue + site config from Firestore,
 *   3. computes authoritative prices/totals, checks availability + stock,
 *   4. in a single transaction: decrements stock and writes the order,
 *   5. returns the stored order (id, prices, timestamps).
 *
 * The core (`placeOrder`) is pure of Firebase Functions wiring so it can be
 * tested against an in-memory fake Firestore (`node --test`).
 */

'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const { randomInt } = require('crypto');

/* ------------------------------------------------------------------ *
 * Config mirroring the bundled MxConfig defaults. The single source of
 * truth at runtime is the `siteConfig/public` document, which overrides
 * these when present.
 * ------------------------------------------------------------------ */
const DEFAULTS = {
  deliveryFee: 39.0,
  deliveryEnabled: true,
  currency: 'INR',
  maxUnitsPerProduct: 12,
};

const ORDER_STATUS_NEW = 'New'; // OrderStatus.newOrder.label

// Matches WhatsAppOrderService._idChars: no 0/O or 1/I.
const ID_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
const ID_CHAR_COUNT = ID_CHARS.length;

const MAPS_HOSTS = new Set([
  'maps.app.goo.gl',
  'goo.gl',
  'google.com',
  'www.google.com',
  'maps.google.com',
  'googlemaps.com',
  'www.googlemaps.com',
]);

// Delivery plausibility box (the Indian subcontinent). Kept generous so
// genuine customers are never blocked; relax if the business expands.
const LAT_MIN = 6;
const LAT_MAX = 37;
const LNG_MIN = 68;
const LNG_MAX = 98;

const MAX_ITEMS = 30;
const MAX_OPTIONAL_LEN = 160;
const MAX_INSTRUCTIONS_LEN = 400;

/* ------------------------------------------------------------------ *
 * Errors
 * ------------------------------------------------------------------ */
class DomainError extends Error {
  constructor(code, message) {
    super(message);
    this.name = 'DomainError';
    this.code = code; // an https HttpsError code
  }
}

function fail(code, message) {
  return new DomainError(code, message);
}

/* ------------------------------------------------------------------ *
 * Small helpers
 * ------------------------------------------------------------------ */
function round2(v) {
  return Math.round(v * 100) / 100;
}

function str(v, fallback) {
  return typeof v === 'string' && v.trim() ? v.trim() : fallback;
}

function optStr(v, maxLen) {
  if (typeof v !== 'string') return undefined;
  const t = v.trim();
  if (!t) return undefined;
  return t.slice(0, maxLen);
}

/** Non-negative finite number, or null. */
function toNonNeg(v) {
  if (typeof v === 'number' && Number.isFinite(v) && v >= 0) return v;
  if (typeof v === 'string' && v.trim() !== '') {
    const n = Number(v);
    if (Number.isFinite(n) && n >= 0) return n;
  }
  return null;
}

function isValidEmail(s) {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s);
}

function makeOrderId() {
  let out = 'MYC-';
  for (let i = 0; i < 8; i++) {
    out += ID_CHARS[randomInt(ID_CHAR_COUNT)];
  }
  return out;
}

function isValidMapsUrl(raw) {
  if (typeof raw !== 'string') return false;
  let u;
  try {
    u = new URL(raw.trim());
  } catch (_) {
    return false;
  }
  if (u.protocol !== 'https:' && u.protocol !== 'http:') return false;
  const host = u.hostname.toLowerCase();
  if (!MAPS_HOSTS.has(host)) return false;
  // A google.com/maps URL needs the /maps path; short links need a code.
  if (host === 'google.com' || host === 'www.google.com') {
    return u.pathname.toLowerCase().startsWith('/maps');
  }
  return u.pathname.length > 1;
}

function toIso(v) {
  if (v instanceof Date) return v.toISOString();
  if (v && typeof v.toDate === 'function') {
    try {
      return v.toDate().toISOString();
    } catch (_) {
      return undefined;
    }
  }
  if (typeof v === 'string') return v;
  return undefined;
}

/* ------------------------------------------------------------------ *
 * Input cleansing + validation. Throws DomainError on any problem.
 * ------------------------------------------------------------------ */
function cleanse(data) {
  if (data === null || typeof data !== 'object' || Array.isArray(data)) {
    throw fail('invalid-argument', 'The order data was not understood. Please try again.');
  }

  const customerName = typeof data.customerName === 'string'
    ? data.customerName.trim()
    : '';
  if (customerName.length < 2 || customerName.length > 80) {
    throw fail('invalid-argument', 'Please enter your name.');
  }

  const phone = typeof data.phone === 'string'
    ? data.phone.replace(/[^0-9]/g, '')
    : '';
  if (phone.length < 10 || phone.length > 13) {
    throw fail('invalid-argument', 'Please enter a valid phone number.');
  }

  let email;
  if (typeof data.email === 'string' && data.email.trim()) {
    email = data.email.trim();
    if (!isValidEmail(email)) {
      throw fail('invalid-argument', 'The email address does not look valid.');
    }
  }

  const lat = typeof data.latitude === 'number' ? data.latitude : NaN;
  const lng = typeof data.longitude === 'number' ? data.longitude : NaN;
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) {
    throw fail('invalid-argument', 'The delivery location was not recognised.');
  }
  if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
    throw fail('invalid-argument', 'The delivery location was not recognised.');
  }
  if (lat < LAT_MIN || lat > LAT_MAX || lng < LNG_MIN || lng > LNG_MAX) {
    throw fail(
      'failed-precondition',
      'That pinned delivery location is outside the area we deliver to.',
    );
  }

  const mapsUrl = typeof data.mapsUrl === 'string' ? data.mapsUrl.trim() : '';
  if (!isValidMapsUrl(mapsUrl)) {
    throw fail(
      'invalid-argument',
      'The pinned delivery link is not a valid Google Maps link.',
    );
  }

  const building = optStr(data.building, MAX_OPTIONAL_LEN);
  const apartment = optStr(data.apartment, MAX_OPTIONAL_LEN);
  const landmark = optStr(data.landmark, MAX_OPTIONAL_LEN);
  const instructions = optStr(data.instructions, MAX_INSTRUCTIONS_LEN);

  const rawItems = Array.isArray(data.items) ? data.items : null;
  if (!rawItems || rawItems.length === 0) {
    throw fail('invalid-argument', 'Your order is empty. Add something first.');
  }
  if (rawItems.length > MAX_ITEMS) {
    throw fail('invalid-argument', 'That order has too many different items.');
  }

  const seen = new Set();
  const items = rawItems.map((it) => {
    if (it === null || typeof it !== 'object') {
      throw fail('invalid-argument', 'One of the items in your order is not valid.');
    }
    const productId = typeof it.productId === 'string' ? it.productId.trim() : '';
    if (!productId || productId.length > 100) {
      throw fail('invalid-argument', 'One of the items in your order is not valid.');
    }
    if (seen.has(productId)) {
      throw fail(
        'invalid-argument',
        'An item appears more than once. Please refresh your cart and try again.',
      );
    }
    seen.add(productId);
    const qty = it.quantity;
    if (!Number.isInteger(qty) || qty < 1 || qty > DEFAULTS.maxUnitsPerProduct) {
      throw fail(
        'invalid-argument',
        'Item quantities must be between 1 and ' +
          DEFAULTS.maxUnitsPerProduct +
          '.',
      );
    }
    return { productId, quantity: qty };
  });

  return {
    customerName,
    phone,
    email,
    latitude: lat,
    longitude: lng,
    mapsUrl,
    building,
    apartment,
    landmark,
    instructions,
    items,
  };
}

/* ------------------------------------------------------------------ *
 * Core order placement (pure of Functions wiring; transaction over a db).
 * ------------------------------------------------------------------ */
async function placeOrder(db, data, { now = () => new Date() } = {}) {
  const c = cleanse(data);

  const ordersCol = db.collection('orders');
  const productsCol = db.collection('products');
  const configRef = db.collection('siteConfig').doc('public');

  const outcome = await db.runTransaction(async (tx) => {
    const cfgSnap = await tx.get(configRef);
    const cfg = cfgSnap.exists ? cfgSnap.data() || {} : {};

    if (cfg.deliveryEnabled === false) {
      throw fail(
        'failed-precondition',
        'We are not accepting delivery orders right now. Please try again later.',
      );
    }
    let deliveryFee = toNonNeg(cfg.deliveryFee);
    if (deliveryFee === null) deliveryFee = DEFAULTS.deliveryFee;
    const currency = typeof cfg.currency === 'string' && cfg.currency.trim()
      ? cfg.currency.trim()
      : DEFAULTS.currency;

    const lines = [];
    for (const item of c.items) {
      const ref = productsCol.doc(item.productId);
      const snap = await tx.get(ref);
      const missingMsg =
        'One of the items in your order is no longer available. ' +
        'Please refresh the page and try again.';
      if (!snap.exists) throw fail('failed-precondition', missingMsg);
      const p = snap.data() || {};
      const name = str(p.name, 'An item');
      if (p.available === false) {
        throw fail(
          'failed-precondition',
          name +
            ' is not available right now. Please refresh the page and try again.',
        );
      }
      const price = toNonNeg(p.price);
      if (price === null) {
        throw fail(
          'failed-precondition',
          'We could not confirm a price for ' + name + '. Please contact us on WhatsApp.',
        );
      }
      const stock = Number.isInteger(p.stock) ? p.stock : 0;
      if (stock < item.quantity) {
        const left = stock <= 0 ? 'is out of stock' :
          'only has ' + stock + ' left in stock';
        throw fail(
          'failed-precondition',
          name + ' ' + left + '. Please adjust the quantity and try again.',
        );
      }
      const unitPrice = round2(price);
      lines.push({
        productId: item.productId,
        productName: name,
        variant: optStr(p.variant, 120),
        weight: optStr(p.weight, 120),
        quantity: item.quantity,
        unitPrice,
        lineTotal: round2(unitPrice * item.quantity),
      });
      tx.update(ref, {
        stock: stock - item.quantity,
        updatedAt: now(),
      });
    }

    const subtotal = round2(lines.reduce((sum, l) => sum + l.lineTotal, 0));
    const total = round2(subtotal + deliveryFee);
    const ts = now();

    const doc = {
      orderId: makeOrderId(),
      customerName: c.customerName,
      phone: c.phone,
      items: lines,
      subtotal,
      deliveryFee,
      total,
      currency,
      latitude: c.latitude,
      longitude: c.longitude,
      mapsUrl: c.mapsUrl,
      status: ORDER_STATUS_NEW,
      createdAt: ts,
      updatedAt: ts,
    };
    if (c.email) doc.email = c.email;
    if (c.building) doc.building = c.building;
    if (c.apartment) doc.apartment = c.apartment;
    if (c.landmark) doc.landmark = c.landmark;
    if (c.instructions) doc.instructions = c.instructions;

    const orderRef = ordersCol.doc();
    tx.set(orderRef, doc);
    return { orderRef, doc };
  });

  // Read back so timestamps are the stored ones (Date -> Firestore Timestamp).
  const after = await outcome.orderRef.get();
  const stored = after.exists ? after.data() || outcome.doc : outcome.doc;

  return {
    id: outcome.orderRef.id,
    order: {
      ...stored,
      createdAt: toIso(stored.createdAt),
      updatedAt: toIso(stored.updatedAt),
    },
  };
}

/* ------------------------------------------------------------------ *
 * Firebase wiring (thin)
 * ------------------------------------------------------------------ */
let db;

function getDb() {
  if (!db) {
    if (!admin.apps.length) {
      admin.initializeApp();
    }
    db = admin.firestore();
  }
  return db;
}

exports.createOrder = functions.https.onCall(async (data) => {
  try {
    return await placeOrder(getDb(), data);
  } catch (err) {
    if (err instanceof DomainError) {
      throw new functions.https.HttpsError(err.code, err.message);
    }
    functions.logger.error('createOrder failed', err);
    throw new functions.https.HttpsError(
      'internal',
      'Your order could not be placed right now. Please try again, or message us on WhatsApp.',
    );
  }
});

exports._test = { placeOrder, cleanse, DEFAULTS, toIso, makeOrderId };
