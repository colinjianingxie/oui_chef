import test from 'node:test';
import assert from 'node:assert/strict';
import { Meter, policy, reserve, reserveSession, finalizeSession, signedInUID } from './budget.mjs';
import { normalize, sessionUpdate } from './xai.mjs';

test('budget rejects invalid totals and over-budget reservations', () => {
  assert.equal(reserve(1350), 1500);
  for (const amount of [-1, 1351, NaN, Infinity, '0']) assert.throws(() => reserve(amount));
});
test('meter counts both audio directions and stops text/audio overages', () => {
  const meter = new Meter();
  meter.audio(48000 * 60); meter.audio(48000 * 30, true); meter.text();
  assert.equal(meter.cents, 16);
  assert.equal(meter.summary.inputSeconds, 60);
  assert.throws(() => meter.audio(3));
  assert.throws(() => meter.audio(48000 * 600));
  const text = new Meter();
  for (let i = 0; i < policy.textItems; i++) text.text();
  assert.throws(() => text.text());
});
const identity = (uid = 'cook', provider = 'password') => ({ uid, firebase: { sign_in_provider: provider } });
function ledger(records = new Map()) {
  let queue = Promise.resolve();
  return { records, doc: path => path, runTransaction: fn => {
    const transaction = queue.then(async () => {
      const writes = [];
      await fn({ get: async key => ({ data: () => records.get(key) }),
        set: (key, value) => writes.push(() => records.set(key, value)),
        create: (key, value) => { assert(!records.has(key)); writes.push(() => records.set(key, value)); },
        update: (key, value) => writes.push(() => records.set(key, { ...records.get(key), ...value })) });
      writes.forEach(write => write());
    });
    queue = transaction.catch(() => {});
    return transaction;
  } };
}

test('signed-in accounts work without enrollment; guests and explicitly blocked accounts do not', async () => {
  const db = ledger();
  for (const provider of ['password', 'google.com', 'apple.com', 'phone']) assert.equal(signedInUID(identity('cook', provider)), 'cook');
  for (const value of [undefined, { uid: 'cook' }, identity('cook', 'anonymous'), identity('cook', 'custom'), identity('../cook')]) {
    await assert.rejects(reserveSession(db, value, 'denied'), /Sign in/);
  }
  assert.equal(db.records.size, 0);
  db.records.set('voiceTesters/cook', { enabled: false });
  await assert.rejects(reserveSession(db, identity(), 'blocked'), /disabled/);
  db.records.delete('voiceTesters/cook');
  await reserveSession(db, identity(), 'first');
  assert.equal(db.records.get('voiceSessions/first').uid, 'cook');
});

test('three concurrent sessions reserve together, free only their own slot, and finalize once', async () => {
  const db = ledger();
  const attempts = await Promise.allSettled(['first', 'second', 'third', 'fourth'].map(id => reserveSession(db, identity(), id)));
  assert.equal(attempts.filter(result => result.status === 'fulfilled').length, 3);
  assert.match(attempts[3].reason.message, /three voice sessions/);
  assert.equal(db.records.get('voiceBudget/development').allocatedCents, 450);
  const meter = new Meter(); meter.audio(48000 * 60);
  await Promise.all([finalizeSession(db, 'first', meter, 'finished'), finalizeSession(db, 'first', meter, 'finished')]);
  assert.equal(db.records.get('voiceBudget/development').allocatedCents, 310);
  assert.deepEqual(Object.keys(db.records.get('voiceBudget/development').activeSessions), ['second', 'third']);
  await reserveSession(db, identity('another-cook'), 'fourth');
  assert.equal(db.records.get('voiceBudget/development').allocatedCents, 460);
  assert.equal(db.records.get('voiceSessions/fourth').uid, 'another-cook');
});

test('expired/crashed sessions keep their spend reservation and the shared budget cannot be bypassed', async () => {
  const db = ledger();
  db.records.set('voiceBudget/development', { allocatedCents: 1300, activeSessions: { crashed: Date.now() - 1 } });
  const results = await Promise.allSettled(['first', 'second'].map(id => reserveSession(db, identity(id), id)));
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.match(results[1].reason.message, /budget reached/);
  assert.equal(db.records.get('voiceBudget/development').allocatedCents, 1450);
  assert.deepEqual(Object.keys(db.records.get('voiceBudget/development').activeSessions), ['first']);
  await finalizeSession(db, 'first', new Meter(), 'finished');
  assert.equal(db.records.get('voiceBudget/development').allocatedCents, 1300);
});

test('rollout preserves the old ledger and waits for an active session on the previous revision', async () => {
  const db = ledger();
  db.records.set('voiceBudget/development', { allocatedCents: 200, activeID: 'old', activeUntil: Date.now() + 60000 });
  await assert.rejects(reserveSession(db, identity(), 'new'));
  assert.equal(db.records.get('voiceBudget/development').allocatedCents, 200);
  db.records.get('voiceBudget/development').activeUntil = Date.now() - 1;
  await reserveSession(db, identity(), 'new');
  const state = db.records.get('voiceBudget/development');
  assert.equal(state.allocatedCents, 350);
  assert.deepEqual(Object.keys(state.activeSessions), ['new']);
  assert.ok(state.activeUntil > Date.now());
});
test('xAI adapter uses specialist context and only the cooking function', () => {
  const session = sessionUpdate({ session: { recipe: { style: 'tequila' } } }).session;
  assert.match(session.instructions, /tequila drinks/);
  assert.equal(session.tools.length, 1);
  assert.equal(session.tools[0].name, 'cooking');
  assert.equal(session.audio.input.format.rate, 24000);
  assert.throws(() => sessionUpdate({ session: { recipe: { style: 'untrusted' } } }));
  assert.deepEqual(normalize({ type: 'response.audio.delta', delta: 'AAA=', item_id: 'a', response_id: 'r' }),
    { type: 'audio', audio: 'AAA=', itemID: 'a', responseID: 'r' });
  assert.equal(normalize({ type: 'future.provider.event' }), null);
});
