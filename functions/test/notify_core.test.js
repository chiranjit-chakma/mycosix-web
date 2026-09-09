/**
 * Behavioural tests for the push-notification core, against an in-memory fake
 * Firestore + a fake FCM sender (no emulator, no network).
 * `node --test test/`.
 */

'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');

const notify = require('../notify_core.js');

const CODE = 'MYC-ABC23456'; // matches the real order-code shape

/* ------------------------------------------------------------------ *
 * Minimal in-memory Firestore (docs under collection.doc(id), collection.get,
 * doc.update, and runTransaction with get/update - enough for notify_core)
 * ------------------------------------------------------------------ */
function clone(v) {
  return v === undefined ? undefined : JSON.parse(JSON.stringify(v));
}

function makeDb(seed = {}) {
  const store = new Map();
  for (const [path, data] of Object.entries(seed)) store.set(path, clone(data));

  function merge(existing, patch) {
    const base = existing ? clone(existing) : {};
    for (const [k, v] of Object.entries(patch)) base[k] = clone(v);
    return base;
  }

  function snapAt(parts) {
    const path = parts.join('/');
    const doc = store.get(path);
    return {
      exists: doc !== undefined,
      id: parts[parts.length - 1],
      data: () => (doc === undefined ? null : clone(doc)),
    };
  }

  function refFor(name, id) {
    const parts = [name, id];
    return {
      parts,
      id,
      get: async () => snapAt(parts),
      update: async (patch) => {
        const path = parts.join('/');
        store.set(path, merge(store.get(path), patch));
      },
    };
  }

  let counter = 0;
  function collection(name) {
    return {
      doc(id) {
        if (id === undefined) id = '__auto' + String(++counter).padStart(6, '0');
        return refFor(name, id);
      },
      get: async () => {
        const prefix = name + '/';
        const docs = [];
        for (const path of store.keys()) {
          if (path.startsWith(prefix) && !path.slice(prefix.length).includes('/')) {
            docs.push({ id: path.slice(prefix.length) });
          }
        }
        return { docs };
      },
    };
  }

  return {
    collection,
    runTransaction: async (fn) => {
      const tx = {
        get: async (r) => snapAt(r.parts),
        update: async (r, patch) => {
          const path = r.parts.join('/');
          store.set(path, merge(store.get(path), patch));
        },
      };
      return fn(tx);
    },
    _store: store,
    _dump: () => clone(Object.fromEntries(store)),
  };
}

/* ------------------------------------------------------------------ *
 * Fake FCM sender: records every message; configured dead tokens answer
 * "registration-token-not-registered" so the core must prune them.
 * ------------------------------------------------------------------ */
function makeSend(dead = []) {
  const deadSet = new Set(dead);
  const sent = [];
  const send = async (msg) => {
    sent.push(clone(msg));
    return deadSet.has(msg.token)
      ? { ok: false, unregistered: true }
      : { ok: true };
  };
  return { send, sent, deadSet };
}

const tokensOf = (db, uid) => {
  const raw = db._dump()['fcmTokens/' + uid];
  return raw ? raw.tokens : undefined;
};

/* A signed-in customer with two live tokens. */
function statusDb(extra = {}) {
  return makeDb(
    Object.assign(
      {
        'orders/o1': { orderId: CODE, status: 'New', customerId: 'u1' },
        'fcmTokens/u1': { tokens: ['t-live-1', 't-live-2'] },
      },
      extra,
    ),
  );
}

// Runs the customer-status path as the trigger would: after = {id, data}.
async function runStatus(db, send, afterData) {
  return notify.onOrderUpdated(
    { db, send },
    { after: { id: 'o1', data: () => afterData } },
  );
}
/* ------------------------------------------------------------------ *
 * Copy + pure decisions
 * ------------------------------------------------------------------ */
test('wording mirrors the open-app banner (human order code)', () => {
  assert.equal(notify.customerTitle(CODE, 'Confirmed'), 'Order ' + CODE + ' is confirmed');
  assert.equal(notify.customerTitle(CODE, 'Delivered'), 'Order ' + CODE + ' has been delivered');
  assert.equal(notify.customerTitle(CODE, 'Cancelled'), 'Order ' + CODE + ' was cancelled');
  assert.equal(notify.adminTitle(CODE), 'New order ' + CODE);
  assert.ok(notify.customerBody('Delivered').length > 0);
});

test('shouldSendCustomerStatus honours the notify set and no-duplicate rule', () => {
  assert.equal(notify.shouldSendCustomerStatus('Confirmed', undefined), true);
  assert.equal(notify.shouldSendCustomerStatus('Confirmed', 'Confirmed'), false);
  assert.equal(notify.shouldSendCustomerStatus('Preparing', 'Confirmed'), false);
  assert.equal(notify.shouldSendCustomerStatus('New', 'New'), false);
  assert.equal(notify.shouldSendNewOrder(false), true);
  assert.equal(notify.shouldSendNewOrder(true), false);
});

test('messageFor carries string-only data with doc id and human code', () => {
  const msg = notify.messageFor('orderStatus', {
    token: 'tok',
    title: 'Order ' + CODE + ' is confirmed',
    body: 'x',
    orderDocId: 'o1',
    orderCode: CODE,
    status: 'Confirmed',
  });
  assert.equal(msg.token, 'tok');
  assert.equal(msg.notification.title, 'Order ' + CODE + ' is confirmed');
  assert.equal(msg.data.mxKind, 'orderStatus');
  assert.equal(msg.data.orderDocId, 'o1');
  assert.equal(msg.data.orderCode, CODE);
  assert.equal(msg.data.status, 'Confirmed');
  for (const [k, v] of Object.entries(msg.data)) {
    assert.equal(typeof v, 'string', 'data.' + k + ' must be a string');
  }
});

/* ------------------------------------------------------------------ *
 * Customer status pushes
 * ------------------------------------------------------------------ */
test('a notify-worthy transition pushes once to the owning customer only', async () => {
  const db = statusDb();
  const { send, sent } = makeSend();
  const res = await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Confirmed' });
  assert.equal(res.sent, 2, 'both of the customer tokens get the push');
  assert.equal(sent.length, 2);
  for (const m of sent) {
    assert.equal(m.token.startsWith('t-live-'), true);
    assert.equal(m.data.mxKind, 'orderStatus');
    assert.equal(m.notification.title, 'Order ' + CODE + ' is confirmed');
  }
  assert.equal(db._dump()['orders/o1'].notify.lastStatus, 'Confirmed');
});

test('re-delivering the same status never double-notifies', async () => {
  const db = statusDb();
  const { send, sent } = makeSend();
  await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Confirmed' });
  const first = sent.length;
  const again = await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Confirmed' });
  assert.equal(again.skipped, 'duplicate');
  assert.equal(sent.length, first, 'no second push');
});

test('advancing to the next notify-worthy status pushes again', async () => {
  const db = statusDb();
  const { send, sent } = makeSend();
  await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Confirmed' });
  const res = await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Delivered' });
  assert.equal(res.sent, 2);
  assert.equal(sent[sent.length - 1].notification.title, 'Order ' + CODE + ' has been delivered');
  assert.equal(db._dump()['orders/o1'].notify.lastStatus, 'Delivered');
});

test('internal shop statuses never push and leave the marker alone', async () => {
  const db = statusDb();
  const { send, sent } = makeSend();
  await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Confirmed' });
  const before = sent.length;
  const res = await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Preparing' });
  assert.equal(res.skipped, 'status-not-notify-worthy');
  assert.equal(sent.length, before);
  assert.equal(db._dump()['orders/o1'].notify.lastStatus, 'Confirmed');
});

test('guest orders (no customerId) never push', async () => {
  const db = statusDb();
  const { send, sent } = makeSend();
  const res = await runStatus(db, send, { orderId: CODE, status: 'Confirmed' });
  assert.equal(res.skipped, 'no-customer');
  assert.equal(sent.length, 0);
  assert.equal(db._dump()['orders/o1'].notify, undefined, 'no claim marker written');
});
test('a dead registration token is pruned, the live one still gets the push', async () => {
  const db = statusDb({ 'fcmTokens/u1': { tokens: ['t-dead', 't-live'] } });
  const { send, sent } = makeSend(['t-dead']);
  const res = await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Delivered' });
  assert.equal(res.sent, 1, 'only the live device counts as sent');
  assert.equal(res.unregistered, 1, 'the dead token is reported for pruning');
  assert.equal(sent.length, 2, 'the core still attempted both before pruning');
  assert.deepEqual(tokensOf(db, 'u1'), ['t-live'], 'dead token removed from the doc');
});

test('a customer with no registered tokens is skipped quietly', async () => {
  const db = statusDb({ 'fcmTokens/u1': { tokens: [] } });
  const { send, sent } = makeSend();
  const res = await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Cancelled' });
  assert.equal(res.skipped, 'no-tokens');
  assert.equal(sent.length, 0);
  assert.equal(db._dump()['orders/o1'].notify.lastStatus, 'Cancelled', 'marker still advances');
});

/* ------------------------------------------------------------------ *
 * Admin new-order pushes
 * ------------------------------------------------------------------ */
function adminDb() {
  return makeDb({
    'admins/a1': { seededAt: true },
    'admins/a2': { seededAt: true },
    'fcmTokens/a1': { tokens: ['adm-1'] },
    'fcmTokens/a2': { tokens: ['adm-2'] },
  });
}

async function runNew(db, send) {
  return notify.onOrderCreated(
    { db, send },
    { id: 'o9', data: () => ({ orderId: CODE }) },
  );
}

test('every admin with tokens is told about a new order once', async () => {
  const db = adminDb();
  const { send, sent } = makeSend();
  const res = await runNew(db, send);
  assert.equal(res.admins, 2);
  assert.equal(res.sent, 2);
  assert.equal(sent.length, 2);
  const tokens = sent.map((m) => m.token).sort();
  assert.deepEqual(tokens, ['adm-1', 'adm-2']);
  for (const m of sent) {
    assert.equal(m.data.mxKind, 'adminNewOrder');
    assert.equal(m.notification.title, 'New order ' + CODE);
    assert.equal(m.data.status, 'New');
  }
  assert.equal(db._dump()['orders/o9'].notify.newOrderSent, true);
});

test('a new-order event never replays (claim marker holds)', async () => {
  const db = adminDb();
  const { send, sent } = makeSend();
  await runNew(db, send);
  const first = sent.length;
  const again = await runNew(db, send);
  assert.equal(again.skipped, 'duplicate');
  assert.equal(sent.length, first);
});

test('admins without tokens receive nothing (and no message to customers)', async () => {
  const db = makeDb({
    'admins/a3': { seededAt: true },
  });
  const { send, sent } = makeSend();
  const res = await runNew(db, send);
  assert.equal(res.admins, 0, 'admin list filters to those with tokens');
  assert.equal(res.sent, 0);
  assert.equal(sent.length, 0);
  assert.equal(db._dump()['orders/o9'].notify.newOrderSent, true, 'marker still set');
});

test('customer pushes never reach admin tokens, and vice-versa', async () => {
  // One Firestore world holding BOTH a customer and an admin token.
  const db = makeDb({
    'orders/o1': { orderId: CODE, status: 'New', customerId: 'u1' },
    'fcmTokens/u1': { tokens: ['cust-live'] },
    'admins/a1': { seededAt: true },
    'fcmTokens/a1': { tokens: ['adm-1'] },
  });
  const { send, sent } = makeSend();
  await runStatus(db, send, { customerId: 'u1', orderId: CODE, status: 'Delivered' });
  assert.deepEqual(
    sent.map((m) => m.token),
    ['cust-live'],
    'a customer status push goes only to the customer token',
  );
  sent.length = 0;
  await notify.onOrderCreated(
    { db, send },
    { id: 'o9', data: () => ({ orderId: CODE }) },
  );
  assert.deepEqual(
    sent.map((m) => m.token),
    ['adm-1'],
    'a new-order push goes only to the admin token',
  );
});
