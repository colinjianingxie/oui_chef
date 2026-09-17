// Local administrator helper. gcloud credentials remain in memory and are never logged.
import { execFileSync } from 'node:child_process';
const project = 'oui-chef-dev-20260914';
const token = execFileSync('gcloud', ['auth', 'print-access-token'], { encoding: 'utf8' }).trim();
const [command, uid] = process.argv.slice(2);
if (command === 'initialize-auth') {
  const response = await fetch(`https://identitytoolkit.googleapis.com/v2/projects/${project}/identityPlatform:initializeAuth`, {
    method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'X-Goog-User-Project': project }, body: '{}' });
  if (!response.ok) throw new Error(`Auth initialization failed (${response.status}): ${(await response.json()).error?.message}`);
  console.log('Development authentication initialized');
  process.exit(0);
}
let url, body;
if (command === 'allow' && /^[A-Za-z0-9_-]{1,128}$/.test(uid ?? '')) {
  url = `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/voiceTesters/${uid}`;
  body = { fields: { enabled: { booleanValue: true } } };
} else if (command === 'enable-auth') {
  url = `https://identitytoolkit.googleapis.com/admin/v2/projects/${project}/config?updateMask=signIn.anonymous.enabled`;
  body = { signIn: { anonymous: { enabled: true } } };
} else { throw new Error('Usage: node backend/admin.mjs allow TESTER_UID | enable-auth'); }
const response = await fetch(url, { method: 'PATCH', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'X-Goog-User-Project': project }, body: JSON.stringify(body) });
if (!response.ok) { console.error(`Admin operation failed (${response.status}): ${(await response.json()).error?.message ?? 'Unknown error'}`); process.exitCode = 1; }
else console.log(`${command} succeeded${uid ? ` for ${uid}` : ''}`);
