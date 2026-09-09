/**
 * MYCOSIX push-notification backend (CORE - pure of any firebase import).
 *
 * Delivers the same two order events the open-app banner shows, but to a
 * phone/PWA that is closed or backgrounded, via FCM. The live website needs
 * NO change to turn it on: notify_triggers.js is deployed once the project is
 * on the paid (Blaze) plan and simply calls the handlers here. Until then this
 * module is dormant and fully unit-tested against in-memory fakes.
 *
 * Trust boundaries (enforced server-side - this code IS the server):
 *  - Customer status pushes go ONLY to the order's own `customerId` token
 *    list. That id is stamped by the order backend from the caller's auth and
 *    status updates are admin-only under the rules, so a customer can neither
 *    forge whose push fires nor write a status that would trigger one.
 *  - Admin new-order pushes go to every uid with an admins/{uid} grant
 *    (admins cannot self-grant under the rules) - never to customers.
 *  - FCM tokens live in fcmTokens/{uid}, readable/writable only by that uid
 *    (rules) or by this Admin SDK.
 *
 * Idempotency is a claim-marker guard, so a repeated update or an at-least-
 * once redelivery can never double-notify:
 *  - New order: `orders/{id}/notify.newOrderSent` is written in a transaction
 *    BEFORE any send; a second invocation sees it and skips.
 *  - Customer status: `orders/{id}/notify.lastStatus` records the last status
 *    a push was sent for. Re-delivering the same status skips; advancing to a
 *    new notify-worthy status sends again. Mirrors the open-app watcher.
 *
 * When FCM reports a registration token is no longer valid it is pruned from
 * the owner's fcmTokens doc, so dead devices never slow the queue.
 */

'use strict';

const CUSTOMER_NOTIFY_STATUSES = new Set([
  'Confirmed',
  'Out for Delivery',
  'Delivered',
  'Cancelled',
]);

const KIND_ORDER_STATUS = 'orderStatus';
const KIND_ADMIN_NEW_ORDER = 'adminNewOrder';

// Order-document bookkeeping: notifications live under `notify` on the order,
// written by the Admin SDK (rules bypassed) - a browser can never touch them.
const MARKER = 'notify';
const NEW_ORDER_SENT = 'newOrderSent';
const LAST_STATUS = 'lastStatus';

/* ------------------------------------------------------------------ *
 * Copy. Kept in lockstep with lib/models/order_notice.dart so the closed-app
 * push reads identically to the open-app banner. `code` is the human order
 * number the customer already knows from My Orders / WhatsApp.
 * ------------------------------------------------------------------ */
function customerTitle(code, status) {
  switch (status) {
    case 'Confirmed':
      return 'Order ' + code + ' is confirmed';
    case 'Out for Delivery':
      return 'Order ' + code + ' is out for delivery';
    case 'Delivered':
      return 'Order ' + code + ' has been delivered';
    case 'Cancelled':
      return 'Order ' + code + ' was cancelled';
    default:
      return 'Order ' + code + ' updated';
  }
}

function customerBody(status) {
  switch (status) {
    case 'Confirmed':
      return 'Your mushrooms are in the works.';
    case 'Out for Delivery':
      return 'Your mushrooms are on the way!';
    case 'Delivered':
      return 'Enjoy your fresh mushrooms - thank you!';
    case 'Cancelled':
      return 'No payment was taken. Message us on WhatsApp with any questions.';
    default:
      return '';
  }
}

function adminTitle(code) {
  return 'New order ' + code;
}

function adminBody() {
  return 'An order just arrived - review it when you are ready.';
}

/* ------------------------------------------------------------------ *
 * Pure decisions
 * ------------------------------------------------------------------ */
// Notify when the stored status is customer-facing AND it is not the last
// status we already pushed for (repeated updates of the same status are quiet).
function shouldSendCustomerStatus(currentStatus, lastSentStatus) {
  return (
    CUSTOMER_NOTIFY_STATUSES.has(currentStatus) &&
    currentStatus !== lastSentStatus
  );
}

// New orders alert exactly once per document, ever.
function shouldSendNewOrder(alreadySent) {
  return !alreadySent;
}
/* ------------------------------------------------------------------ *
 * Messaging
 * ------------------------------------------------------------------ */
// The full FCM v1 message the wrapper sends verbatim. `data` is always the
// small string map a client reads on tap to route (order doc id = identity,
// human code = display). All data values are strings as FCM requires.
function messageFor(kind, o) {
  const code = o.orderCode || o.orderDocId;
  return {
    token: o.token,
    notification: { title: o.title, body: o.body || '' },
    data: {
      mxKind: kind,
      orderDocId: o.orderDocId,
      orderCode: code,
      status: o.status || '',
    },
    webpush: { headers: { TTL: '604800' } },
    android: { priority: 'high', ttl: 604800000 },
    apns: { headers: { 'apns-priority': '10', 'apns-expiration': '604800' } },
  };
}

/* ------------------------------------------------------------------ *
 * Tokens (fcmTokens/{uid}.tokens: an array of registration tokens)
 * ------------------------------------------------------------------ */
function normalizeTokens(raw) {
  if (!Array.isArray(raw)) return [];
  return raw.filter((t) => typeof t === 'string' && t.length > 0);
}

async function tokensFor(db, uid) {
  const ref = db.collection('fcmTokens').doc(uid);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : {};
  return { uid, ref, tokens: normalizeTokens(data.tokens) };
}

// Prunes dead registration tokens from the owner's doc. The array is re-read
// then written whole: the owner prunes locally on sign-out too, and the
// backend only prunes on an explicit "not registered" answer, so a lost race
// simply heals on the next push.
async function pruneTokens(db, uid, toRemove) {
  if (!toRemove || !toRemove.length) return 0;
  const { ref, tokens } = await tokensFor(db, uid);
  if (!tokens.length) return 0;
  const gone = new Set(toRemove);
  const kept = tokens.filter((t) => !gone.has(t));
  if (kept.length === tokens.length) return 0;
  await ref.update({ tokens: kept });
  return tokens.length - kept.length;
}

// deps.send(msg) resolves (never rejects by contract) to {ok, unregistered}.
async function safeSend(send, msg) {
  try {
    const res = await send(msg);
    return res && res.unregistered ? { ok: false, unregistered: true } : { ok: true };
  } catch (_) {
    return { ok: false, unregistered: false };
  }
}

// Sends one message per token, prunes anything FCM reports dead, and reports
// how many live devices were reached.
async function sendToTokens(db, send, uid, tokens, build) {
  const dead = [];
  for (const token of tokens) {
    const res = await safeSend(send, build(token));
    if (res.unregistered) dead.push(token);
  }
  const pruned = dead.length ? await pruneTokens(db, uid, dead) : 0;
  return { sent: tokens.length - dead.length, unregistered: pruned };
}
/* ------------------------------------------------------------------ *
 * Claim markers (idempotency). Each writes BEFORE any send, in a transaction,
 * so an at-least-once redelivery observes the marker and skips.
 * ------------------------------------------------------------------ */
function readMarker(data) {
  const m = data && typeof data === 'object' ? data[MARKER] : null;
  return m && typeof m === 'object' ? m : {};
}

async function claimStatus(db, orderDocId, status) {
  const ref = db.collection('orders').doc(orderDocId);
  let claimed = false;
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const marker = readMarker(snap.exists ? snap.data() : {});
      if (marker[LAST_STATUS] === status) return; // already pushed this status
      tx.update(ref, {
        [MARKER]: Object.assign({}, marker, { [LAST_STATUS]: status }),
      });
      claimed = true;
    });
  } catch (_) {
    claimed = false; // claim failed: treat as already-handled, never force a send
  }
  return claimed;
}

async function claimNewOrder(db, orderDocId) {
  const ref = db.collection('orders').doc(orderDocId);
  let claimed = false;
  try {
    await db.runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const marker = readMarker(snap.exists ? snap.data() : {});
      if (marker[NEW_ORDER_SENT]) return; // already announced
      tx.update(ref, {
        [MARKER]: Object.assign({}, marker, { [NEW_ORDER_SENT]: true }),
      });
      claimed = true;
    });
  } catch (_) {
    claimed = false;
  }
  return claimed;
}

/* ------------------------------------------------------------------ *
 * Recipients
 * ------------------------------------------------------------------ */
// Every uid that holds an admins/{uid} grant (never self-serviceable).
async function adminTokenTargets(db) {
  const adminsSnap = await db.collection('admins').get();
  const out = [];
  for (const doc of adminsSnap.docs) {
    const t = await tokensFor(db, doc.id);
    if (t.tokens.length) out.push(t);
  }
  return out;
}
/* ------------------------------------------------------------------ *
 * Handlers (called by the thin triggers)
 * ------------------------------------------------------------------ */
async function handleOrderStatus(opts) {
  const { db, send, orderDocId, status, customerId } = opts;
  if (typeof customerId !== 'string' || customerId.length === 0) {
    return { kind: KIND_ORDER_STATUS, sent: 0, skipped: 'no-customer' };
  }
  if (!CUSTOMER_NOTIFY_STATUSES.has(status)) {
    return { kind: KIND_ORDER_STATUS, sent: 0, skipped: 'status-not-notify-worthy' };
  }
  const code = opts.orderCode || orderDocId;
  const claimed = await claimStatus(db, orderDocId, status);
  if (!claimed) return { kind: KIND_ORDER_STATUS, sent: 0, skipped: 'duplicate' };
  const { tokens } = await tokensFor(db, customerId);
  if (!tokens.length) return { kind: KIND_ORDER_STATUS, code, sent: 0, skipped: 'no-tokens' };
  const title = customerTitle(code, status);
  const body = customerBody(status);
  const res = await sendToTokens(db, send, customerId, tokens, (token) =>
    messageFor(KIND_ORDER_STATUS, {
      token, title, body, orderDocId, orderCode: code, status,
    }));
  return { kind: KIND_ORDER_STATUS, code, sent: res.sent, unregistered: res.unregistered };
}

async function handleNewOrder(opts) {
  const { db, send, orderDocId } = opts;
  const code = opts.orderCode || orderDocId;
  const claimed = await claimNewOrder(db, orderDocId);
  if (!claimed) return { kind: KIND_ADMIN_NEW_ORDER, sent: 0, skipped: 'duplicate' };
  const targets = await adminTokenTargets(db);
  const title = adminTitle(code);
  let sent = 0;
  let unregistered = 0;
  for (const t of targets) {
    const res = await sendToTokens(db, send, t.uid, t.tokens, (token) =>
      messageFor(KIND_ADMIN_NEW_ORDER, {
        token, title, body: adminBody(), orderDocId, orderCode: code, status: 'New',
      }));
    sent += res.sent;
    unregistered += res.unregistered;
  }
  return { kind: KIND_ADMIN_NEW_ORDER, code, admins: targets.length, sent, unregistered };
}

/* ------------------------------------------------------------------ *
 * Thin entrypoints the triggers pass snapshots/change objects into
 * ------------------------------------------------------------------ */
async function onOrderCreated(deps, snap) {
  const data = snap.data ? snap.data() : {};
  return handleNewOrder({
    db: deps.db,
    send: deps.send,
    orderDocId: snap.id,
    orderCode: data.orderId,
  });
}

async function onOrderUpdated(deps, change) {
  const after = change.after && change.after.data ? change.after.data() : null;
  if (!after || typeof after !== 'object') {
    return { sent: 0, skipped: 'no-data' };
  }
  return handleOrderStatus({
    db: deps.db,
    send: deps.send,
    orderDocId: change.after.id,
    orderCode: after.orderId,
    status: after.status,
    customerId: after.customerId,
  });
}

module.exports = {
  CUSTOMER_NOTIFY_STATUSES,
  KIND_ORDER_STATUS,
  KIND_ADMIN_NEW_ORDER,
  MARKER,
  customerTitle,
  customerBody,
  adminTitle,
  adminBody,
  shouldSendCustomerStatus,
  shouldSendNewOrder,
  messageFor,
  normalizeTokens,
  tokensFor,
  pruneTokens,
  safeSend,
  sendToTokens,
  claimStatus,
  claimNewOrder,
  handleOrderStatus,
  handleNewOrder,
  onOrderCreated,
  onOrderUpdated,
};
