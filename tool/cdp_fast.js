// Fast CDP smoke: navigate every route, 3s settle, capture console errors.
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const BASE = 'http://127.0.0.1:8137';
const ROUTES = ['/#/home', '/#/shop', '/#/cart', '/#/farm', '/#/journey', '/#/team', '/#/contact', '/#/privacy', '/#/terms'];
const OUT = path.join(__dirname, '_work', 'shots');
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const userData = path.join(os.tmpdir(), 'mx-cdp2-' + Date.now());
  const chrome = spawn(CHROME, [
    '--no-sandbox', '--hide-scrollbars', '--window-position=0,0',
    '--remote-debugging-port=9225', '--user-data-dir=' + userData,
    '--window-size=1440,1000', 'about:blank',
  ], { stdio: 'ignore' });
  await sleep(2500);

  const targets = await (await fetch('http://127.0.0.1:9225/json/list')).json();
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl, { maxPayload: 256 * 1024 * 1024 });
  await new Promise((res, rej) => { ws.on('open', res); ws.on('error', rej); });

  let id = 0;
  const pending = new Map();
  const errors = [];
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); return; }
    if (msg.method === 'Runtime.exceptionThrown') {
      errors.push('EXC: ' + (msg.params.exceptionDetails?.exception?.description || msg.params.exceptionDetails?.text || '').slice(0, 300));
    }
    if (msg.method === 'Log.entryAdded' && msg.params.entry.level === 'error') {
      errors.push('LOG: ' + msg.params.entry.text.slice(0, 300));
    }
  });
  const send = (m, p = {}) => new Promise((res) => { const mid = ++id; pending.set(mid, res); ws.send(JSON.stringify({ id: mid, method: m, params: p })); });

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');
  await send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });

  let fail = 0;
  for (const route of ROUTES) {
    const before = errors.length;
    await send('Page.navigate', { url: BASE + route });
    await sleep(route === '/' ? 8000 : 3500);
    const shotName = route.split('/').pop();
    const shot = await send('Page.captureScreenshot', { format: 'png' });
    if (shot.result?.data) fs.writeFileSync(path.join(OUT, shotName + '.png'), Buffer.from(shot.result.data, 'base64'));
    const newErrs = errors.slice(before);
    if (newErrs.length) {
      fail++;
      console.log(`[${route}] FAIL: ${newErrs.length}`);
      newErrs.slice(0, 4).forEach((e) => console.log('    ' + e.slice(0, 180)));
    } else {
      console.log(`[${route}] ok`);
    }
  }
  console.log(fail === 0 ? 'ALL ROUTES CLEAN' : fail + ' ROUTE(S) WITH ERRORS');
  ws.close();
  chrome.kill();
  process.exit(fail === 0 ? 0 : 2);
}
main().catch((e) => { console.error('fatal', e); process.exit(1); });
