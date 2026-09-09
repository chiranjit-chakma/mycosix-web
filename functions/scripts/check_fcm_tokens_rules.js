#!/usr/bin/env node
// Focused Firestore-rules check for fcmTokens/{uid}: the Cloud Functions
// notification backend delivers pushes to the tokens stored here, and the
// browser registers/refreshes its OWN tokens through this path. So read and
// every write are reserved for the owner of the uid (decided server-side by
// request.auth.uid == uid) - no other signed-in user, and nobody anonymous,
// may ever read or overwrite another person's token list. Deleting a stale
// token (an unregistered device) is done by the backend's Admin SDK, which
// bypasses rules, or by the owner themselves.
//
// Run under the Firestore emulator (same gate as the other checks):
//   cd functions && npm run test:rules
//
// Every write probe uses its OWN uid (== documentId) so a denial is caused by
// exactly the condition under test, never by a uid mismatch.

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

async function raw(method, path, { uid, body } = {}) {
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
    const ok = expected.includes ? expected.includes(status) : status === expected;
    if (!ok) throw new Error(`expected ${expected}, got ${status}`);
    results.push(`PASS  ${name} (${status})`);
    passed++;
  } catch (e) {
    results.push(`FAIL  ${name}: ${e.message}`);
  }
}

const str = (v) => ({ stringValue: v });
const tokensDoc = (tok) => ({
  fields: { tokens: { arrayValue: { values: [{ stringValue: tok }] } } },
});

async function main() {
  // --- READ: nobody can read another user's tokens ---
  await probe('anonymous may not read fcmTokens', 403, () => raw('GET', 'fcmTokens/f1'));
  await probe('other signed-in user may not read fcmTokens', 403, () =>
    raw('GET', 'fcmTokens/f1', { uid: 'n2' }),
  );

  // --- CREATE: only the owner may create their own token document ---
  await probe('anonymous may not create a token doc', 403, () =>
    raw('POST', 'fcmTokens?documentId=anon', { body: tokensDoc('t-anon') }),
  );
  await probe('a user cannot create another user token doc', 403, () =>
    raw('POST', 'fcmTokens?documentId=f1', { uid: 'n2', body: tokensDoc('t-n2') }),
  );
  await probe('the owner may create their own token doc', 200, () =>
    raw('POST', 'fcmTokens?documentId=f1', { uid: 'f1', body: tokensDoc('t-f1') }),
  );

  // --- READ of own doc (after creation) stays owner-only ---
  await probe('the owner may read their own token doc', 200, () =>
    raw('GET', 'fcmTokens/f1', { uid: 'f1' }),
  );
  await probe('another user still cannot read it (denied)', 403, () =>
    raw('GET', 'fcmTokens/f1', { uid: 'n2' }),
  );

  // --- UPDATE: only the owner may change their own token list ---
  await probe('another user cannot overwrite a token doc', 403, () =>
    raw('PATCH', 'fcmTokens/f1?updateMask.fieldPaths=tokens', {
      uid: 'n2',
      body: { fields: { tokens: { arrayValue: { values: [{ stringValue: 'evil' }] } } } },
    }),
  );
  await probe('the owner may append a token to their own doc', 200, () =>
    raw('PATCH', 'fcmTokens/f1?updateMask.fieldPaths=tokens', {
      uid: 'f1',
      body: { fields: { tokens: { arrayValue: { values: [{ stringValue: 't-f1b' }] } } } },
    }),
  );

  // --- DELETE: only the owner may delete their own token doc ---
  await probe('another user cannot delete a token doc', 403, () =>
    raw('DELETE', 'fcmTokens/f1', { uid: 'n2' }),
  );
  await probe('anonymous cannot delete a token doc', 403, () => raw('DELETE', 'fcmTokens/f1'));
  await probe('the owner may delete their own token doc', 200, () =>
    raw('DELETE', 'fcmTokens/f1', { uid: 'f1' }),
  );

  // --- No cross-user data left behind: another user never got a 200 read ---
  await probe('owner read of a now-deleted doc is a 404 (cleanup)', 404, () =>
    raw('GET', 'fcmTokens/f1', { uid: 'f1' }),
  );

  console.log(results.join('\n'));
  console.log(`\n${passed}/${results.length} fcmTokens rules probes passed.`);
  if (passed !== results.length) process.exit(1);
}

main().catch((e) => {
  console.error('fcmTokens rules check crashed:', e);
  process.exit(2);
});
