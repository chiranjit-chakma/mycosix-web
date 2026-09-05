// CDP smoke test: loads each route in headless Chrome, waits for first
// Flutter frame, captures console errors and takes a screenshot.
const { spawn } = require('child_process');
const fs = require('fs');
const os = require('os');
const path = require('path');
const WebSocket = require('ws');

const CHROME = 'C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe';
const BASE = 'http://127.0.0.1:8137';
const ROUTES = ['/', '/shop', '/cart', '/farm', '/journey', '/team', '/contact', '/privacy', '/terms'];
const OUT = path.join(__dirname, '_work', 'shots');
fs.mkdirSync(OUT, { recursive: true });

function sleep(ms) { return new Promise((r) => setTimeout(r, ms)); }

async function cdpPage(wsUrl) {
  const ws = new WebSocket(wsUrl, { maxPayload: 128 * 1024 * 1024 });
  await new Promise((res, rej) => { ws.on('open', res); ws.on('error', rej); });
  let id = 0;
  const pending = new Map();
  const events = [];
  ws.on('message', (raw) => {
    const msg = JSON.parse(raw.toString());
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
    if (msg.method === 'Runtime.consoleAPICalled') {
      events.push({ type: 'console', text: (msg.params.args || []).map((a) => a.value ?? a.description ?? '').join(' ') });
    }
    if (msg.method === 'Runtime.exceptionThrown') {
      events.push({ type: 'exception', text: msg.params.exceptionDetails?.text || 'exception' });
    }
    if (msg.method === 'Log.entryAdded') {
      const l = msg.params.entry;
      if (l.level === 'error') events.push({ type: 'log', text: l.text });
    }
  });
  function send(method, params = {}) {
    return new Promise((res) => {
      const mid = ++id;
      pending.set(mid, res);
      ws.send(JSON.stringify({ id: mid, method, params }));
    });
  }
  return { ws, send, events };
}

(async () => {
  const userData = path.join(os.tmpdir(), 'mx-cdp-' + Date.now());
  const chrome = spawn(CHROME, [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
    '--remote-debugging-port=9224', '--user-data-dir=' + userData,
    '--window-size=1440,1000', 'about:blank',
  ], { stdio: 'ignore' });
  await sleep(2500);

  const targets = await (await fetch('http://127.0.0.1:9224/json/list')).json();
  const page = targets.find((t) => t.type === 'page');
  if (!page) { console.error('no page target'); process.exit(1); }
  const cdp = await cdpPage(page.webSocketDebuggerUrl);
  await cdp.send('Runtime.enable');
  await cdp.send('Log.enable');
  await cdp.send('Page.enable');
  await cdp.send('Emulation.setDeviceMetricsOverride', { width: 1440, height: 1000, deviceScaleFactor: 1, mobile: false });

  let failures = 0;
  for (const route of ROUTES) {
    cdp.events.length = 0;
    await cdp.send('Page.navigate', { url: BASE + route + '/#/' });
    // Allow Flutter to boot and settle.
    await sleep(route === '/' ? 14000 : 6000);
    const shot = path.join(OUT, (route === '/' ? 'home' : route.slice(1)) + '.png');
    const res = await cdp.send('Page.captureScreenshot', { format: 'png' });
    if (res.result && res.result.data) fs.writeFileSync(shot, Buffer.from(res.result.data, 'base64'));
    const errs = cdp.events.filter((e) => e.type !== 'console' || /error|exception|failed/i.test(e.text));
    if (errs.length) {
      failures++;
      console.log(`[${route}] ERRORS:`);
      for (const e of errs.slice(0, 5)) console.log('   ', e.type, e.text.slice(0, 220));
    } else {
      console.log(`[${route}] ok (${fs.existsSync(shot) ? 'shot saved' : 'no shot'})`);
    }
  }
  console.log(failures === 0 ? 'ALL ROUTES CLEAN' : `${failures} ROUTE(S) WITH ERRORS`);
  cdp.ws.close();
  chrome.kill();
  process.exit(failures === 0 ? 0 : 2);
})();
