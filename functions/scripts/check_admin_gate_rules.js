#!/usr/bin/env node
// Focused Firestore-rules check for the server-side admin gate:
//   secrets/{secretId}  - owner-set admin access code, readable by NO client
//   admins/{uid}        - grants created ONLY by submitting that code
//
// This is the restored secret-code security system. The security boundary is
// entirely in the rules engine: a signed-in user creates their own admins grant
// only when the write carries exactly one field - a non-empty string `code` -
// equal to the value of secrets/adminGate, a document no client can read
// (rules `get()` it; a missing secret fails the get() and denies everything).
// So a customer who discovers the admin URL, fabricates requests, or tampers
// with the payload is still denied unless they know the owner-set code. Once
// the grant exists the app gate opens with no further code; grants are revoked
// only by the owner (console / Admin SDK), because update/delete stay denied.
//
// Run under the Firestore emulator (same gate as the other checks):
//   cd functions && npm run test:rules
//
// NOTE ON THE CODE STRING BELOW: it is a TEST FIXTURE created by this probe on
// a throwaway emulator database. It is NOT the real admin code, which the owner
// sets in production through Admin -> Settings and which lives only in
// secrets/adminGate on the live project. Never treat this literal as real.
//
// The admin used for secret writes is seeded through the emulator `owner`
// bypass (how the real owner grants through the console / an admin SDK), with
// a uid unique to this script so a fresh `emulators:exec` never collides with
// the other checks. Every self-grant probe targets its OWN documentId.

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

async function raw(method, path, { uid, body, owner } = {}) {
  const headers = { 'Content-Type': 'application/json' };
  if (owner) headers.Authorization = 'Bearer owner';
  else if (uid) headers.Authorization = `Bearer ${token(uid)}`;
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

// The test-fixture code (see NOTE above). Real production code is owner-set.
const CODE = 'owner-gate-test-code';

async function seedAdmin(uid) {
  // Emulator owner bypass: admins/{uid} provisioned server-side, exactly how
  // the real owner grants through the console / an admin SDK script.
  return raw('POST', `admins?documentId=${uid}`, {
    owner: true,
    body: { fields: { seededAt: { timestampValue: '2026-09-09T00:00:00Z' } } },
  });
}

async function main() {
  // The secret-code gate needs one administrator to own the code document.
  const seeded = await seedAdmin('g1');
  if (seeded !== 200) {
    console.error(`Could not seed admin grant for g1 (got ${seeded}) - aborting.`);
    process.exit(2);
  }

  // --- secrets/adminGate: READABLE BY NO CLIENT, not even the admin ---
  await probe('anonymous may not read secrets/adminGate', 403, () =>
    raw('GET', 'secrets/adminGate'),
  );
  await probe('signed-in non-admin may not read secrets/adminGate', 403, () =>
    raw('GET', 'secrets/adminGate', { uid: 'n1' }),
  );
  await probe('an administrator may not read secrets/adminGate', 403, () =>
    raw('GET', 'secrets/adminGate', { uid: 'g1' }),
  );

  // --- secrets/adminGate: writes are admin-only and id-bound ---
  await probe('anonymous may not create the secret', 403, () =>
    raw('POST', 'secrets?documentId=adminGate', { body: { fields: { code: str(CODE) } } }),
  );
  await probe('non-admin may not create the secret', 403, () =>
    raw('POST', 'secrets?documentId=adminGate', {
      uid: 'n1', body: { fields: { code: str(CODE) } },
    }),
  );
  await probe('admin cannot create a different secret doc', 403, () =>
    raw('POST', 'secrets?documentId=other', {
      uid: 'g1', body: { fields: { code: str(CODE) } },
    }),
  );
  await probe('an administrator may set the adminGate code', 200, () =>
    raw('POST', 'secrets?documentId=adminGate', {
      uid: 'g1', body: { fields: { code: str(CODE) } },
    }),
  );
  await probe('non-admin may not rotate the secret', 403, () =>
    raw('PATCH', 'secrets/adminGate?updateMask.fieldPaths=code', {
      uid: 'n1', body: { fields: { code: str('x') } },
    }),
  );
  await probe('an administrator may rotate the secret', 200, () =>
    raw('PATCH', 'secrets/adminGate?updateMask.fieldPaths=code', {
      uid: 'g1', body: { fields: { code: str('owner-gate-test-code-2') } },
    }),
  );
  await probe('non-admin may not delete the secret', 403, () =>
    raw('DELETE', 'secrets/adminGate', { uid: 'n1' }),
  );
  await probe('an administrator may delete the secret', 200, () =>
    raw('DELETE', 'secrets/adminGate', { uid: 'g1' }),
  );

  // --- After deletion the gate fails closed (get() on a missing secret) ---
  await probe('self-grant with the old code after deletion is denied', 403, () =>
    raw('POST', 'admins?documentId=n-early', {
      uid: 'n-early', body: { fields: { code: str('owner-gate-test-code-2') } },
    }),
  );

  // Re-create the secret for the grant probes below.
  await probe('admin re-sets the code for the grant probes', 200, () =>
    raw('POST', 'secrets?documentId=adminGate', {
      uid: 'g1', body: { fields: { code: str(CODE) } },
    }),
  );

  // --- admins/{uid}: a grant requires the exact code, nothing else ---
  await probe('anonymous cannot self-grant admin', 403, () =>
    raw('POST', 'admins?documentId=anon-x', { body: { fields: { code: str(CODE) } } }),
  );
  await probe('empty self-grant body is denied', 403, () =>
    raw('POST', 'admins?documentId=n-empty', { uid: 'n-empty', body: {} }),
  );
  await probe('self-grant with a wrong code is denied', 403, () =>
    raw('POST', 'admins?documentId=n-wrong', {
      uid: 'n-wrong', body: { fields: { code: str('not-the-code') } },
    }),
  );
  await probe('self-grant with a non-string code is denied', 403, () =>
    raw('POST', 'admins?documentId=n-num', {
      uid: 'n-num', body: { fields: { code: { integerValue: '7' } } },
    }),
  );
  await probe('self-grant carrying an extra field is denied', 403, () =>
    raw('POST', 'admins?documentId=n-extra', {
      uid: 'n-extra', body: { fields: { code: str(CODE), name: str('sneaky') } },
    }),
  );
  await probe('correct code for someone elses doc is denied', 403, () =>
    raw('POST', 'admins?documentId=target-victim', {
      uid: 'n-other', body: { fields: { code: str(CODE) } },
    }),
  );
  await probe('correct code on your own doc grants admin', 200, () =>
    raw('POST', 'admins?documentId=n1', {
      uid: 'n1', body: { fields: { code: str(CODE) } },
    }),
  );
  await probe('a second admin can be granted with the same code', 200, () =>
    raw('POST', 'admins?documentId=n2', {
      uid: 'n2', body: { fields: { code: str(CODE) } },
    }),
  );

  // --- admins/{uid}: read only your own grant; mutate never by client ---
  await probe('anonymous may not read any grant', 403, () => raw('GET', 'admins/g1'));
  await probe('an admin may not read another admin grant', 403, () =>
    raw('GET', 'admins/g1', { uid: 'n1' }),
  );
  await probe('a user may read their own grant (the app gate opens)', 200, () =>
    raw('GET', 'admins/n1', { uid: 'n1' }),
  );
  await probe('a non-granted user reading their own path sees 404, not a grant', 404, () =>
    raw('GET', 'admins/nobody-yet', { uid: 'nobody-yet' }),
  );
  await probe('an admin may not update their own grant', 403, () =>
    raw('PATCH', 'admins/n1?updateMask.fieldPaths=code', {
      uid: 'n1', body: { fields: { code: str('self-edit') } },
    }),
  );
  await probe('an admin may not delete their own grant', 403, () =>
    raw('DELETE', 'admins/n1', { uid: 'n1' }),
  );

  console.log(results.join('\n'));
  console.log(`\n${passed}/${results.length} admin-gate rules probes passed.`);
  if (passed !== results.length) process.exit(1);
}

main().catch((e) => {
  console.error('admin-gate rules check crashed:', e);
  process.exit(2);
});
