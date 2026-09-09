/**
 * MYCOSIX push-notification triggers (thin Firebase wiring only).
 *
 * Deployed once the project moves to the paid (Blaze) plan - the owner's
 * cost decision. Until then nothing here runs and the live site is unchanged:
 * this file only becomes live when `firebase deploy --only functions` is run.
 *
 * Two Firestore events map onto the tested core in notify_core.js:
 *   orders/{orderId} onCreate  -> admin "new order" push
 *   orders/{orderId} onUpdate  -> owning customer's status push
 * Every send is guarded by the core's claim markers, so a Firestore retry can
 * never double-notify. deps() shares the single lazy Admin SDK initialisation
 * with index.js.
 */

'use strict';

const functions = require('firebase-functions');
const admin = require('firebase-admin');
const notify = require('./notify_core');

let messaging;

function getMessaging() {
  if (!messaging) {
    if (!admin.apps.length) admin.initializeApp();
    messaging = admin.messaging();
  }
  return messaging;
}

// The send contract notify_core expects: resolves (never rejects on an FCM
// outcome) to { ok: true } or { ok: false, unregistered: true } when FCM says
// the registration token is no longer valid - which the core then prunes.
async function sendOne(msg) {
  try {
    await getMessaging().send(msg);
    return { ok: true };
  } catch (err) {
    const code = (err && (err.code || (err.errorInfo && err.errorInfo.code))) || '';
    if (
      code === 'messaging/registration-token-not-registered' ||
      code === 'messaging/invalid-registration-token'
    ) {
      return { ok: false, unregistered: true };
    }
    functions.logger.warn('push send failed (will retry on next event)', {
      code,
      message: err && err.message,
    });
    return { ok: false, unregistered: false };
  }
}

function deps() {
  if (!admin.apps.length) admin.initializeApp();
  return { db: admin.firestore(), send: sendOne };
}

// A trigger must never reject: log and finish so Firestore does not retry a
// doomed event forever. The claim markers make a manual retry safe.
const safe = (fn) => async (...args) => {
  try {
    return await fn(...args);
  } catch (err) {
    functions.logger.error('notification trigger failed', err);
    return null;
  }
};

exports.notifyOrderStatus = functions.firestore
  .document('orders/{orderId}')
  .onUpdate(safe((change) => notify.onOrderUpdated(deps(), change)));

exports.notifyOrderNew = functions.firestore
  .document('orders/{orderId}')
  .onCreate(safe((snap) => notify.onOrderCreated(deps(), snap)));
