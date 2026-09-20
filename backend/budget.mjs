// Conservative estimates: double the documented starting rates, not provider invoices.
export const policy = Object.freeze({ budgetCents: 1500, reservationCents: 150,
  maxSessions: 3, sessionSeconds: 600, audioSeconds: 600, textItems: 50, centsPerMinute: 10, centsPerText: 0.8 });

// Only these authored errors may be shown to clients; internal errors stay private.
export class VoiceAccessError extends Error {}

export function signedInUID(identity) {
  if (typeof identity?.uid !== 'string' || !/^[A-Za-z0-9_-]{1,128}$/.test(identity.uid) ||
      !['password', 'google.com', 'apple.com', 'phone'].includes(identity.firebase?.sign_in_provider)) {
    throw new VoiceAccessError('Sign in to your Oui Chef account in Profile, then tap the microphone again.');
  }
  return identity.uid;
}

const activeSessions = state => Object.fromEntries(Object.entries(state.activeSessions ?? {})
  .filter(([, until]) => Number.isFinite(until) && until > Date.now()));

export class Meter {
  inputBytes = 0;
  outputBytes = 0;
  textItems = 0;
  started = Date.now();
  audio(bytes, output = false) {
    if (!Number.isSafeInteger(bytes) || bytes <= 0 || bytes % 2 !== 0) throw new Error('Invalid PCM audio');
    if (output) this.outputBytes += bytes;
    else this.inputBytes += bytes;
    if ((this.inputBytes + this.outputBytes) / 48000 > policy.audioSeconds) throw new Error('Audio allowance reached');
  }
  text() { if (++this.textItems > policy.textItems) throw new Error('Text allowance reached'); }
  get cents() {
    return Math.ceil((this.inputBytes + this.outputBytes) / 48000 / 60 * policy.centsPerMinute + this.textItems * policy.centsPerText);
  }
  get summary() { return { inputSeconds: this.inputBytes / 48000, outputSeconds: this.outputBytes / 48000,
    textItems: this.textItems, connectedSeconds: (Date.now() - this.started) / 1000, estimatedCents: this.cents }; }
}

export function reserve(total) {
  if (!Number.isSafeInteger(total) || total < 0 || total + policy.reservationCents > policy.budgetCents) throw new VoiceAccessError('Development voice budget reached');
  return total + policy.reservationCents;
}

export async function reserveSession(db, identity, id) {
  const uid = signedInUID(identity);
  const budget = db.doc('voiceBudget/development');
  const session = db.doc(`voiceSessions/${id}`);
  await db.runTransaction(async tx => {
    const [tester, ledger] = await Promise.all([tx.get(db.doc(`voiceTesters/${uid}`)), tx.get(budget)]);
    if (tester.data()?.enabled === false) throw new VoiceAccessError('Voice access is disabled for this account.');
    const state = ledger.data() ?? {};
    const active = activeSessions(state);
    // Let an existing session on the previous revision finish before changing formats.
    if ((!state.activeSessions && state.activeUntil > Date.now()) || Object.keys(active).length >= policy.maxSessions) {
      throw new VoiceAccessError('All three voice sessions are in use. Please try again when one finishes.');
    }
    active[id] = Date.now() + (policy.sessionSeconds + 60) * 1000;
    // ponytail: one transactional ledger is sufficient for this three-session beta.
    // activeUntil also prevents the previous revision from reserving during a rollout.
    tx.set(budget, { allocatedCents: reserve(state.allocatedCents ?? 0), activeSessions: active,
      activeID: null, activeUntil: Math.max(...Object.values(active)) });
    tx.create(session, { uid, provider: 'xai', model: 'grok-voice-think-fast-2.0', promptVersion: 'companion-2', status: 'reserved', reservedCents: policy.reservationCents,
      createdAt: new Date(), expiresAt: new Date(Date.now() + 30 * 86400000) });
  });
}

export async function finalizeSession(db, id, meter, reason) {
  await db.runTransaction(async tx => {
    const budget = db.doc('voiceBudget/development');
    const session = db.doc(`voiceSessions/${id}`);
    const [ledger, record] = await Promise.all([tx.get(budget), tx.get(session)]);
    if (record.data()?.status !== 'reserved') return;
    const state = ledger.data();
    const active = activeSessions(state);
    delete active[id];
    // Crashed sessions retain their whole reservation; never trust client usage reports.
    tx.update(budget, { allocatedCents: Math.max(0, state.allocatedCents - policy.reservationCents + meter.cents),
      activeSessions: active, activeID: null, activeUntil: Math.max(0, ...Object.values(active)) });
    tx.update(session, { status: 'finished', reason, ...meter.summary, finishedAt: new Date() });
  });
}
