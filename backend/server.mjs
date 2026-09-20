import { handleCompanion } from './companion.mjs';
import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import WebSocket, { WebSocketServer } from 'ws';
import { Meter, policy, reserveSession, finalizeSession, signedInUID, VoiceAccessError } from './budget.mjs';
import { openProvider, normalize, sessionUpdate, providerEvent } from './xai.mjs';
import { handleCatalogRequest } from './catalog.mjs';
import { handleAccountRequest } from './accounts.mjs';

export function createVoiceServer({ db, auth, connectProvider = openProvider }) {
const server = createServer((req, res) => {
  if (req.url?.startsWith('/companion/')) { void handleCompanion(req, res, { db, auth }); return; }
  if (req.url === '/catalog/publish') { void handleCatalogRequest(req, res, { db, auth }); return; }
  if (req.url === '/account/claim-voice') { void handleAccountRequest(req, res, { db, auth }); return; }
  res.writeHead(req.url === '/health' ? 200 : 404, { 'Content-Type': 'application/json' });
  res.end(JSON.stringify({ service: 'oui-chef-voice' }));
});
const sockets = new WebSocketServer({ noServer: true, maxPayload: 750000, perMessageDeflate: false });

server.on('upgrade', async (req, socket, head) => {
  socket.on('error', () => {});
  socket.setTimeout(15000, () => socket.destroy());
  try {
    if (req.url !== '/voice') throw new Error('Invalid route');
    const token = req.headers.authorization?.match(/^Bearer (\S+)$/)?.[1];
    if (!token || token.length > 10000) throw new Error('Sign in required');
    const identity = await auth.verifyIdToken(token);
    if (socket.destroyed) return;
    socket.setTimeout(0);
    sockets.handleUpgrade(req, socket, head, ws => sockets.emit('connection', ws, identity));
  } catch {
    socket.end('HTTP/1.1 403 Forbidden\r\nConnection: close\r\nContent-Length: 0\r\n\r\n');
  }
});

sockets.on('connection', (client, identity) => {
  try { signedInUID(identity); }
  catch (error) {
    client.on('error', () => {});
    client.send(JSON.stringify({ type: 'ended', message: error.message, code: 'sign_in_required' }));
    client.close(1008, 'Sign in required');
    return;
  }
  const id = randomUUID(), meter = new Meter();
  let upstream, reserved = false, closed = false, initialized = false, responding = false, shouldRespond = false;
  let context, activeResponseID, pendingTools = new Set(), seenCalls = new Set();
  let eventCount = 0, inputWindowBytes = 0;
  const send = event => { if (client.readyState === WebSocket.OPEN) client.send(JSON.stringify(event)); };
  const providerSend = event => {
    if (upstream?.readyState !== WebSocket.OPEN) throw new Error('Voice is still connecting');
    if (upstream.bufferedAmount > 256000) throw new Error('Voice connection is too slow');
    upstream.send(JSON.stringify(event));
  };
  const finish = async reason => {
    if (closed) return;
    closed = true;
    clearTimeout(deadline); clearTimeout(startDeadline); clearInterval(rateWindow);
    upstream?.terminate();
    send({ type: 'ended', message: reason, usage: meter.summary });
    client.close(1000, 'Voice session ended');
    if (reserved) {
      try { await finalizeSession(db, id, meter, reason); }
      catch { console.error(JSON.stringify({ event: 'voice_finalize_failed', id })); }
    }
  };
  const startDeadline = setTimeout(() => finish('Voice setup timed out. Tap to reconnect.'), 20000);
  const deadline = setTimeout(() => finish('Development voice session limit reached. Timers continue; tap to reconnect.'), policy.sessionSeconds * 1000);
  const rateWindow = setInterval(() => { eventCount = 0; inputWindowBytes = 0; }, 1000);
  const respond = () => {
    shouldRespond = true;
    if (!responding && pendingTools.size === 0) {
      shouldRespond = false;
      providerSend(providerEvent('respond'));
      responding = true;
    }
  };

  // Process messages in wire order; no races between tool results and context updates.
  let work = Promise.resolve();
  client.on('message', data => {
    if (++eventCount > 80) { finish('Voice message limit reached'); return; }
    work = work.then(async () => {
      if (closed) return;
      const event = JSON.parse(data.toString());
      if (event.type === 'start') {
        if (initialized) throw new Error('Voice session already started');
        initialized = true;
        context = event.context;
        const configuration = sessionUpdate(context);
        if (!process.env.XAI_API_KEY) throw new Error('xAI voice has not been configured yet');
        await reserveSession(db, identity, id);
        reserved = true;
        if (closed) { await finalizeSession(db, id, meter, 'closed_before_connection'); return; }
        upstream = connectProvider();
        upstream.on('open', () => providerSend(configuration));
        upstream.on('message', bytes => {
          try {
            if (closed) return;
            const source = JSON.parse(bytes.toString());
            const normalized = normalize(source);
            if (!normalized) return;
            if (normalized.type === 'ready') { clearTimeout(startDeadline); send({ ...normalized, provider: 'xai', sessionID: id }); return; }
            if (normalized.type === 'responding') { responding = true; activeResponseID = normalized.responseID; }
            if (normalized.type === 'audio') {
              meter.audio(Buffer.from(normalized.audio, 'base64').length, true);
              if (client.bufferedAmount > 256000) throw new Error('Audio playback cannot keep up');
            }
            if (normalized.type === 'tool') {
              if (seenCalls.has(normalized.callID)) return;
              if (normalized.name !== 'cooking' || typeof normalized.callID !== 'string' || seenCalls.size >= 100) throw new Error('Invalid voice tool');
              seenCalls.add(normalized.callID); pendingTools.add(normalized.callID);
            }
            if (normalized.type === 'response_done') {
              if (normalized.responseID === activeResponseID) responding = false;
              if (shouldRespond && !responding && pendingTools.size === 0) respond();
            }
            send(normalized);
            if (normalized.type === 'error') finish('Voice provider error. Tap to reconnect.');
          } catch { finish('Voice allowance or connection limit reached. Cooking progress is saved.'); }
        });
        upstream.on('error', () => finish('Could not connect to xAI. Check the voice configuration and credit balance.'));
        upstream.on('close', () => finish('Voice disconnected. Timers continue; tap to reconnect.'));
        return;
      }
      if (!initialized) throw new Error('Start voice first');
      switch (event.type) {
        case 'audio': {
          if (typeof event.audio !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(event.audio)) throw new Error('Invalid audio');
          const audio = Buffer.from(event.audio, 'base64');
          inputWindowBytes += audio.length;
          if (inputWindowBytes > 96000) throw new Error('Audio arrived too quickly');
          meter.audio(audio.length);
          providerSend(providerEvent('audio', event)); break;
        }
        case 'context': context = event.context; providerSend(sessionUpdate(context)); break;
        case 'text': case 'cue': {
          if (typeof event.text !== 'string' || event.text.length > 2000) throw new Error('Invalid voice message');
          if (event.type === 'cue' && (responding || pendingTools.size)) return;
          meter.text();
          providerSend(providerEvent('text', { text: event.type === 'cue' ? `App coaching intent (do not mark any task complete): ${event.text}` : event.text }));
          respond(); break;
        }
        case 'tool_result': {
          if (!pendingTools.delete(event.callID)) throw new Error('Unknown or duplicate tool result');
          if (typeof event.output !== 'string' || event.output.length > 70000) throw new Error('Invalid tool result');
          context = event.context;
          providerSend(sessionUpdate(context));
          providerSend(providerEvent('tool_result', event));
          respond(); break;
        }
        case 'interrupt':
          if (responding && event.cancelResponse !== false) providerSend(providerEvent('cancel'));
          if (typeof event.itemID === 'string' && Number.isFinite(event.playedMs) && event.playedMs >= 0) {
            providerSend(providerEvent('truncate', event));
          }
          shouldRespond = false; break;
        default: throw new Error('Unsupported voice event');
      }
    }).catch(error => finish(error instanceof VoiceAccessError ? error.message : 'Voice stopped. Check your connection and try again; cooking progress is saved.'));
  });
  client.on('close', () => finish('client_disconnected'));
  client.on('error', () => finish('client_connection_error'));
});

return server;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const [{ initializeApp }, { getAuth }, { getFirestore }] = await Promise.all([
    import('firebase-admin/app'), import('firebase-admin/auth'), import('firebase-admin/firestore')]);
  initializeApp({ storageBucket: process.env.FIREBASE_STORAGE_BUCKET ?? "oui-chef-dev-20260914.firebasestorage.app" });
  createVoiceServer({ db: getFirestore(), auth: getAuth() }).listen(Number(process.env.PORT ?? 8080), '0.0.0.0');
}
