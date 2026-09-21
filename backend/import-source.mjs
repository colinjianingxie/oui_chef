import { lookup } from 'node:dns/promises';
import { isIP, connect } from 'node:net';
import { request } from 'node:https';
import { createServer } from 'node:http';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
const exec = promisify(execFile);
// Source tools do not inherit API keys or cloud credential environment variables.
const toolEnvironment = { PATH: process.env.PATH, LANG: 'C.UTF-8' };

export function sourceName(raw) {
  const host = new URL(raw).hostname.toLowerCase();
  for (const [name, domains] of Object.entries({ YouTube: ['youtube.com', 'youtu.be'], Instagram: ['instagram.com'], TikTok: ['tiktok.com'], RedNote: ['xiaohongshu.com', 'xhslink.com'] })) {
    if (domains.some(d => host === d || host.endsWith('.' + d))) return name;
  }
  return 'Website';
}
export function publicAddress(address) {
  if (isIP(address) !== 4) return false; // Pin IPv4; never fall back to an unchecked DNS result.
  const [a,b] = address.split('.').map(Number);
  return !([0,10,127].includes(a) || a >= 224 || (a===169 && b===254) || (a===172 && b>=16 && b<=31) ||
    (a===192 && [0,168].includes(b)) || (a===100 && b>=64 && b<=127) || (a===198 && [18,19,51].includes(b)) || (a===203 && b===0));
}
export function normalizeURL(raw) {
  const url = new URL(raw);
  if (!['https:', 'http:'].includes(url.protocol) || url.username || url.password || (url.port && url.port !== '443') || isIP(url.hostname) || !url.hostname.includes('.')) throw new Error('Use a public recipe link.');
  url.protocol = 'https:'; url.hash = '';
  if (sourceName(url.href) === 'YouTube') {
    const id = url.hostname === 'youtu.be' ? url.pathname.split('/')[1] : url.pathname === '/watch' ? url.searchParams.get('v') : url.pathname.match(/^\/(?:shorts|embed|live)\/([^/]+)/)?.[1];
    if (id && /^[A-Za-z0-9_-]{11}$/.test(id)) return `https://www.youtube.com/watch?v=${id}`;
  }
  for (const key of [...url.searchParams.keys()]) if (/^(utm_|fbclid|igsh|si$)/.test(key)) url.searchParams.delete(key);
  return url.href;
}
export function importInput(body) {
  if (body.text != null && (typeof body.text !== 'string' || body.text.length > 40000)) throw new Error('Keep recipe text under 40,000 characters.');
  if (body.url != null && (typeof body.url !== 'string' || body.url.length > 4000)) throw new Error('Use a public recipe link.');
  const text = (body.text ?? '').trim(), raw = (body.url ?? '').trim();
  if (!raw && !text) throw new Error('Paste a recipe link or ingredients and steps.');
  const url = raw ? normalizeURL(raw) : '';
  return { url, text, source: url ? sourceName(url) : 'Pasted text' };
}
export function descriptionLinks(description = '') {
  const candidates = new Map();
  for (const line of description.split('\n')) {
    for (const match of line.matchAll(/https?:\/\/[^\s<>"']+/g)) {
      try {
        let url = new URL(match[0].replace(/[.,;!?)\]。！，；）]+$/u, ''));
        if (sourceName(url.href) === 'YouTube' && url.pathname === '/redirect') url = new URL(url.searchParams.get('q') ?? url.searchParams.get('url'));
        const normalized = normalizeURL(url.href);
        if (sourceName(normalized) !== 'Website') continue;
        const priority = /recipe|ingredients|instructions|食谱|食譜|配方|做法|レシピ/i.test(line) ? 1 : 0;
        candidates.set(normalized, Math.max(priority, candidates.get(normalized) ?? 0));
      } catch { /* Description links must pass the same public URL checks as the original source. */ }
    }
  }
  // ponytail: read at most three description links; creator research handles missing or truncated links.
  return [...candidates].sort((a,b) => b[1] - a[1]).slice(0,3).map(([url]) => url);
}
async function resolvePublic(host) {
  const records = await lookup(host, { all: true, family: 4 });
  if (!records.length || records.some(r => !publicAddress(r.address))) throw new Error('This address is not a public source.');
  return records[0].address;
}
export async function safeFetch(raw, limit = 3_000_000, redirects = 0) {
  if (redirects > 5) throw new Error('Too many source redirects.');
  const url = new URL(normalizeURL(raw)), address = await resolvePublic(url.hostname);
  const result = await new Promise((resolve, reject) => {
    const req = request(url, { signal: AbortSignal.timeout(45000), headers: { 'User-Agent': 'OuiChefRecipeImporter/2.0', 'Accept-Encoding': 'identity' },
      lookup: (_host, options, cb) => options.all ? cb(null, [{ address, family: 4 }]) : cb(null, address, 4) }, res => {
      const chunks = []; let size = 0;
      res.on('data', chunk => { size += chunk.length; if (size > limit) res.destroy(new Error('Source exceeds import size limit.')); else chunks.push(chunk); });
      res.on('error', reject);
      res.on('end', () => resolve({ status: res.statusCode, headers: res.headers, bytes: Buffer.concat(chunks), url: url.href }));
    });
    req.setTimeout(25000, () => req.destroy(new Error('Source timed out.')));
    req.on('error', reject); req.end();
  });
  if ([301,302,303,307,308].includes(result.status) && result.headers.location) return safeFetch(new URL(result.headers.location, url).href, limit, redirects + 1);
  if (result.status !== 200) throw Object.assign(new Error('Source could not be read. It may require a login.'), { status: result.status });
  return result;
}
// Media extraction's every HTTPS connection also resolves/pins a public IP.
async function mediaProxy() {
  const server = createServer((_req,res) => { res.writeHead(403); res.end(); });
  const sockets = new Set();
  server.on('connection', socket => { sockets.add(socket); socket.on('close', () => sockets.delete(socket)); });
  server.on('connect', async (req, client, head) => {
    try {
      const [host, port] = req.url.split(':');
      if (port !== '443' || !host.includes('.') || isIP(host)) throw new Error('Invalid media host');
      const upstream = connect({ host: await resolvePublic(host), port: 443 });
      sockets.add(upstream); upstream.on('close', () => sockets.delete(upstream));
      upstream.setTimeout(25000, () => upstream.destroy());
      upstream.on('error', () => client.destroy()); client.on('error', () => upstream.destroy());
      client.on('close', () => upstream.destroy());
      upstream.on('connect', () => { client.write('HTTP/1.1 200 Connection Established\r\n\r\n'); if (head.length) upstream.write(head); upstream.pipe(client); client.pipe(upstream); });
    } catch { client.end('HTTP/1.1 403 Forbidden\r\n\r\n'); }
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  return { url: `http://127.0.0.1:${server.address().port}`, close() { sockets.forEach(s => s.destroy()); server.close(); } };
}
export function retrievalError(error) {
  const detail = String(error?.stderr ?? error?.message ?? '');
  if (/sign in.*(bot|confirm)|LOGIN_REQUIRED/i.test(detail)) return 'YouTube requested a sign-in check from the import server.';
  if (error?.status === 429 || /429|too many requests/i.test(detail)) return 'The source rate-limited the import server.';
  if (error?.name === 'TimeoutError' || /timed? ?out|ETIMEDOUT/i.test(detail) || error?.killed) return 'Source retrieval timed out.';
  if (error?.status === 403 || /403|forbidden/i.test(detail)) return 'The source refused access to its media.';
  if (/format.*not available|no video formats/i.test(detail)) return 'Video formats were unavailable; trying the public description and captions.';
  return 'The source extractor could not retrieve media metadata.';
}
export function captionText(raw, timestamps = false) {
  if (raw.trim().startsWith('{')) {
    try { return JSON.parse(raw).events?.map(e => {
      const text = (e.segs ?? []).map(s => s.utf8 ?? '').join('').trim();
      return text && (timestamps && Number.isFinite(e.tStartMs) ? `[${e.tStartMs / 1000}s] ${text}` : text);
    }).filter(Boolean).join('\n') ?? ''; } catch { return ''; }
  }
  if (!raw.trim().startsWith('WEBVTT')) return '';
  const lines = raw.split('\n').filter(line => line.trim() && !/^(WEBVTT|Kind:|Language:|NOTE|\d+$)|-->/.test(line));
  const text = lines.join('\n').replace(/<[^>]*>/g, '').trim();
  return text && timestamps ? raw : text;
}
export function captionTracks(meta) {
  const tracks = [];
  for (const [kind, languages] of [['manual', meta.subtitles], ['automatic', meta.automatic_captions]]) {
    for (const [language, formats] of Object.entries(languages ?? {})) {
      for (const track of formats) if (['vtt', 'json3'].includes(track.ext)) tracks.push({ ...track, language, kind });
    }
  }
  for (const track of meta.captionTracks ?? []) {
    for (const ext of ['json3', 'vtt']) {
      const url = new URL(track.baseUrl); url.searchParams.set('fmt', ext);
      tracks.push({ url: url.href, ext, language: track.languageCode, kind: track.kind === 'asr' ? 'automatic' : 'manual' });
    }
  }
  const rank = track => {
    const url = new URL(track.url);
    const original = track.language?.endsWith('-orig') || track.language === meta.language;
    return (url.searchParams.has('tlang') ? 10 : 0) + (original ? 0 : track.kind === 'manual' ? 1 : 2);
  };
  const sorted = tracks.sort((a,b) => rank(a) - rank(b) || Number(a.ext !== 'json3') - Number(b.ext !== 'json3'));
  // Try different languages before alternate encodings of the same track.
  const seen = new Set(), first = [], alternates = [];
  for (const track of sorted) {
    const key = `${track.kind}:${track.language}`;
    (seen.has(key) ? alternates : first).push(track); seen.add(key);
  }
  return [...first, ...alternates].slice(0, 4);
}
export async function readCaptions(tracks, result, fetchSource = safeFetch) {
  for (const track of tracks) {
    try {
      const caption = await fetchSource(track.url, 1_000_000);
      const transcript = captionText(caption.bytes.toString(), true);
      if (transcript) {
        result.transcript = transcript.slice(0,80000);
        result.transcriptLanguage = track.language ?? null;
        result.hasTranscript = true; return;
      }
    } catch { /* Try the next available caption track. */ }
  }
  result.retrievalErrors.push(tracks.length ? 'Caption tracks were listed, but returned no readable captions.' : 'No caption tracks were exposed by the source.');
}
export async function readPage(url, { captions = false, onMetadata = async () => {} } = {}) {
  const page = await safeFetch(url);
  if (!/text\/|json|xml/.test(page.headers['content-type'] ?? 'text/html')) throw new Error('Share a recipe page or video post.');
  const directory = await mkdtemp(join(tmpdir(), 'oui-page-'));
  try {
    const file = join(directory, 'page.html'); await writeFile(file, page.bytes);
    const youtube = sourceName(url) === 'YouTube';
    const { stdout } = await exec('python3', [fileURLToPath(new URL('./tools/extract.py', import.meta.url)), file, ...(youtube ? ['--youtube'] : [])], { timeout: 15000, maxBuffer: 500000, env: toolEnvironment });
    const result = { ...JSON.parse(stdout), url: page.url, hasTranscript: false, retrievalErrors: [] };
    await onMetadata(result);
    if (youtube && captions) {
      await readCaptions(captionTracks(result), result);
    }
    delete result.captionTracks;
    return result;
  } finally { await rm(directory, { recursive: true, force: true }); }
}
export async function readSocial(url, { withMedia = false, captions = false, onMetadata = async () => {} } = {}) {
  if (sourceName(url) === 'Website') return { text: '', images: [] };
  const proxy = await mediaProxy(), directory = await mkdtemp(join(tmpdir(), 'oui-media-'));
  try {
    const { stdout } = await exec('python3', ['-m', 'yt_dlp', '--ignore-config', '--no-plugin-dirs', '--no-remote-components', '--js-runtimes', 'node', '--no-cache-dir', '--proxy', proxy.url, '--skip-download', '--ignore-no-formats-error', '--dump-single-json', '--no-playlist', '--no-warnings', '--socket-timeout', '15', '--retries', '0', '--', normalizeURL(url)], { timeout: 55000, maxBuffer: 5_000_000, env: toolEnvironment });
    const meta = JSON.parse(stdout);
    const result = { title: meta.title ?? null, creator: meta.uploader ?? null, description: meta.description ?? '', text: `${meta.title ?? ''}\nCreator: ${meta.uploader ?? ''}\n${meta.description ?? ''}`, imageURL: meta.thumbnail, images: [], duration: meta.duration,
      extractor: meta.extractor_key ?? meta.extractor ?? sourceName(url), hasTranscript: false, retrievalErrors: [] };
    await onMetadata(result);
    if (captions || withMedia) {
      await readCaptions(captionTracks(meta), result);
      if (!result.hasTranscript && sourceName(url) === 'YouTube') {
        try {
          const page = await readPage(url, { captions: true });
          result.retrievalErrors.push(...page.retrievalErrors);
          if (page.hasTranscript) {
            result.transcript = page.transcript; result.transcriptLanguage = page.transcriptLanguage;
            result.hasTranscript = true;
          }
        } catch { result.retrievalErrors.push('The public video captions could not be read.'); }
      }
    }
    // Captions are deterministic evidence; only download/transcribe when they are unavailable.
    if (withMedia && !result.hasTranscript && Number.isFinite(meta.duration) && meta.duration > 0 && meta.duration <= 1200) {
      try {
        const formats = (meta.formats ?? []).filter(f => f.url?.startsWith('https:') && f.protocol === 'https' && f.acodec !== 'none');
        const format = formats.find(f => f.vcodec !== 'none' && f.height <= 480 && f.ext === 'mp4') ?? formats.find(f => f.vcodec === 'none');
        if (format) {
          const media = await safeFetch(format.url, 40_000_000); const file = join(directory, 'media'); await writeFile(file, media.bytes);
          const audio = join(directory, 'audio.mp3');
          await exec('ffmpeg', ['-v','error','-protocol_whitelist','file,pipe','-i',file,'-vn','-ac','1','-ar','16000','-t','1200',audio], { timeout: 45000, env: toolEnvironment });
          result.audio = await readFile(audio);
          if (format.vcodec !== 'none') {
            for (const fraction of [0.15,0.4,0.65,0.85]) {
              const second = Math.floor(meta.duration * fraction), frame = join(directory, `frame-${second}.jpg`);
              await exec('ffmpeg', ['-v','error','-ss',String(second),'-protocol_whitelist','file,pipe','-i',file,'-frames:v','1','-vf','scale=640:-1',frame], { timeout: 15000, env: toolEnvironment });
              result.images.push({ second, data: (await readFile(frame)).toString('base64') });
            }
          }
        } else { result.retrievalErrors.push('This platform did not expose a downloadable media file.'); }
      } catch(error) { result.retrievalErrors.push(retrievalError(error)); }
    }
    return result;
  } finally { proxy.close(); await rm(directory, { recursive: true, force: true }); }
}
