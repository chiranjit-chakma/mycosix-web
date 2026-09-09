#!/usr/bin/env node
// Focused Firestore-rules check for the admin-managed editorial collections:
// team/{docId} and content/{docId}. The public marketing pages render these
// (live "Our Team" roster + admin-written copy), so READ is open to the world;
// every write (create/update/delete) is reserved for an admin - a uid with a
// document in admins/{uid}, decided server-side by isAdmin().
//
// Run under the Firestore emulator (same gate as check_carts_rules.js):
//   cd functions && npm run test:rules
//
// Because admins/{uid} documents are "provisioned by the project owner through
// the console or an admin SDK script - never by the app" (allow create: if
// false), the probe seeds its own admin grant through the emulator's `owner`
// bearer bypass before the admin-positive probes. Every write probe uses its
// OWN uid (== documentId where relevant) so a denial is caused by exactly the
// condition under test, never by a uid mismatch.

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
const ts = { timestampValue: '2026-09-09T00:00:00Z' };

const teamDoc = (name) => ({ fields: { name: str(name), sort: { integerValue: '1' } } });
const contentDoc = (title) => ({ fields: { title: str(title) } });

async function seedAdminGrant(uid) {
  // Emulator owner bypass: the Firestore emulator honours `Bearer owner` as a
  // full-admin credential (rules bypassed), exactly how the real owner seeds
  // admins/{uid} through the console / an admin SDK script.
  return raw('POST', `admins?documentId=${uid}`, {
    owner: true,
    body: { fields: { seededAt: ts } },
  });
}

async function main() {
  // Seed the admin grant for the positive probes. If the emulator rejects the
  // owner bypass this exits non-zero loudly - never a silent false-green.
  const seeded = await seedAdminGrant('a1');
  if (seeded !== 200) {
    console.error(
      `FATAL: could not seed admins/a1 via emulator owner bypass (status ${seeded}); ` +
        `admin-positive probes would be meaningless. Aborting.`,
    );
    process.exit(2);
  }
  console.log('NOTE  seeded admins/a1 through emulator owner bypass (rules bypassed)');

  // --- READ: public marketing pages read team + content with NO sign-in ---
  await probe('anonymous may read a missing team doc (404, not 403)', 404, () =>
    raw('GET', 'team/missing'),
  );
  await probe('signed-in non-admin may read a missing content doc', 404, () =>
    raw('GET', 'content/c-missing', { uid: 'n1' }),
  );

  // --- WRITE: only an admin (admins/{uid} exists) may create/update/delete ---
  await probe('anonymous cannot create a team doc', 403, () =>
    raw('POST', 'team?documentId=t-anon', { body: teamDoc('Anon') }),
  );
  await probe('non-admin cannot create a team doc', 403, () =>
    raw('POST', 'team?documentId=t-n1', { uid: 'n1', body: teamDoc('N1') }),
  );
  await probe('admin may create a team doc', 200, () =>
    raw('POST', 'team?documentId=t1', { uid: 'a1', body: teamDoc('Chandan') }),
  );
  await probe('admin may create a content doc', 200, () =>
    raw('POST', 'content?documentId=c1', { uid: 'a1', body: contentDoc('Edited title') }),
  );

  // --- READ of the now-existing docs stays open to the world ---
  await probe('anonymous may read the stored team doc', 200, () =>
    raw('GET', 'team/t1'),
  );
  await probe('anonymous may read the stored content doc', 200, () =>
    raw('GET', 'content/c1'),
  );
  await probe('signed-in non-admin may read the stored team doc', 200, () =>
    raw('GET', 'team/t1', { uid: 'n1' }),
  );

  // --- UPDATE / DELETE ---
  await probe('admin may update a team doc', 200, () =>
    raw('PATCH', 'team/t1?updateMask.fieldPaths=role', {
      uid: 'a1',
      body: { fields: { role: str('Co-founder') } },
    }),
  );
  await probe('non-admin cannot update a team doc', 403, () =>
    raw('PATCH', 'team/t1?updateMask.fieldPaths=role', {
      uid: 'n1',
      body: { fields: { role: str('Hacker') } },
    }),
  );
  await probe('anonymous cannot delete a team doc', 403, () =>
    raw('DELETE', 'team/t1'),
  );
  await probe('non-admin cannot delete a content doc', 403, () =>
    raw('DELETE', 'content/c1', { uid: 'n1' }),
  );
  await probe('admin may delete a content doc', 200, () =>
    raw('DELETE', 'content/c1', { uid: 'a1' }),
  );
  await probe('anonymous read of team doc survives the denied attempts', 200, () =>
    raw('GET', 'team/t1'),
  );

  // --- No self-grant: admins/{uid} is provisioned server-side, never by app ---
  await probe('anonymous cannot self-grant admin', 403, () =>
    raw('POST', 'admins?documentId=anon-x', { body: {} }),
  );
  await probe('non-admin cannot self-grant admin', 403, () =>
    raw('POST', 'admins?documentId=n1', { uid: 'n1', body: {} }),
  );

  console.log(results.join('\n'));
  console.log(`\n${passed}/${results.length} editorial rules probes passed.`);
  if (passed !== results.length) process.exit(1);
}

main().catch((e) => {
  console.error('editorial rules check crashed:', e);
  process.exit(2);
});
