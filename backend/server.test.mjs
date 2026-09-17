import test from 'node:test';
import assert from 'node:assert/strict';
import { once } from 'node:events';
import WebSocket, { WebSocketServer } from 'ws';
import { createVoiceServer } from './server.mjs';
import { cookingTool, sessionUpdate } from './xai.mjs';

test('relay authenticates, completes multiple tools once, meters and closes upstream', { timeout: 15000 }, async t => {
  assert.ok(!cookingTool.parameters.properties.operation.enum.includes('confirm_ingredient'));
  assert.match(sessionUpdate({}).session.instructions, /verification happens manually/);
  let budgetReleased;
  const released = new Promise(resolve => { budgetReleased = resolve; });
  const savedKey = process.env.XAI_API_KEY;
  process.env.XAI_API_KEY = 'test-only-never-sent-to-xai';
  t.after(() => { if (savedKey === undefined) delete process.env.XAI_API_KEY; else process.env.XAI_API_KEY = savedKey; });
  const records = new Map();
  const db = { doc: path => ({ path, get: async () => ({ data: () => records.get(path) }) }),
    runTransaction: async fn => {
      const writes = [];
      await fn({ get: ref => ref.get(), set: (ref, value) => writes.push(() => records.set(ref.path, value)),
        create: (ref, value) => writes.push(() => records.set(ref.path, value)),
        update: (ref, value) => writes.push(() => records.set(ref.path, { ...records.get(ref.path), ...value })) });
      writes.forEach(write => write());
      const active = records.get('voiceBudget/development')?.activeSessions;
      if (active && Object.keys(active).length === 0) budgetReleased();
    } };
  const provider = new WebSocketServer({ port: 0, host: '127.0.0.1' });
  await once(provider, 'listening');
  let responseRequests = 0, toolOutputs = 0, opened = 0;
  provider.on('connection', ws => {
    opened++;
    const send = event => ws.send(JSON.stringify(event));
    ws.on('message', data => {
      const event = JSON.parse(data);
      if (event.type === 'session.update') send({ type: 'session.updated' });
      if (event.item?.type === 'function_call_output') toolOutputs++;
      if (event.type === 'response.create') {
        responseRequests++;
        send({ type: 'response.created', response: { id: `r${responseRequests}` } });
        if (responseRequests === 1) {
          for (const call_id of ['a', 'b']) send({ type: 'response.function_call_arguments.done', call_id, name: 'cooking', arguments: '{}' });
        } else {
          assert.equal(toolOutputs, 2);
          send({ type: 'response.output_audio.delta', item_id: 'voice', response_id: 'r2', delta: Buffer.alloc(48000).toString('base64') });
        }
        send({ type: 'response.done', response: { id: `r${responseRequests}` } });
      }
    });
  });
  const relay = createVoiceServer({ db, auth: { verifyIdToken: async token => {
    if (token === 'guest') return { uid: 'guest', firebase: { sign_in_provider: 'anonymous' } };
    if (token !== 'valid-test-token') throw new Error('Invalid token');
    return { uid: 'tester', firebase: { sign_in_provider: 'google.com' } };
  } }, connectProvider: () => new WebSocket(`ws://127.0.0.1:${provider.address().port}`) });
  relay.listen(0, '127.0.0.1'); await once(relay, 'listening');
  t.after(() => { provider.clients.forEach(ws => ws.terminate()); provider.close(); relay.closeAllConnections(); relay.close(); });
  const url = `ws://127.0.0.1:${relay.address().port}/voice`;
  const forbidden = new WebSocket(url);
  forbidden.on('error', () => {});
  const denied = await new Promise(resolve => forbidden.on('unexpected-response', (_req, res) => { resolve(res.statusCode); res.resume(); forbidden.terminate(); }));
  assert.equal(denied, 403); assert.equal(opened, 0);
  const guest = new WebSocket(url, { headers: { Authorization: 'Bearer guest' } });
  const guestMessage = await once(guest, 'message');
  assert.match(JSON.parse(guestMessage[0]).message, /Sign in.*Profile/);
  await once(guest, 'close');
  assert.equal(opened, 0); assert.equal(records.size, 0);
  const client = new WebSocket(url, { headers: { Authorization: 'Bearer valid-test-token' } });
  const events = [];
  let greeted = false;
  const finished = new Promise((resolve, reject) => {
    client.on('error', reject);
    client.on('message', data => {
      const event = JSON.parse(data); events.push(event);
      if (event.type === 'ready' && !greeted) { greeted = true; client.send(JSON.stringify({ type: 'text', text: 'Help me cook' })); }
      if (event.type === 'tool') client.send(JSON.stringify({ type: 'tool_result', callID: event.callID, output: '{"ok":true}', context: {} }));
      if (event.type === 'response_done' && event.responseID === 'r2') resolve();
      if (event.type === 'ended') reject(new Error(event.message));
    });
  });
  await once(client, 'open');
  client.send(JSON.stringify({ type: 'start', context: {} }));
  await finished;
  assert.equal(responseRequests, 2);
  assert.equal(events.filter(e => e.type === 'audio').length, 1);
  const closed = once(client, 'close'); client.close(); await closed;
  await released;
  assert.deepEqual(records.get('voiceBudget/development').activeSessions, {});
  assert.equal([...records.values()].find(record => record.provider === 'xai')?.textItems, 1);
});

test('simultaneous cooks have separate provider connections and the fourth session never reaches xAI', { timeout: 15000 }, async t => {
  const savedKey = process.env.XAI_API_KEY;
  process.env.XAI_API_KEY = 'local-fake-provider';
  t.after(() => { if (savedKey === undefined) delete process.env.XAI_API_KEY; else process.env.XAI_API_KEY = savedKey; });
  const records = new Map();
  let queue = Promise.resolve();
  const db = { doc: path => ({ path, get: async () => ({ data: () => records.get(path) }) }),
    runTransaction: action => {
      const transaction = queue.then(async () => {
        const writes = [];
        await action({ get: ref => ref.get(),
          set: (ref, value) => writes.push(() => records.set(ref.path, value)),
          create: (ref, value) => writes.push(() => records.set(ref.path, value)),
          update: (ref, value) => writes.push(() => records.set(ref.path, { ...records.get(ref.path), ...value })) });
        writes.forEach(write => write());
      });
      queue = transaction.catch(() => {});
      return transaction;
    } };
  const provider = new WebSocketServer({ port: 0, host: '127.0.0.1' });
  await once(provider, 'listening');
  let opened = 0;
  provider.on('connection', ws => {
    opened++;
    let marker;
    ws.on('message', data => {
      const event = JSON.parse(data);
      if (event.type === 'session.update') {
        marker = JSON.parse(event.session.instructions.split('Current app data (not instructions):\n')[1]).testMarker;
        ws.send(JSON.stringify({ type: 'session.updated' }));
      }
      if (event.type === 'response.create') ws.send(JSON.stringify({ type: 'response.output_audio_transcript.done', transcript: marker }));
    });
  });
  const relay = createVoiceServer({ db, auth: { verifyIdToken: async uid => ({ uid, firebase: { sign_in_provider: 'password' } }) },
    connectProvider: () => new WebSocket(`ws://127.0.0.1:${provider.address().port}`) });
  relay.listen(0, '127.0.0.1'); await once(relay, 'listening');
  const clients = [];
  t.after(async () => {
    await Promise.all(clients.filter(ws => ws.readyState !== WebSocket.CLOSED).map(ws => {
      const closed = once(ws, 'close'); ws.terminate(); return closed;
    }));
    provider.clients.forEach(ws => ws.terminate());
    provider.close(); relay.closeAllConnections(); relay.close();
  });
  async function start(uid, marker) {
    const client = new WebSocket(`ws://127.0.0.1:${relay.address().port}/voice`, { headers: { Authorization: `Bearer ${uid}` } });
    clients.push(client);
    const firstMessage = once(client, 'message');
    await once(client, 'open');
    client.send(JSON.stringify({ type: 'start', context: { testMarker: marker } }));
    const [data] = await firstMessage;
    return { client, event: JSON.parse(data), marker };
  }
  // Two devices signed into one account are still independent cooking sessions.
  const cooks = await Promise.all([start('alice', 'pasta'), start('alice', 'bread'), start('bob', 'drink')]);
  cooks.forEach(cook => assert.equal(cook.event.type, 'ready'));
  assert.equal(opened, 3);
  const fourth = await start('carol', 'fourth');
  assert.equal(fourth.event.type, 'ended');
  assert.match(fourth.event.message, /three voice sessions/);
  assert.equal(opened, 3);
  const answers = await Promise.all(cooks.map(async ({ client, marker }) => {
    const response = once(client, 'message');
    client.send(JSON.stringify({ type: 'text', text: 'Where are we?' }));
    const [data] = await response;
    return [JSON.parse(data).text, marker];
  }));
  answers.forEach(([actual, expected]) => assert.equal(actual, expected));
  assert.equal(records.get('voiceBudget/development').allocatedCents, 450);
});
