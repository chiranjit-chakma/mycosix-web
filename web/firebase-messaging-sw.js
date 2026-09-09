/* MYCOSIX push-messaging service worker.
 *
 * Registered lazily by the app the moment a signed-in user grants permission
 * and the owner has set the web-push (VAPID) key (see lib/state/fcm_registration_keeper.dart).
 * Until then this file is inert - never installed, no effect on the site.
 *
 * It imports the Firebase messaging SW SDK ONLY for lifecycle maintenance
 * (browser-side push-subscription rotation -> token refresh -> page). Display
 * and click routing are implemented below instead, so every notification is
 * deterministic: exactly one per event, with an icon and a data payload that
 * routes a tap to the right page.
 *
 * Security notes:
 *  - This file carries only the PUBLIC web config, identical to the values
 *    already shipped to every browser in firebase_options.dart. No secret of
 *    any kind lives here.
 *  - Tap destinations are derived from the message's own data. They are NOT
 *    authorization: the Admin page independently re-checks the admins/{uid}
 *    grant, and My Orders lists only the signed-in customer's own orders
 *    (both enforced by Firestore security rules), so a forged or stale payload
 *    can never surface another account's order.
 */

importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyBvqscwzhutRNOuetbOWoPreO7ftRuL9L4',
  authDomain: 'mycosix.firebaseapp.com',
  projectId: 'mycosix',
  storageBucket: 'mycosix.firebasestorage.app',
  messagingSenderId: '578755322711',
  appId: '1:578755322711:web:8c5e27f0a3399549da9412'
});

// Where a tapped notification should take the user. Must mirror the app router
// (lib/router/app_router.dart + lib/pages/profile/my_orders_page.dart):
// customers land on their own orders with the highlighted order; admins land
// on the gate, which re-checks the admin grant.
function mxRouteFor(kind, docId) {
  if (kind === 'admin-new-order') return '/admin';
  if (kind === 'order-status') {
    return docId ? '/my-orders/' + encodeURIComponent(docId) : '/my-orders';
  }
  return '/';
}

function mxFallbackTitle(kind, orderCode, status) {
  if (kind === 'admin-new-order') return 'New order ' + (orderCode || '');
  if (kind === 'order-status') {
    var c = orderCode || '';
    return c || status ? 'Order ' + c + (status ? ' ' + status : '') : 'MYCOSIX order';
  }
  return 'MYCOSIX';
}

var mxIcon = new URL('icons/Icon-192.png', self.location.href).href;

// ---- Incoming push ----------------------------------------------------------
// Runs before the SDK registers its own push listener (this file listens first,
// then firebase.messaging() below attaches the SDK's), so for a MYCOSIX message
// it takes over: no SDK auto-show, no window post. When a tab is VISIBLE the
// in-app banner already covers the event through the Firestore watchers, so no
// system notification is shown; when nothing is on screen (app closed or
// backgrounded) a single notification is shown from the backend's title/body.
self.addEventListener('push', function (event) {
  var msg = null;
  try { msg = event.data ? event.data.json() : null; } catch (err) {}
  if (!msg) return;
  var data = (msg.data) || {};
  var kind = typeof data.mxKind === 'string' ? data.mxKind : '';
  var orderDocId = typeof data.orderDocId === 'string' ? data.orderDocId : '';
  if (!kind) return; // not a MYCOSIX push: leave the SDK's default handling in place

  event.stopImmediatePropagation();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (windows) {
        for (var i = 0; i < windows.length; i++) {
          if (windows[i].visibilityState === 'visible') return null; // app on screen
        }
        var ntf = msg.notification || {};
        var title = ntf.title || mxFallbackTitle(kind, data.orderCode || '', data.status || '');
        var body = ntf.body || '';
        return self.registration.showNotification(title, {
          body: body,
          icon: mxIcon,
          badge: mxIcon,
          data: {
            mxKind: kind,
            orderDocId: orderDocId,
            orderCode: data.orderCode || orderDocId,
            status: data.status || ''
          },
          tag: 'mx-' + kind + ':' + (orderDocId || 'noid'),
          renotify: false
        });
      })
  );
});

// ---- Tap on a notification --------------------------------------------------
// Also registered before the SDK's own click listener, so this handles the tap
// and stops the SDK from additionally opening the app root. Focuses the app if
// it is already open, otherwise opens it - always on the routed page.
self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  event.stopImmediatePropagation();
  var d = event.notification.data || {};
  var url = new URL(mxRouteFor(d.mxKind, d.orderDocId), self.location.origin).href;
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true })
      .then(function (windows) {
        var origin = self.location.origin;
        for (var i = 0; i < windows.length; i++) {
          var w = windows[i];
          try {
            if (new URL(w.url).origin !== origin) continue;
            return w.focus().then(function () {
              // Same-origin window clients can be navigated to the route; if the
              // browser refuses (uncontrolled tab), fall through to openWindow.
              return w.navigate(url).catch(function () {
                return self.clients.openWindow(url);
              });
            });
          } catch (err) {}
        }
        return self.clients.openWindow(url);
      })
  );
});

// ---- Firebase messaging lifecycle ------------------------------------------
// Instantiating the compat messaging controller in the worker makes the SDK
// handle browser push-subscription rotation (pushsubscriptionchange), which
// refreshes the registration and notifies the page so its stored token stays
// valid. Its own push/notificationclick listeners attach AFTER the two above,
// which already stop propagation for MYCOSIX messages.
firebase.messaging();
