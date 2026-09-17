// One-time transfer of an existing development device's voice access to its signed-in account.
// Neither account identity nor the destination UID is accepted from the request body.
export async function claimVoiceAccess({ db, auth }, token, legacyToken) {
  if (typeof token !== 'string' || token.length > 10000 || typeof legacyToken !== 'string' || legacyToken.length > 10000) throw new Error('Invalid credentials');
  const [current, legacy] = await Promise.all([auth.verifyIdToken(token), auth.verifyIdToken(legacyToken)]);
  if (!current.uid || !legacy.uid || current.uid.includes('/') || legacy.uid.includes('/')) throw new Error('Invalid identity');
  const identities = current.firebase?.identities ?? {};
  if (!['google.com', 'apple.com', 'email', 'phone'].some(key => Array.isArray(identities[key]) && identities[key].length)) throw new Error('Sign in to an account first');
  if (legacy.firebase?.sign_in_provider !== 'anonymous' || Object.keys(legacy.firebase?.identities ?? {}).length) throw new Error('Only anonymous development access can migrate');
  if (current.uid === legacy.uid) return { migrated: false };
  return db.runTransaction(async tx => {
    const oldRef = db.doc(`voiceTesters/${legacy.uid}`);
    const claimRef = db.doc(`voiceMigrations/${legacy.uid}`);
    const currentRef = db.doc(`voiceTesters/${current.uid}`);
    const [old, claim, currentAccess] = await Promise.all([tx.get(oldRef), tx.get(claimRef), tx.get(currentRef)]);
    if (currentAccess.data()?.enabled === false) throw new Error('Voice access is disabled for this account');
    if (claim.exists) {
      if (claim.data().uid !== current.uid) throw new Error('Development access was already claimed');
      return { migrated: true };
    }
    if (old.data()?.enabled !== true) return { migrated: false };
    tx.set(currentRef, { enabled: true }, { merge: true });
    tx.update(oldRef, { enabled: false });
    tx.create(claimRef, { uid: current.uid, migratedAt: new Date() });
    return { migrated: true };
  });
}

export async function handleAccountRequest(req, res, services) {
  res.setHeader('Content-Type', 'application/json');
  res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') { res.writeHead(405); res.end(JSON.stringify({ error: 'Use POST' })); return; }
  try {
    const token = req.headers.authorization?.match(/^Bearer (\S+)$/)?.[1];
    if (!token) { res.writeHead(401); res.end(JSON.stringify({ error: 'Sign in required' })); return; }
    const chunks = []; let length = 0;
    for await (const chunk of req) {
      length += chunk.length;
      if (length > 12000) { res.writeHead(413); res.end(JSON.stringify({ error: 'Request too large' })); return; }
      chunks.push(chunk);
    }
    const { legacyToken } = JSON.parse(Buffer.concat(chunks).toString('utf8'));
    const result = await claimVoiceAccess(services, token, legacyToken);
    res.writeHead(200); res.end(JSON.stringify(result));
  } catch {
    res.writeHead(403); res.end(JSON.stringify({ error: 'Development voice access could not be transferred' }));
  }
}
