import test from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { once } from 'node:events';
import { claimVoiceAccess, handleAccountRequest } from './accounts.mjs';

test('only the holder of both verified identities can transfer development access once', async () => {
  const records = new Map([['voiceTesters/guest', { enabled: true }]]);
  const claims = {
    guest: { uid: 'guest', firebase: { sign_in_provider: 'anonymous', identities: {} } },
    alice: { uid: 'alice', firebase: { sign_in_provider: 'password', identities: { email: ['alice@example.com'] } } },
    bob: { uid: 'bob', firebase: { sign_in_provider: 'google.com', identities: { 'google.com': ['google-id'] } } }
  };
  const services = {
    auth: { verifyIdToken: async token => { if (!claims[token]) throw Error('Invalid signature'); return claims[token]; } },
    db: { doc: path => path, runTransaction: async action => {
      const writes = [];
      const result = await action({
        get: async path => ({ exists: records.has(path), data: () => records.get(path) }),
        set: (path, data) => writes.push(() => records.set(path, { ...records.get(path), ...data })),
        update: (path, data) => writes.push(() => records.set(path, { ...records.get(path), ...data })),
        create: (path, data) => writes.push(() => { assert(!records.has(path)); records.set(path, data); })
      });
      writes.forEach(write => write()); return result;
    } }
  };
  for (const [current, legacy] of [['forged', 'guest'], ['alice', 'forged'], ['guest', 'guest'], ['alice', 'bob']]) {
    await assert.rejects(claimVoiceAccess(services, current, legacy));
    assert.equal(records.size, 1);
  }
  assert.deepEqual(await claimVoiceAccess(services, 'alice', 'guest'), { migrated: true });
  assert.equal(records.get('voiceTesters/guest').enabled, false);
  assert.equal(records.get('voiceTesters/alice').enabled, true);
  assert.deepEqual(await claimVoiceAccess(services, 'alice', 'guest'), { migrated: true });
  await assert.rejects(claimVoiceAccess(services, 'bob', 'guest'));
  assert.equal(records.has('voiceTesters/bob'), false);
  records.clear(); records.set('voiceTesters/guest', { enabled: false });
  assert.deepEqual(await claimVoiceAccess(services, 'alice', 'guest'), { migrated: false });
  assert.equal(records.size, 1);
  records.set('voiceTesters/guest', { enabled: true });
  records.set('voiceTesters/alice', { enabled: false });
  await assert.rejects(claimVoiceAccess(services, 'alice', 'guest'), /disabled/);
  assert.equal(records.get('voiceTesters/alice').enabled, false);
});

test('account endpoint rejects unauthenticated and oversized requests without exposing tokens', async t => {
  const server = createServer((req, res) => void handleAccountRequest(req, res, {
    auth: { verifyIdToken: async () => { throw Error('secret-token'); } }
  }));
  server.listen(0, '127.0.0.1'); await once(server, 'listening');
  t.after(() => { server.closeAllConnections(); server.close(); });
  const url = `http://127.0.0.1:${server.address().port}/account/claim-voice`;
  assert.equal((await fetch(url)).status, 405);
  assert.equal((await fetch(url, { method: 'POST', body: '{}' })).status, 401);
  const headers = { Authorization: 'Bearer secret-token' };
  assert.equal((await fetch(url, { method: 'POST', headers, body: 'x'.repeat(12001) })).status, 413);
  const failed = await fetch(url, { method: 'POST', headers, body: '{"legacyToken":"old"}' });
  assert.equal(failed.status, 403);
  assert.equal(failed.headers.get('cache-control'), 'no-store');
  assert.equal((await failed.text()).includes('secret-token'), false);
});
