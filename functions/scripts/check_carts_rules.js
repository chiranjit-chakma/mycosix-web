#!/usr/bin/env node
// Focused Firestore-rules check for the account cart document (carts/{uid}).
//
// Run under the Firestore emulator:
//   cd functions && npm run test:rules
// (which is `firebase emulators:exec --only firestore --project demo-mycosix
// "node scripts/check_carts_rules.js"` - the emulator loads firestore.rules
// from the repo's firebase.json).
//
// Probes the changed rule: carts documents may carry a bounded `removed`
// (tombstone) list alongside items+updatedAt, owner-only, and nothing else.
// Every probe asserts the expected outcome; any mismatch fails the run.
//
// Two Firestore-emulator REST quirks are handled here:
//   1. the database segment must be URL-encoded: databases/%28default%29
//      (a literal `(default)` makes creates fail path parsing with a 400).
//   2. `Authorization: Bearer <uid>` is rejected ("invalid jwt"); the
//      emulator wants a real (unverified) JWT carrying the uid in its claims.
//
// Every write probe uses its OWN uid == documentId pair, so a denial is
// caused by exactly the condition under test (owner-only or shape), never
// by a uid mismatch.

const assert = require('node:assert/strict');

const host = process.env.FIRESTORE_EMULATOR_HOST || '127.0.0.1:8080';
const project = process.env.GCLOUD_PROJECT || 'demo-mycosix';
const base = `http://${host}/v1/projects/${project}/databases/%28default%29/documents`;

const b64 = (o) => Buffer.from(JSON.stringify(o)).toString('base64url');

function token(uid) {
  return [
    b64({ alg: 'none', typ: 'JWT' }),
    b64({
      iss: 'https://securetoken.google.com/' + project,
      aud: project,
      auth_time: 0,
      sub: uid,
      user_id: uid,
      iat: 0,
      exp: 4102444800,
      firebase: { identities: {}, sign_in_provider: 'password' },
    }),
    '',
  ].join('.');
}

let passed = 0;
const results = [];

async function call({ method, path, uid, body }) {
  const headers = { 'Content-Type': 'application/json' };
  if (uid) headers.Authorization = `Bearer ${token(uid)}`;
  const res = await fetch(`${base}/${path}`, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  return res.status;
}

async function probe(name, expected, fn) {
  const status = await fn();
  try {
    assert.equal(status, expected, `expected ${expected}, got ${status}`);
    results.push(`PASS  ${name} (${status})`);
    passed++;
  } catch (e) {
    results.push(`FAIL  ${name}: ${e.message}`);
  }
}

const str = (v) => ({ stringValue: v });
const int = (n) => ({ integerValue: String(n) });
const ts = { timestampValue: '2026-09-09T00:00:00Z' };
const items = { mapValue: { fields: { p1: int(2) } } };

function removedArray(n) {
  return {
    arrayValue: {
      values: Array.from({ length: n }, (_, i) => str(`p${i}`)),
    },
  };
}

async function main() {
  // --- READ: owner-only ---
  // A missing own cart is 404 (rules allow the read), not 403 - proving the
  // rules do not deny the owner.
  await probe('owner may read own (missing) cart', 404, () =>
    call({ method: 'GET', path: 'carts/u1', ...authOwner }),
  );
  await probe('another user cannot read the cart', 403, () =>
    call({ method: 'GET', path: 'carts/u1', ...authOther }),
  );
  await probe('anonymous cannot read the cart', 403, () =>
    call({ method: 'GET', path: 'carts/u1' }),
  );

  // --- CREATE: items + removed + updatedAt is allowed (new shape) ---
  await probe('create cart with removed tombstone list', 200, () =>
    call({
      method: 'POST',
      path: 'carts?documentId=u1',
      ...authOwner,
      body: { fields: { items, removed: removedArray(1), updatedAt: ts } },
    }),
  );
  await probe('owner reads own cart after create', 200, () =>
    call({ method: 'GET', path: 'carts/u1', ...authOwner }),
  );
  await probe('create cart without removed (legacy shape still works)', 200, () =>
    call({
      method: 'POST',
      path: 'carts?documentId=leg',
      ...authOwnerLegacy,
      body: { fields: { items, updatedAt: ts } },
    }),
  );
  await probe('create with a 100-entry tombstone list (bounded limit)', 200, () =>
    call({
      method: 'POST',
      path: 'carts?documentId=h100',
      ...authOwner100,
      body: { fields: { items, removed: removedArray(100), updatedAt: ts } },
    }),
  );
  await probe('create with a 101-entry tombstone list is refused', 403, () =>
    call({
      method: 'POST',
      path: 'carts?documentId=h101',
      ...authOwner101,
      body: { fields: { items, removed: removedArray(101), updatedAt: ts } },
    }),
  );
  await probe('create with removed as a string is refused', 403, () =>
    call({
      method: 'POST',
      path: 'carts?documentId=str1',
      ...authOwnerStr,
      body: {
        fields: { items, removed: str('p1'), updatedAt: ts },
      },
    }),
  );
  await probe('create with an extra unknown key is refused', 403, () =>
    call({
      method: 'POST',
      path: 'carts?documentId=xtra',
      ...authOwnerExtra,
      body: {
        fields: { items, removed: removedArray(0), updatedAt: ts, evil: str('x') },
      },
    }),
  );

  // --- UPDATE / DELETE: owner-only, shape still enforced ---
  await probe('owner updates own cart', 200, () =>
    call({
      method: 'PATCH',
      path: 'carts/u1?updateMask.fieldPaths=items',
      ...authOwner,
      body: { fields: { items: { mapValue: { fields: { p1: int(3) } } } } },
    }),
  );
  await probe('another user cannot update the cart', 403, () =>
    call({
      method: 'PATCH',
      path: 'carts/u1?updateMask.fieldPaths=items',
      ...authOther,
      body: { fields: { items: { mapValue: { fields: { p1: int(9) } } } } },
    }),
  );
  await probe('owner deletes own cart', 200, () =>
    call({ method: 'DELETE', path: 'carts/u1', ...authOwner }),
  );
  await probe('another user cannot delete the cart', 403, () =>
    call({ method: 'DELETE', path: 'carts/leg', ...authOther }),
  );

  console.log(results.join('\n'));
  console.log(`\n${passed}/${results.length} rules probes passed.`);
  if (passed !== results.length) process.exit(1);
}

// Every uid here is paired with a matching documentId in the probes above.
const authOwner = { uid: 'u1' };
const authOther = { uid: 'u2' };
const authOwnerLegacy = { uid: 'leg' };
const authOwner100 = { uid: 'h100' };
const authOwner101 = { uid: 'h101' };
const authOwnerStr = { uid: 'str1' };
const authOwnerExtra = { uid: 'xtra' };

main().catch((e) => {
  console.error('rules check crashed:', e);
  process.exit(2);
});
