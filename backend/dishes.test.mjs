import test from 'node:test';
import assert from 'node:assert/strict';
import { sessionUpdate } from './xai.mjs';

const project = 'demo-ouichef';
const enabled = process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8085';
function token(uid) {
  const encode = v => Buffer.from(JSON.stringify(v)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ sub: uid, user_id: uid, aud: project, iss: `https://securetoken.google.com/${project}`, iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600, firebase: { sign_in_provider: 'password' } })}.`;
}
test('new cooking operations are advertised only to capable clients', () => {
  for (const enabled of [false, true]) {
    const ops = sessionUpdate({ adaptiveCooking: enabled }).session.tools[0].parameters.properties.operation.enum;
    assert.equal(ops.includes('report_amount'), enabled);
    assert.equal(ops.includes('resume_attempt'), enabled);
    assert.equal(ops.includes('take_photo'), enabled);
    assert.ok(ops.includes('complete_node'));
  }
});

test('completed dishes and images are private, bounded, replaceable and deletable', { skip: !enabled }, async () => {
  const id = 'C29C3BD3-8315-447E-8EB4-FEB2498F0774', uid = 'dish-owner';
  const doc = `http://127.0.0.1:8085/v1/projects/${project}/databases/(default)/documents/users/${uid}/completedRecipes/${id}`;
  const path = `users/${uid}/completedRecipes/${id}/dish.jpg`;
  const storage = `http://127.0.0.1:9199/v0/b/${project}.appspot.com/o`;
  const image = `${storage}/${encodeURIComponent(path)}`;
  const headers = user => user ? { Authorization: `Bearer ${token(user)}` } : {};
  const fields = { id: { stringValue: id }, recipeID: { stringValue: 'margarita' }, recipeVersion: { integerValue: 2 },
    title: { stringValue: 'My Margarita' }, chefName: { stringValue: 'Chef Margarita' }, servings: { integerValue: 1 },
    completedAt: { timestampValue: new Date().toISOString() }, adjustments: { arrayValue: { values: [] } }, photoPath: { stringValue: path } };
  async function status(url, options, expected) {
    const response = await fetch(url, options);
    assert.equal(response.status, expected, await response.text());
  }
  const patch = (user, f = fields) => ({ method: 'PATCH', headers: { ...headers(user), 'Content-Type': 'application/json' }, body: JSON.stringify({ fields: f }) });
  const upload = (user, name = path, data = Buffer.from([255,216,255,217]), type = 'image/jpeg') => {
    const boundary = 'dish-boundary';
    const body = Buffer.concat([Buffer.from(`--${boundary}\r\nContent-Type: application/json\r\n\r\n${JSON.stringify({ name, contentType: type })}\r\n--${boundary}\r\nContent-Type: ${type}\r\n\r\n`), data, Buffer.from(`\r\n--${boundary}--\r\n`)]);
    return status(`${storage}?name=${encodeURIComponent(name)}`, { method: 'POST', headers: { ...headers(user), 'X-Goog-Upload-Protocol': 'multipart', 'Content-Type': `multipart/related; boundary=${boundary}` }, body }, user === uid && name === path && data.length <= 2000000 && type === 'image/jpeg' ? 200 : 403);
  };
  await status(doc, patch(uid), 200);
  await status(doc, patch(uid), 200); // Retry is the same attempt, not a second record.
  await status(doc, { headers: headers(uid) }, 200);
  await status(doc, { headers: headers('other-user') }, 403);
  await status(doc, {}, 403);
  await status(doc, patch('other-user'), 403);
  await status(doc, patch(uid, { ...fields, photoPath: { stringValue: 'users/other-user/photo.jpg' } }), 403);
  await status(doc, patch(uid, { ...fields, isAdmin: { booleanValue: true } }), 403);
  await upload(uid);
  await upload(uid); // Replacing a photo leaves one object.
  await status(`${image}?alt=media`, { headers: headers(uid) }, 200);
  await status(`${image}?alt=media`, { headers: headers('other-user') }, 403);
  await status(`${image}?alt=media`, {}, 403);
  await upload('other-user');
  await upload(undefined);
  await upload(uid, path, Buffer.alloc(2000001));
  await upload(uid, path, Buffer.from('text'), 'text/plain');
  await upload(uid, `users/${uid}/completedRecipes/${id}/other.jpg`);
  await status(`${storage}?prefix=${encodeURIComponent(`users/${uid}/completedRecipes/`)}&delimiter=/`, { headers: headers(uid) }, 200);
  await status(image, { method: 'DELETE', headers: headers('other-user') }, 403);
  await status(image, { method: 'DELETE', headers: headers(uid) }, 204);
  await status(doc, { method: 'DELETE', headers: headers(uid) }, 200);
  await status(doc, { headers: headers(uid) }, 404);
});
