import { createHash, randomUUID } from 'node:crypto';
import { validateRecipe } from './recipe-agent.mjs';

export const shareOrigin = 'https://oui-chef-dev-20260914.web.app';
const validID = id => typeof id === 'string' && /^[a-f0-9]{32}$/.test(id);
const escape = value => String(value ?? '').replace(/[&<>"']/g, character => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[character]));

function snapshot(payload) {
  if(typeof payload!=='string' || payload.length>180000)throw new Error('Invalid recipe.');
  const source=JSON.parse(payload);
  validateRecipe(source);
  // Share recipe content, excluding account state, private storage paths and AI diagnostics.
  const recipe=Object.fromEntries(['title','summary','sourceURL','sourceName','creator','servings','prepMinutes','cookMinutes','totalMinutes','ingredients','preparation','steps','equipment','notes','adaptations','warnings','version'].filter(key=>source[key]!==undefined).map(key=>[key,source[key]]));
  return {...recipe,favorite:false,reviewed:false,evidence:[]};
}

async function readShare(db,id) {
  if(!validID(id))throw new Error('This recipe link is unavailable.');
  const doc=await db.doc(`recipeLinks/${id}`).get(),share=doc.data();
  if(!share || (await db.doc(`deletedAccounts/${share.ownerUID}`).get()).exists)throw new Error('This recipe link is unavailable.');
  return share;
}

export async function createRecipeShare(db,uid,payload) {
  const recipe=snapshot(payload),content=JSON.stringify(recipe);
  const key=createHash('sha256').update(content).digest('hex');
  const id=randomUUID().replaceAll('-','');
  const savedID=await db.runTransaction(async tx=>{
    const mapping=db.doc(`users/${uid}/recipeLinks/${key}`);
    const [previous,deleted]=await Promise.all([tx.get(mapping),tx.get(db.doc(`deletedAccounts/${uid}`))]);
    if(deleted.exists)throw new Error('Account deleted.');
    if(previous.exists)return previous.data().id;
    tx.set(db.doc(`recipeLinks/${id}`),{ownerUID:uid,payload:content,createdAt:Date.now()});
    tx.set(mapping,{id});return id;
  });
  return {url:`${shareOrigin}/r/${savedID}`};
}

export async function receiveRecipeShare(db,uid,id) {
  const share=await readShare(db,id),recipeID=`shared-${id}`;
  return db.runTransaction(async tx=>{
    const ref=db.doc(`users/${uid}/cookbook/${recipeID}`);
    const [saved,deleted,ownerDeleted]=await Promise.all([tx.get(ref),tx.get(db.doc(`deletedAccounts/${uid}`)),tx.get(db.doc(`deletedAccounts/${share.ownerUID}`))]);
    if(deleted.exists || ownerDeleted.exists)throw new Error('This recipe link is unavailable.');
    // Opening the same link again preserves the recipient's edits and favorite state.
    if(saved.exists && !saved.data().deleted)return {payload:saved.data().payload};
    const payload=JSON.stringify({...JSON.parse(share.payload),id:recipeID,createdAt:Date.now()});
    tx.set(ref,{id:recipeID,payload,updatedAt:Date.now()});
    return {payload};
  });
}

export async function handleRecipePage(req,res,{db}) {
  const match=req.url?.match(/^\/r\/([a-f0-9]{32})(?:\?.*)?$/);
  let status=200,body;
  try {
    if(!['GET','HEAD'].includes(req.method)) {res.writeHead(405,{Allow:'GET, HEAD'});res.end();return;}
    if(!match)throw new Error('Missing link');
    const {payload}=await readShare(db,match[1]),recipe=JSON.parse(payload);
    const title=escape(recipe.title),summary=escape(recipe.summary);
    body=`<meta property="og:title" content="${title}"><meta property="og:description" content="Cook this recipe with Oui Chef."><meta property="og:url" content="${shareOrigin}/r/${match[1]}"><title>${title} · Oui Chef</title></head><body><main><p class="eyebrow">OUI CHEF</p><h1>${title}</h1><p>${summary}</p><p>Save this recipe to your cookbook and cook with voice guidance.</p><a class="button" href="ouichef://recipe/${match[1]}">Open in Oui Chef</a><p class="hint">Already in the beta? Install Oui Chef from your TestFlight invitation, then return to this link.</p></main></body></html>`;
  } catch {
    status=404;body='<title>Recipe unavailable · Oui Chef</title></head><body><main><p class="eyebrow">OUI CHEF</p><h1>This recipe link is unavailable.</h1><p>Ask the person who shared it for a new link.</p></main></body></html>';
  }
  res.writeHead(status,{'Content-Type':'text/html; charset=utf-8','Cache-Control':'no-store','X-Robots-Tag':'noindex, nofollow','Referrer-Policy':'no-referrer','X-Content-Type-Options':'nosniff','Content-Security-Policy':"default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'"});
  const head='<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><style>body{margin:0;background:#f7f4eb;color:#25281d;font:17px -apple-system,BlinkMacSystemFont,sans-serif}main{max-width:480px;margin:12vh auto;padding:28px}h1{font:44px Georgia,serif;line-height:1.1}p{line-height:1.6}.eyebrow{letter-spacing:4px;font-size:12px;color:#465236}.button{display:block;padding:18px;margin:30px 0;text-align:center;background:#465236;color:white;border-radius:30px;text-decoration:none;font-weight:600}.hint{font-size:14px;color:#65665e}</style>';
  res.end(req.method==='HEAD'?'':head+body);
}
