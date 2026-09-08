// Hide the splash once Flutter takes over the page (externalized from
// index.html so the site can ship a strict Content-Security-Policy).
window.addEventListener('flutter-first-frame', function () {
  var el = document.getElementById('mx-boot');
  if (el) { el.classList.add('done'); }
  setTimeout(function () { if (el && el.parentNode) el.parentNode.removeChild(el); }, 600);
});
