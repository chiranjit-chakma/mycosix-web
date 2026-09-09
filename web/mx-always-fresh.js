// MYCOSIX always-fresh (externalized from index.html so the site can ship a
// strict Content-Security-Policy: script-src 'self'): never let a stale
// service-worker copy mask a deploy. Normal Chrome cached the old version
// after updates (incognito never did, because it has no service worker).
// Unregister any stale worker, block new registrations of caching workers,
// and drop the old worker with a one-time reload.
//
// ONE exemption: the push-messaging worker (firebase-messaging-sw.js). It has
// NO fetch handler and caches nothing, so it can never serve stale assets; it
// only exists to receive push events and open the app on tap. It is kept and
// its registration is allowed, otherwise web push cannot work. The Flutter
// bootstrap's caching worker stays blocked as before.
(function () {
  try {
    if ('serviceWorker' in navigator) {
      var sw = navigator.serviceWorker;
      var MESSAGING = 'firebase-messaging-sw.js';
      var isMessaging = function (reg) {
        try {
          var s = (reg && (reg.active || reg.installing || reg.waiting)) || null;
          if (!s || !s.scriptURL) return false;
          return (s.scriptURL.split('/').pop() || '') === MESSAGING;
        } catch (err) { return false; }
      };
      var reloadOnce = function () {
        try {
          if (window.sessionStorage.getItem('mx-always-fresh') === '1') return;
          window.sessionStorage.setItem('mx-always-fresh', '1');
          window.location.reload();
        } catch (err) {}
      };
      var drop = sw.getRegistrations().then(function (regs) {
        for (var i = 0; i < regs.length; i++) {
          if (isMessaging(regs[i])) continue; // push worker: never stale-serving
          try { regs[i].unregister(); } catch (err) {}
        }
      });
      if (sw.controller && !isMessaging({ active: sw.controller })) {
        // A caching worker controls this page and may serve stale assets; drop
        // it, then reload so this very visit already shows the current version.
        drop.then(function () { reloadOnce(); }).catch(function () {});
      }
      var origRegister = sw.register.bind(sw);
      // Allow only the push worker; block Flutter's generated bootstrap worker
      // (whose cache masks deploys). A registration at the same scope as a
      // messaging worker would replace it and silently kill push, so this guard
      // is load-bearing, not cosmetic.
      sw.register = function (url) {
        var name = String(url).split('/').pop() || '';
        if (name === MESSAGING) {
          return origRegister.apply(null, arguments);
        }
        return Promise.reject(new Error('caching service workers disabled by MYCOSIX always-fresh policy'));
      };
    }
  } catch (err) {}
})();
