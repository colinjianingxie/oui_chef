// Trusted operator commands. Never put service-account keys in the app or this repository.
import { readFile, writeFile, mkdtemp, rm } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Firestore } from 'firebase-admin/firestore';
import { OAuth2Client } from 'google-auth-library';
import { catalogProject, validID, draftRevision, cardFor, searchTokens, canonicalTags, publishRecipe } from './catalog.mjs';

const [command, argument, project] = process.argv.slice(2);
if (project !== catalogProject && !(project === 'demo-ouichef' && process.env.FIRESTORE_EMULATOR_HOST)) throw new Error('Explicit project required: seed catalog/seed.json oui-chef-dev-20260914 OR draft recipe-import.json oui-chef-dev-20260914');
const credentials = new OAuth2Client();
credentials.setCredentials({ access_token: process.env.FIRESTORE_EMULATOR_HOST ? 'owner' : execFileSync('gcloud', ['auth', 'print-access-token'], { encoding: 'utf8' }).trim() });
const db = new Firestore({ projectId: project, authClient: credentials });
const root = fileURLToPath(new URL('../', import.meta.url));
const readJSON = async path => JSON.parse(await readFile(path, 'utf8'));
async function createOnce(path, data) {
  await db.runTransaction(async tx => { const ref = db.doc(path); if (!(await tx.get(ref)).exists) tx.create(ref, data); });
}
async function validate(recipes, library) {
  const dir = await mkdtemp(join(tmpdir(), 'oui-chef-import-'));
  try {
    const file = join(dir, 'catalog.json'); await writeFile(file, JSON.stringify({ ...library, recipes }));
    execFileSync('swift', ['run', '--package-path', root, '--scratch-path', '/tmp/oui-chef-catalog-core', 'catalog-validate', file], { stdio: 'inherit' });
  } finally { await rm(dir, { recursive: true, force: true }); }
}
function checkSet(set) {
  const p = set.price;
  if (!validID(set.id) || !validID(set.chefID) || typeof set.title !== 'string' || !['draft', 'published'].includes(set.status) ||
      p?.currency !== 'USD' || !Number.isSafeInteger(p.amountMinor) || !(p.kind === 'free' ? p.amountMinor === 0 : p.kind === 'subscription' && p.amountMinor > 0 && ['month', 'year'].includes(p.interval) && typeof p.productID === 'string' && p.productID.length > 0)) throw new Error('Invalid recipe set or price');
}
if (command === 'seed') {
  const seed = await readJSON(argument);
  const library = await readJSON(join(root, 'OuiChef/Core/Resources/ingredients.json'));
  const { recipes } = await readJSON(join(root, 'OuiChef/Core/Resources/recipes.json'));
  await validate(recipes, library);
  const categoryMap = new Map(library.categories.map(c => [c.id, c]));
  for (const item of seed.classifications) {
    if (!validID(item.id)) throw new Error('Invalid classification');
    await createOnce(`classifications/${item.id}`, item);
  }
  for (const chef of seed.chefs) {
    if (!validID(chef.id) || typeof chef.ownerUID !== 'string' || !chef.name) throw new Error('Invalid chef');
    await createOnce(`chefs/${chef.id}`, chef);
  }
  for (const set of seed.recipeSets) {
    checkSet(set);
    canonicalTags(set.tags ?? set.classificationIDs);
    if (!seed.chefs.some(c => c.id === set.chefID)) throw new Error('Unknown set references');
    await createOnce(`recipeSets/${set.id}`, set);
  }
  for (const category of library.categories) await createOnce(`ingredientCategories/${category.id}`, category);
  for (const food of library.foods) {
    const ancestors = []; let id = food.categoryID;
    while (id) { ancestors.push(id); id = categoryMap.get(id).parentID; }
    await createOnce(`ingredients/${food.id}`, { ...food, categoryAncestors: ancestors, searchTokens: searchTokens([food.name, ...(food.aliases ?? []), ...ancestors.map(id => categoryMap.get(id).name)]) });
  }
  for (const recipe of recipes) {
    const classes = canonicalTags(recipe.tags);
    if (!validID(recipe.id) || !seed.recipeSets.some(s => s.id === recipe.recipeSetID && s.chefID === recipe.chefID) || !classes?.every(id => seed.classifications.some(c => c.id === id))) throw new Error('Invalid recipe references');
    await db.runTransaction(async tx => {
      const ref = db.doc(`recipes/${recipe.id}`);
      if (!(await tx.get(ref)).exists) {
        tx.create(ref, cardFor(recipe, classes, 'published', false));
        tx.create(ref.collection('versions').doc(String(recipe.version)), { recipe, published: true, publishedAt: new Date() });
      }
    });
  }
  for (const email of seed.adminEmails) {
    if (!/^[^/\s]+@[^/\s]+$/.test(email) || email !== email.toLowerCase()) throw new Error('Invalid admin email');
    await createOnce(`catalogAdmins/${email}`, { enabled: true });
  }
  console.log(`Catalog seeded in ${project}; existing records preserved. ${recipes.length} starter recipes, ${library.foods.length} ingredients.`);
} else if (command === 'draft') {
  const draft = await readJSON(argument), recipe = draft.recipe;
  draft.classificationIDs = canonicalTags(draft.tags ?? draft.classificationIDs ?? recipe?.tags);
  recipe.tags = draft.classificationIDs;
  if (!validID(recipe?.id) || !validID(recipe.chefID) || !validID(recipe.recipeSetID) || !Array.isArray(draft.classificationIDs) || draft.classificationIDs.length > 20 || !draft.classificationIDs.every(validID)) throw new Error('Invalid import references');
  const [chef, set, categories] = await Promise.all([db.doc(`chefs/${recipe.chefID}`).get(), db.doc(`recipeSets/${recipe.recipeSetID}`).get(), db.collection('ingredientCategories').get()]);
  if (!chef.exists || set.data()?.chefID !== recipe.chefID) throw new Error('Create the owning chef/set first');
  recipe.chefName = chef.data().name;
  const pending = new Set(recipe.ingredients.flatMap(i => [i.foodID, ...(i.alternatives ?? []).map(a => a.foodID)])), foods = new Map();
  for (const id of pending) {
    if (!validID(id) || pending.size > 300) throw new Error('Invalid or oversized ingredient tree');
    const doc = await db.doc(`ingredients/${id}`).get();
    if (!doc.exists) throw new Error(`Missing ingredient: ${id}`);
    const food = doc.data(); foods.set(id, food); food.constituents.forEach(id => pending.add(id));
  }
  await validate([recipe], { schemaVersion: 1, foods: [...foods.values()], categories: categories.docs.map(d => d.data()) });
  const payload = { recipe, classificationIDs: draft.classificationIDs };
  const revision = draftRevision(payload);
  await db.runTransaction(async tx => {
    const ref = db.doc(`recipes/${recipe.id}`), old = await tx.get(ref);
    if (old.exists && (old.data().chefID !== recipe.chefID || old.data().recipeSetID !== recipe.recipeSetID)) throw new Error('Import cannot change recipe ownership');
    if (old.exists) tx.update(ref, { hasDraft: true });
    else tx.create(ref, cardFor(recipe, draft.classificationIDs, 'draft', true));
    tx.set(ref.collection('versions').doc('draft'), { ...payload, revision, validatedRevision: revision, importedAt: new Date() });
  });
  console.log(`Private draft ${recipe.id} imported. Preview and publish from the admin account in the app.`);
 } else if (command === 'migrate-tags') {
  if (!argument) throw new Error('Provide a new backup file path');
  const [recipes, sets] = await Promise.all([db.collection('recipes').get(), db.collection('recipeSets').get()]);
  const changes = [...recipes.docs, ...sets.docs].map(doc => {
    const value = doc.data(); const tags = canonicalTags(value.tags ?? value.classificationIDs);
    return { path: doc.ref.path, before: value, update: { tags, classificationIDs: tags,
      ...(doc.ref.parent.id === 'recipeSets' ? { access: { kind: value.price.kind, ...(value.price.productID ? { productID: value.price.productID } : {}) } } : {}) } };
  });
  await writeFile(argument, JSON.stringify(changes, null, 2), { flag: 'wx', mode: 0o600 });
  for (const change of changes) {
    await db.runTransaction(async tx => {
      const ref = db.doc(change.path), current = await tx.get(ref);
      if (JSON.stringify(current.data()) !== JSON.stringify(change.before)) throw new Error('Catalog changed during migration; review the backup before retrying');
      tx.update(ref, change.update);
    });
  }
  console.log(`Migrated ${changes.length} cards/sets; legacy fields and immutable versions preserved.`);
 } else if (command === 'publish') {
  // Operator IAM credentials authenticate this CLI; Firebase clients use the existing endpoint.
  const email = process.env.FIRESTORE_EMULATOR_HOST ? 'colinjianingxie@gmail.com' : execFileSync('gcloud', ['auth', 'list', '--filter=status:ACTIVE', '--format=value(account)'], { encoding: 'utf8' }).trim();
  if (!validID(argument)) throw new Error('Provide a recipe ID');
  const draft = (await db.doc(`recipes/${argument}/versions/draft`).get()).data();
  console.log(await publishRecipe(db, { email, email_verified: true }, argument, draft?.revision));
} else throw new Error('Supported commands: seed, draft, publish, migrate-tags');
