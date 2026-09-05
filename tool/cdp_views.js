// Responsive CDP smoke: renders key routes at phone/tablet/desktop sizes,
// captures console errors and screenshots for layout inspection.
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const BASE = 'http://127.0.0.1:8137';
const VIEWPORTS = [
  { name: 'phone', width: 390, height: 844 },
];
const ROUTES = ['/#/home', '/#/shop', '/#/product', '/#/cart', '/#/checkout', '/#/farm', '/#/journey', '/#/team', '/#/contact', '/#/privacy', '/#/terms'];
const OUT = path.join(__dirname, '_work', 'views');
fs.mkdirSync(OUT, { recursive: true });
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  const userData = path.join(os.tmpdir(), 'mx-cdp3-' + Date.now());
  const chrome = spawn(CHROME, [
    '--no-sandbox', '--hide-scrollbars',
    '--window-position=0,0',
    '--remote-debugging-port=9226', '--user-data-dir=' + userData,
    '--window-size=420,900', 'about:blank',
  ], { stdio: 'ignore' });
  await sleep(2500);

  const targets = await (await fetch('http://127.0.0.1:9226/json/list')).json();
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
      errors.push('EXC: ' + (msg.params.exceptionDetails?.exception?.description || msg.params.exceptionDetails?.text || '').slice(0, 250));
    }
    if (msg.method === 'Log.entryAdded' && msg.params.entry.level === 'error') {
      errors.push('LOG: ' + msg.params.entry.text.slice(0, 250));
    }
  });
  const send = (m, p = {}) => new Promise((res) => { const mid = ++id; pending.set(mid, res); ws.send(JSON.stringify({ id: mid, method: m, params: p })); });

  await send('Runtime.enable');
  await send('Log.enable');
  await send('Page.enable');

  let fail = 0;
  for (const vp of VIEWPORTS) {
    await send('Emulation.setDeviceMetricsOverride', { width: vp.width, height: vp.height, deviceScaleFactor: 1, mobile: vp.name === 'phone' });
    for (const route of ROUTES) {
      const before = errors.length;
      await send('Page.navigate', { url: BASE + route });
      await sleep(route === '/#/home' || route === '/#/product' ? 7000 : 3500);
      const shot = await send('Page.captureScreenshot', { format: 'png' });
      const name = (route.split('/#/')[1] || 'home') + '-' + vp.name;
      if (shot.result?.data) fs.writeFileSync(path.join(OUT, name + '.png'), Buffer.from(shot.result.data, 'base64'));
      const newErrs = errors.slice(before);
      if (newErrs.length) {
        fail++;
        console.log(`[${name}] FAIL: ${newErrs.length}`);
        newErrs.slice(0, 3).forEach((e) => console.log('    ' + e.slice(0, 160)));
      } else {
        console.log(`[${name}] ok`);
      }
    }
  }
  console.log(fail === 0 ? 'ALL VIEWPORTS CLEAN' : fail + ' FAILURES');
  ws.close();
  chrome.kill();
  process.exit(fail === 0 ? 0 : 2);
}
main().catch((e) => { console.error('fatal', e); process.exit(1); });
