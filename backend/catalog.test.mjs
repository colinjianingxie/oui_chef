import test from 'node:test';
import assert from 'node:assert/strict';
import { Firestore, Timestamp } from 'firebase-admin/firestore';
import { publishRecipe, draftRevision, cardFor, canonicalTags } from './catalog.mjs';

// Run with the Firebase emulator only; never touches the live project.
const project = 'demo-ouichef';
const enabled = process.env.FIRESTORE_EMULATOR_HOST === '127.0.0.1:8085';
const db = enabled ? new Firestore({ projectId: project }) : null;
const base = `http://127.0.0.1:8085/v1/projects/${project}/databases/(default)/documents`;
function token(uid, email, verified = true) {
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  return `${encode({ alg: 'none', typ: 'JWT' })}.${encode({ sub: uid, user_id: uid, email, email_verified: verified, aud: project, iss: `https://securetoken.google.com/${project}`, iat: Math.floor(Date.now()/1000), exp: Math.floor(Date.now()/1000)+3600, firebase: { sign_in_provider: 'password' } })}.`;
}
const admin = token('admin', 'colinjianingxie@gmail.com'), otherAdmin = token('other-admin', 'wonmargarita@gmail.com');
const regular = token('regular', 'regular@example.com'), owner = token('owner', 'owner@example.com');
async function request(path, jwt, options = {}) {
  const response = await fetch(`${base}${path}`, { ...options, headers: { ...(jwt ? { Authorization: `Bearer ${jwt}` } : {}), 'Content-Type': 'application/json' } });
  return { status: response.status, body: await response.json() };
}
async function allowed(path, jwt) { const r = await request(path, jwt); assert.equal(r.status, 200, JSON.stringify(r.body)); }
async function denied(path, jwt, options) { const r = await request(path, jwt, options); assert.equal(r.status, 403, JSON.stringify(r.body)); }

test('Firestore protects drafts, subscriptions, admins, and publication across accounts', { skip: !enabled }, async t => {
  t.after(async () => {
    for (const path of ['recipes/paid-recipe', 'recipes/new-draft', 'recipes/private-set-recipe', 'recipeSets/paid', 'recipeSets/private', 'chefs/owned', 'users/regular']) await db.recursiveDelete(db.doc(path));
  });
  const version = (await db.doc('recipes/spaghetti').get()).data().publishedVersion;
  const recipe = (await db.doc(`recipes/spaghetti/versions/${version}`).get()).data().recipe;
  await db.doc('chefs/owned').set({ id: 'owned', name: 'Owner Chef', ownerUID: 'owner', status: 'published' });
  await db.doc('recipeSets/paid').set({ id: 'paid', chefID: 'owned', status: 'published', price: { kind: 'subscription', amountMinor: 499, currency: 'USD', interval: 'month', productID: 'test.paid' } });
  await db.doc('recipeSets/private').set({ id: 'private', chefID: 'owned', status: 'draft', price: { kind: 'free' } });
  const paid = { ...recipe, id: 'paid-recipe', chefID: 'owned', chefName: 'Owner Chef', recipeSetID: 'paid', version: 1 };
  const draft = { recipe: { ...paid, title: 'Private revision' }, classificationIDs: ['pasta'] };
  const revision = draftRevision(draft);
  await db.doc('recipes/paid-recipe').set(cardFor(paid, ['pasta'], 'published', true));
  await db.doc('recipes/paid-recipe/versions/1').set({ recipe: paid, published: true });
  await db.doc('recipes/paid-recipe/versions/draft').set({ ...draft, revision, validatedRevision: revision });
  await db.doc('recipes/new-draft').set(cardFor({ ...paid, id: 'new-draft' }, ['pasta'], 'draft', true));
  await db.doc('recipes/new-draft/versions/draft').set({ ...draft, revision, validatedRevision: revision });
  await db.doc('recipes/private-set-recipe').set(cardFor({ ...paid, id: 'private-set-recipe', recipeSetID: 'private' }, ['pasta'], 'published', false));
  await db.doc('recipes/private-set-recipe/versions/1').set({ recipe: paid, published: true });

  await allowed('/recipes/spaghetti');
  await allowed(`/recipes/spaghetti/versions/${version}`);
  await allowed(`/recipes/spaghetti/versions/${version}`, token('phone-user', undefined));
  await allowed('/ingredients/garlic');
  await denied('/recipes/paid-recipe/versions/1', regular);
  await denied('/recipes/private-set-recipe/versions/1', regular);
  await denied('/recipes/new-draft', regular);
  await denied('/recipes/paid-recipe/versions/draft', regular);
  await denied('/recipes/paid-recipe/versions/draft');
  await denied('/recipes/paid-recipe/versions/draft', token('fake', 'colinjianingxie@gmail.com', false));
  await allowed('/recipes/paid-recipe/versions/draft', admin);
  await allowed('/recipes/paid-recipe/versions/draft', otherAdmin);
  await allowed('/recipes/paid-recipe/versions/draft', owner);
  await allowed('/catalogAdmins/colinjianingxie@gmail.com', admin);
  await denied('/catalogAdmins/wonmargarita@gmail.com', admin);
  await denied('/voiceBudget/shared', admin);
  await denied('/catalogAdmins/regular@example.com', regular, { method: 'PATCH', body: JSON.stringify({ fields: { enabled: { booleanValue: true } } }) });
  await denied('/users/regular/recipeSetEntitlements/paid', regular, { method: 'PATCH', body: JSON.stringify({ fields: { expiresAt: { timestampValue: new Date(Date.now()+60000).toISOString() } } }) });
  await denied('/recipes/paid-recipe/versions/draft', admin, { method: 'PATCH', body: JSON.stringify({ fields: {} }) });

  const query = async (filter, jwt) => request(':runQuery', jwt, { method: 'POST', body: JSON.stringify({ structuredQuery: { from: [{ collectionId: 'recipes' }], ...(filter ? { where: { fieldFilter: { field: { fieldPath: filter[0] }, op: 'EQUAL', value: typeof filter[1] === 'boolean' ? { booleanValue: filter[1] } : { stringValue: filter[1] } } } } : {}), orderBy: [{ field: { fieldPath: 'title' }, direction: 'ASCENDING' }], limit: 12 } }) });
  assert.equal((await query(['status', 'published'])).status, 200);
  assert.equal((await query(null, regular)).status, 403);
  assert.equal((await query(['hasDraft', true], regular)).status, 403);
  assert.equal((await query(['hasDraft', true], admin)).status, 200);
  await db.doc('users/regular/recipeSetEntitlements/paid').set({ expiresAt: Timestamp.fromMillis(Date.now()+60000) });
  await allowed('/recipes/paid-recipe/versions/1', regular);
  await db.doc('users/regular/recipeSetEntitlements/paid').set({ expiresAt: Timestamp.fromMillis(Date.now()-60000) });
  await denied('/recipes/paid-recipe/versions/1', regular);

  await assert.rejects(publishRecipe(db, { uid: 'regular' }, 'paid-recipe', revision));
  await assert.rejects(publishRecipe(db, { uid: 'fake', email: 'colinjianingxie@gmail.com', email_verified: false }, 'paid-recipe', revision));
  await assert.rejects(publishRecipe(db, { uid: 'admin', email: 'colinjianingxie@gmail.com', email_verified: true }, 'paid-recipe', '0'.repeat(64)));
  const result = await publishRecipe(db, { uid: 'other-admin', email: 'wonmargarita@gmail.com', email_verified: true }, 'paid-recipe', revision);
  assert.equal(result.version, 2);
  assert.equal((await db.doc('recipes/paid-recipe').get()).data().hasDraft, false);
  assert.equal((await db.doc('recipes/paid-recipe/versions/1').get()).data().recipe.title, paid.title);
  assert.equal((await db.doc('recipes/paid-recipe/versions/2').get()).data().recipe.title, draft.recipe.title);
  await assert.rejects(publishRecipe(db, { uid: 'owner' }, 'paid-recipe', revision));
  await denied('/recipes/paid-recipe/versions/draft', regular);
  // Firestore may reorder map keys; validated drafts must remain publishable.
  assert.equal(draftRevision({ recipe: { b: 1, a: 2 }, classificationIDs: [] }), draftRevision({ recipe: { a: 2, b: 1 }, classificationIDs: [] }));
});


test('canonical discovery tags normalize duplicates and reject unsupported metadata', () => {
  assert.deepEqual(canonicalTags([' Pasta ', 'pasta', 'dinner']), ['pasta', 'dinner']);
  assert.throws(() => canonicalTags(['unknown-category']));
  assert.throws(() => canonicalTags([null]));
  assert.throws(() => canonicalTags(Array(21).fill('pasta')));
});
