import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
const tags = JSON.parse(readFileSync(new URL('../OuiChef/Core/Resources/catalog-tags.json', import.meta.url)));
export function canonicalTags(values) {
  if (!Array.isArray(values) || values.length > 20 || !values.every(value => typeof value === 'string')) throw new Error('Invalid tags');
  const result = [...new Set(values.map(value => value.trim().toLowerCase()))];
  if (result.some(id => !tags.some(tag => tag.id === id))) throw new Error('Unknown tag');
  return result;
}

export function canonicalAccess(value) {
  if (value?.kind === 'free') return { kind: 'free' };
  if (value?.kind === 'subscription' && typeof value.productID === 'string' && /^[A-Za-z0-9._-]{1,200}$/.test(value.productID)) {
    return { kind: 'subscription', productID: value.productID };
  }
  throw new Error('Invalid recipe-set access');
}

export const catalogProject = 'oui-chef-dev-20260914';
export const validID = id => typeof id === 'string' && /^[a-zA-Z0-9_-]{1,100}$/.test(id);
const canonical = value => Array.isArray(value) ? value.map(canonical) : value && typeof value === 'object' ? Object.fromEntries(Object.keys(value).sort().map(key => [key, canonical(value[key])])) : value;
export const draftRevision = draft => createHash('sha256').update(JSON.stringify(canonical([draft.recipe, draft.classificationIDs ?? draft.recipe.tags]))).digest('hex');
export function cardFor(recipe, tags, status, hasDraft) {
  tags = canonicalTags(tags ?? recipe.tags);
  const { id, title, subtitle, style, minutes, baseServings, maximumServings, chefID, chefName, recipeSetID } = recipe;
  return { id, title, subtitle, style, minutes, baseServings, maximumServings, chefID, chefName, recipeSetID, tags,
    ...(recipe.totalMinutes == null ? {} : { totalMinutes: recipe.totalMinutes }),
    ...(recipe.maximumMinutes == null ? {} : { maximumMinutes: recipe.maximumMinutes }),
    status, hasDraft, publishedVersion: status === 'published' ? recipe.version : null };
}
export async function publishRecipe(db, identity, recipeID, revision) {
  if (!validID(recipeID) || typeof revision !== 'string' || !/^[a-f0-9]{64}$/.test(revision)) throw new Error('Invalid recipe or draft revision.');
  return db.runTransaction(async tx => {
    const ref = db.doc(`recipes/${recipeID}`), draftRef = ref.collection('versions').doc('draft');
    const [cardDoc, draftDoc] = await Promise.all([tx.get(ref), tx.get(draftRef)]);
    if (!cardDoc.exists || !draftDoc.exists) throw new Error('Draft not found.');
    const card = cardDoc.data(), draft = draftDoc.data();
    const chefDoc = await tx.get(db.doc(`chefs/${card.chefID}`));
    let admin = false;
    if (identity.email_verified === true && typeof identity.email === 'string' && !identity.email.includes('/')) {
      admin = (await tx.get(db.doc(`catalogAdmins/${identity.email.toLowerCase()}`))).data()?.enabled === true;
    }
    if (!admin && (!identity.uid || chefDoc.data()?.ownerUID !== identity.uid)) throw new Error('Catalog owner or administrator required.');
    // Only the trusted import command writes validated drafts. Client writes are denied by rules.
    if (!card.hasDraft || draft.revision !== revision || draft.validatedRevision !== revision || draftRevision(draft) !== revision) throw new Error('Draft changed. Re-import or refresh it before publishing.');
    const recipe = draft.recipe;
    if (recipe.id !== recipeID || recipe.chefID !== card.chefID || recipe.recipeSetID !== card.recipeSetID) throw new Error('Recipe ownership cannot change during publication.');
    const setDoc = await tx.get(db.doc(`recipeSets/${recipe.recipeSetID}`));
    if (!setDoc.exists || setDoc.data().chefID !== recipe.chefID || setDoc.data().status !== 'published' || chefDoc.data()?.status !== 'published') throw new Error('Publish the owning chef and recipe set first.');
    const labels = canonicalTags(draft.classificationIDs ?? recipe.tags);
    const version = Math.max(0, card.publishedVersion ?? 0) + 1;
    const published = { ...recipe, tags: labels, chefName: chefDoc.data().name, version };
    tx.create(ref.collection('versions').doc(String(version)), { recipe: published, published: true, publishedAt: new Date() });
    tx.set(ref, cardFor(published, labels, 'published', false));
    tx.delete(draftRef);
    return { recipeID, version };
  });
}
export async function handleCatalogRequest(req, res, { db, auth }) {
  res.setHeader('Content-Type', 'application/json'); res.setHeader('Cache-Control', 'no-store');
  if (req.method !== 'POST') { res.writeHead(405); res.end(JSON.stringify({ error: 'Use POST' })); return; }
  try {
    const token = req.headers.authorization?.match(/^Bearer (\S+)$/)?.[1];
    if (!token || token.length > 10000) throw new Error('Sign in required.');
    const identity = await auth.verifyIdToken(token);
    let body = '';
    for await (const chunk of req) { body += chunk; if (body.length > 2000) throw new Error('Request too large.'); }
    const { recipeID, draftRevision } = JSON.parse(body);
    const result = await publishRecipe(db, identity, recipeID, draftRevision);
    res.writeHead(200); res.end(JSON.stringify(result));
  } catch (error) {
    res.writeHead(403); res.end(JSON.stringify({ error: ['Catalog owner or administrator required.', 'Draft changed. Re-import or refresh it before publishing.', 'Publish the owning chef and recipe set first.'].includes(error.message) ? error.message : 'Recipe could not be published.' }));
  }
}
