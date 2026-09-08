// MYCOSIX always-fresh (externalized from index.html so the site can ship a
// strict Content-Security-Policy: script-src 'self'): never let a stale
// service-worker copy mask a deploy. Normal Chrome cached the old version
// after updates (incognito never did, because it has no service worker).
// Unregister any existing worker, block new registrations, and drop the old
// worker with a one-time reload.
(function () {
  try {
    if ('serviceWorker' in navigator) {
      var sw = navigator.serviceWorker;
      var reloadOnce = function () {
        try {
          if (window.sessionStorage.getItem('mx-always-fresh') === '1') return;
          window.sessionStorage.setItem('mx-always-fresh', '1');
          window.location.reload();
        } catch (err) {}
      };
      var drop = sw.getRegistrations().then(function (regs) {
        for (var i = 0; i < regs.length; i++) {
          try { regs[i].unregister(); } catch (err) {}
        }
      });
      if (sw.controller) {
        // A worker controls this page and may serve stale assets; drop it,
        // then reload so this very visit already shows the current version.
        drop.then(function () { reloadOnce(); }).catch(function () {});
      }
      // Block Flutter's generated bootstrap from installing a new worker.
      sw.register = function () {
        return Promise.reject(new Error('service workers disabled by MYCOSIX always-fresh policy'));
      };
    }
  } catch (err) {}
})();
