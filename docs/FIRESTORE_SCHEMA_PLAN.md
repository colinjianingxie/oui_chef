# Oui Chef catalog, adaptive cooking, and completed-dish plan

Status: core implementation completed September 17, 2026; live catalog cleanup completed September 18. See [FIRESTORE_CATALOG.md](FIRESTORE_CATALOG.md) for the current layout and search tradeoff, and [ADAPTIVE_COOKING.md](ADAPTIVE_COOKING.md) for delivered behavior and validation. The rationale below describes the original migration and deferred creator/subscription work. Legacy taxonomy/price data is removed; `minutes` strings remain for TestFlight build 5 decoding.

## Recommendation

Keep five catalog concepts: chefs, recipe sets, recipes, ingredients, and ingredient categories. Use simple tags on recipes and sets. Keep the execution graph embedded in a recipe version. Separate personal cooking progress and server billing records from shared content. Preserve explicit ownership and publication boundaries so user-created sets can be added later, while retaining top-level collections for globally discoverable sets and recipes.

Current planned scope is catalog cleanup, live cooking corrections/recovery, and completed-dish photos in the user's profile. Chef creation/editing/import interfaces, public creator APIs, pack prompt authoring, and paid marketplace implementation are deferred. Existing trusted admin imports and preview/publishing continue. Do not create empty future collections or build creator workflows as part of this work.

A field earns its place if it changes what the app displays, retrieves, validates, permits, or remembers. Avoid separately maintained metadata that only describes other metadata.

### Why `appliesTo` is a good example

Before migration, the field was in `classifications`, not `ingredientCategories`. All 12 seeded classifications had the same value: `["recipe", "recipeSet"]`. The importer, publisher, and filter chips read it, but the identical value made no useful distinction. Those documents are now removed.

The old app also had both `Recipe.tags` and `classificationIDs`. For example, spaghetti's graph had Dinner/Vegetarian/Vegan while its card had Italian/Dinner/Pasta/Beginner/Weeknight classification IDs. That gave remote and bundled browsing different metadata. One canonical set of discovery tags is simpler.

Use `tags: ["italian", "pasta", "dinner", "beginner", "weeknight"]` on that recipe and `tags: ["beginner", "essentials"]` on its set. Tags are stable, normalized strings, validated and deduplicated on import. Sets have their own editorial tags; they do not inherit every tag from every recipe.

The generic `classifications` collection, its `appliesTo`/`kind`/`parentID` machinery, and `classificationIDs` were retired September 18. Keep an approved tag vocabulary in the version-controlled catalog manifest, used by import validation and the app's curated browse filters. Public creators choose approved tags; normalize case, deduplicate, cap the list, and reject unknown values. Not every supported tag needs a filter chip. This does not provide a remotely editable, localized tag directory; add a small shared directory only when an editorial workflow actually requires it. That directory still does not need `appliesTo` when both recipes and sets support every tag. Do not scan all recipes to discover filter choices.

Diet/allergen compatibility stays in ingredient validation. A discovery tag must never authorize an ingredient or establish safety.

## Review of every current storage responsibility

| Current path or model | Why it exists | Proposed treatment |
| --- | --- | --- |
| `chefs/{chefID}` | Public identity and ownership | Keep. `name`, optional `bio`, `ownerUID`, publication status. Chef Margarita remains the starter identity. Admins manage the starter chef until a specific owner UID is assigned. |
| `recipeSets/{setID}` | Chef-owned collections and eventual subscription access | Keep. `chefID`, title, summary, status, tags, access configuration. One chef owns many sets. |
| `recipes/{recipeID}` | Small, queryable browse cards | Keep. Publisher generates this document from validated content; chefs do not maintain a second copy manually. |
| `recipes/{recipeID}/versions/{number}` | Stable published cooking instructions | Keep immutable versions. Needed to prevent an edit from changing an in-progress recipe. Embed ingredient lines and nodes here. |
| `recipes/{recipeID}/versions/draft` | Private preview before publication | Keep the existing path. It is separate from publicly readable content even when editing a published recipe. |
| `ingredients/{foodID}` | Reusable food identity and preference checks | Keep canonical names, category, composition, allergens, diet facts, alcohol information, and useful aliases/art references. No serving quantities here. |
| `ingredientCategories/{categoryID}` | Ingredient browsing and grouping | Keep a small hierarchy: `name`, optional `parentID`, optional presentation symbol. |
| `classifications/{classificationID}` | Shared labels and generic applicability rules | Replace with simple tags on recipes and sets. No replacement generic taxonomy collection. |
| `catalogAdmins/{verifiedEmail}` | Authorizes the two configured admins | Keep the existing private allowlist. Replacing it with an elaborate role system would add work without changing the requirement. |
| `users/{uid}/recipeSetEntitlements/{setID}` | Server-issued paid access | Keep the security boundary; populate only once StoreKit billing is implemented. Users cannot write these records. |
| `voiceSessions/{id}` | Server-observed voice usage and spend estimates | Keep. This is a voice connection, not a cooking session or transcript. |
| `voiceBudget/development` | Atomically reserves the shared beta allowance and connection slots | Keep for the three-session POC. Revisit provider-specific metering and account quotas when switching providers or widening the beta. |
| `voiceTesters/{uid}` | Now an explicit account block override | Missing records already allow supported signed-in accounts. Stop describing this as device enrollment. Preserve explicit blocks; no per-install records are needed. |
| `voiceMigrations/{legacyUID}` | Compatibility with the old anonymous enrollment flow | Retire the client/server migration flow before archiving these records. No new general-purpose migration subsystem. |
| Local `AppArchive` | Account-specific preferences, saved recipes, cooking snapshot, history, optional usage events | Keep local persistence and pending photo uploads. Add cloud completed-dish records and private images; live cooking sync remains deferred. |
| Proposed `users/{uid}/completedRecipes/{attemptID}` | Profile's completed-dish list | One private record per completed cooking attempt, with source recipe/version, completion date, actual servings, compact adjustment summary, and optional photo reference. |
| Proposed Storage `users/{uid}/completedRecipes/{attemptID}/dish.jpg` | Completed-dish image | Private image bytes in Cloud Storage, referenced by path from the completion document. |

Do not rename working collections merely to make their names shorter.

## Ownership and collection placement

Keep the relationship `account -> chef -> recipe sets -> recipes`, represented by explicit IDs:

```text
chefs/{chefID}                        ownerUID identifies the creator account
recipeSets/{setID}                    chefID identifies the owning chef
recipes/{recipeID}                    recipeSetID identifies the set
recipes/{recipeID}/versions/{version}  content belongs to that recipe
```

Recipe cards also retain a generated `chefID` for authorization and creator queries. Validate that it matches the owning set. Do not treat client-supplied ownership fields as proof of access.

`recipeSets` stays top-level because sets are discoverable products with independent links and subscription references. Query all published sets directly; add a `chefID` filter for a chef profile. Keep one owner account per chef and one set per recipe initially. A user can cook and create using the same Firebase account. Granting creator ownership does not grant platform admin access.

Nesting under `chefs/{chefID}/recipeSets/{setID}` could also scale. Firestore's collection-group query can find all `recipeSets` without loading chefs first. It requires suitable group indexes and rules. Neither layout needs to scan or index chef documents to search set content; this choice is about access patterns and reference simplicity. See [collection-group queries](https://firebase.google.com/docs/firestore/query-data/queries) and [their security rules](https://firebase.google.com/docs/firestore/security/rules-query).

Versions remain nested because they are read in the context of a selected recipe. Do not create parallel top-level and nested copies of sets.

## Deferred allowance for user-created sets and recipes

Retain chef ownership, set references, private recipe drafts, immutable publications, and access configuration in the schema. These are enough to allow a creator workflow later. Continue using the current trusted operator importer. Public creator endpoints, enrollment screens, and recipe editors are not part of the current implementation scope.

When that work is explicitly started, the backend must validate untrusted imports itself, verify ownership, reject stale draft publication, and support private preview and withdrawal. A client-supplied validation marker must never authorize publication.

The shared ingredient catalog stays curated. Creators reference existing food IDs; new-food submissions need validation/review before entering the shared catalog. A creator cannot alter the allergen or composition information used by everyone else's recipes.

### Future editing of a published set

When creators can edit live sets, add `recipeSets/{setID}/private/draft` for unpublished metadata and pack guidance. The top-level set document remains the currently published sales/browse card. Publish the draft revision atomically into that public card and the private active guidance document. Set status remains draft/published; do not add review states before a review workflow exists.

Each recipe publishes independently under its set. Adding a new recipe means validating and publishing that recipe before it appears in the live set; do not expose its draft through a public membership list. If all-or-nothing releases of several recipes become necessary, add a release manifest then. Avoid an unbounded array of all recipe IDs on the set; the recipe collection is queried by `recipeSetID`.

Keep published pack guidance in `recipeSets/{setID}/private/guidance`, readable by the authorized backend and its creator/admin, rather than embedding it in public cards. A voice connection retains the selected guidance text and revision for its lifetime. Pack text can affect style and explanations; executable permissions and safety/progress checks remain in code.

The first creator release should use the same structured JSON format already chosen. A drag-and-drop recipe editor, team permissions, recipe membership in multiple paid sets, and automatic extraction from URLs/videos are later features.

## Ingredient model

### Keep identity separate from a recipe's use of it

Example category documents:

```text
ingredientCategories/vegetables   { name: "Vegetables" }
ingredientCategories/alliums      { name: "Alliums", parentID: "vegetables" }
ingredients/garlic                { name: "Garlic", categoryID: "alliums", ... }
```

The ingredient document describes garlic. A recipe ingredient line describes how much garlic this batch needs:

```json
{
  "id": "sauce_garlic",
  "foodID": "garlic",
  "name": "Garlic, minced",
  "amount": 3,
  "unit": "clove",
  "scales": true
}
```

Both IDs are useful: the same food can be used separately in sauce and garnish. Preparation/display text belongs to the recipe line; canonical identity belongs to the ingredient catalog. Do not create separate food documents for every chopped/minced/cooked state.

Keep these ingredient fields because the app already uses them:

- `allergens` and `constituents`: inspect an ingredient and its known components, including sauces and substitutions.
- `compositionKnown`: an empty allergen array cannot distinguish known absence from missing product information. Unknown information must not become an affirmative safety claim.
- `dietaryTags` and the currently used alcohol trait: support dietary restrictions and alcohol avoidance. Do not create a vocabulary of unused traits.
- `aliases`: help users find an ingredient under familiar names.
- `spriteAsset`: optional; fill it when the supplied sprites exist. Images themselves belong in assets or object storage, not Firestore documents.

`categoryAncestors` is worthwhile generated duplication: it allows a Vegetables query to include garlic without reading every descendant category and ingredient. The importer derives it from `categoryID`; authors should not enter both. The current field includes the leaf category too, and that behavior should remain documented.

Category membership is for navigation. A dislike of one ingredient does not imply a dislike of its siblings, and categories are not allergen rules.

## Recipes and publication

### Browse card versus cooking content

Keep cards small: title, subtitle, chef/set references, status, tags, style, estimated time, and published-version pointer. `hasDraft` remains useful for the private preview list. Card fields such as servings should remain only if browsing/selection actually needs them; otherwise fetch them with the graph.

Keep `chefName` on cards as a generated display copy if it avoids fetching a chef document for every card. `chefID` is still the ownership/reference key. Controlled duplication for an actual read path is useful; competing authoring sources are not.

Replace human-formatted `minutes` strings with numeric estimates and format them in the app. For example, active minutes plus a total range supports both “3–4 hr” and duration filtering. These are authored estimates: adding all node durations is wrong when tasks overlap or proofing varies.

Store ingredients, tools, nodes, permitted ratios, source, and canonical tags inside the immutable recipe version. Keep the draft's concurrency/integrity checks and atomically update the published card/version pointer after validation.

Firestore security rules cannot hide individual fields in an otherwise readable document. That is a concrete reason to keep private drafts and protected instructions separate from public cards. See [Firebase field access rules](https://firebase.google.com/docs/firestore/security/rules-fields).

Unpublishing a set must also remove its cards from public browsing through a trusted operation. Protected graph reads must independently check set access. Keep the current separation until that operation exists; a parent status alone does not make child queries disappear. Already downloaded cooking snapshots cannot be recalled by changing a publication flag.

### Preserve the executable graph without expanding the database

There is no need for global `actions`, `steps`, `ingredientStates`, `timers`, or `checkpoints` collections. These are structures inside a recipe or cooking session.

Keep the existing node fields that power the engine:

- Stable ID and `dependsOn` for parallel work and prerequisites.
- `inputs`/`outputs` for state transformations and consumed-ingredient checks.
- `instruction` and `criterion` for what to do and how to assess completion.
- Optional duration, first check-in time, recheck interval, and authored coaching cues.
- Tools as information and resource constraints, with no manual equipment-verification gate.

Keep action/wait/checkpoint kinds because the current engine uses them. There is no benefit in rewriting the engine merely to save an enum. Defer general branching, reusable subrecipe functions, and variation patch languages until a real recipe needs them.

For scaling, keep the supported linear/fixed behavior and per-recipe maximum servings. Keep explicit bounded ratio controls and approved substitutions with instruction changes. Add another scaling rule only for a recipe that needs and tests it. The language model proposes; deterministic code calculates, validates, and applies a confirmed change. Changing an unconsumed amount and adding a recovery ingredient to an existing mixture are distinct operations; support the latter through the session recovery flow below.

## Cooking state and voice

### A cooking session is the assistant's memory

Keep a session's selected recipe/version, effective recipe and ingredient snapshot, servings, manual preparation checks, active/completed nodes, timer deadlines, last/pending check-in, delivered cues, revision, and guidance-pause state.

The effective recipe snapshot contains confirmed substitutions, quantities, and any validated recovery steps. Keep a bounded correction history and one pre-change snapshot for pending/last reversible edits; a generic patch language and event-replay system are unnecessary. Ignore obsolete `confirmedTools` through compatible decoding. Keep equipment preferences from onboarding to hide owned everyday tools; tool verification is not required.

The session must survive ending a voice connection. Reopening voice reads the current cooking state and asks a relevant question. Elapsed time triggers a readiness check, never automatic completion. Guidance pause and real-world timer progress remain separate. A specific user report can complete the relevant active node without a confirmation popup.

Continue saving this state locally first. Do not write Firestore every timer tick or every audio fragment. If cross-device resume becomes a requirement, add one owner-private snapshot document per cooking session, sync meaningful transitions, and explicitly resolve which device controls that session. Preferences and saved-recipe sync can ship before that complexity.

### Live corrections, mistakes, and taste recovery

The current app only selects a recipe when no cooking session exists, disallows substitutions after cooking starts, and rejects ratio edits once ingredients are consumed. Those guards protect physical state, but the planned product needs explicit recovery operations instead of a general rejection.

Keep the published recipe/version immutable and identify it as the source. Treat the active session's effective recipe as a mutable, validated copy. Give a cooking attempt its own stable ID and increasing revision. A voice connection can outlive changes to the active recipe; it is not the cooking attempt ID.

Distinguish these user intents:

| Request | Result |
| --- | --- |
| "Go back" / "Repeat that" | Revisit an instruction without undoing cooking progress, restarting heat, or resetting a timer. Clarify if the user means a correction. |
| "I said done, but I haven't done it" | Correct the recorded step only after checking dependent steps. Reconcile any downstream work already performed; do not blindly rewind an entire branch. |
| "I used twice as much lime" | Record the actual quantity as a user-reported fact, preserving known/unknown information. Then evaluate recovery separately. Do not reject or erase an honest report because it is outside the recipe's recommended ratio. |
| "It's too salty/sour/thick" | Ask only for missing facts needed to decide: what has already been added, approximate amount, current state, and available ingredients. Propose a bounded, recipe-appropriate adjustment and a new sensory check. |
| "Actually, let's make a different recipe" | Explicitly select a new source recipe and cooking attempt within the ongoing conversation. Preserve the previous attempt as unfinished and keep outstanding timers associated with it until the user resolves them. Do not transfer completion/ingredient checks automatically. |

Recovery sequence:

1. Read current state and record what the user reports happened. Distinguish ingredients available, prepared, and already incorporated; record known incorporated amounts as facts, with uncertainty explicit.
2. Identify what can still change. Preserve the selected source recipe/version and irreversible physical actions.
3. Calculate a proposal using supported arithmetic, compatible units, recipe-specific ranges, availability, allergy/diet checks, and batch/equipment limits. Actual mistaken amounts can be outside those ranges; recommended further actions still need validation.
4. Explain the concrete addition or next action and its effect. Wait for confirmation before changing the plan. Never equate accepting a plan with physically adding the ingredient.
5. Apply the confirmed plan to the session copy, revalidate dependencies, retain unrelated progress and timer deadlines, and update the agent context. New physical additions get an explicit action/readiness step; amounts become incorporated only when the user reports doing it.
6. Check the result and adjust again if supported. When a safe, supported correction is unavailable, clarify or offer a feasible restart rather than inventing a guaranteed rescue.

For the starter recipes, use a small set of authored recovery options: measured ratio/batch adjustments for cocktails, supported additions and sensory checks for sauce, and conservative dough corrections tied to the recipe's structural bounds. Availability and taste are not inferred from ingredient category alone. Do not use a universal rule that one taste always cancels another.

New ingredients or changed product identities require the existing manual ingredient/label check for the affected items. Keep unchanged confirmations and the voice conversation; do not restart the entire initial preparation screen. Allergy/diet restrictions must be re-evaluated against the effective ingredients, including reported mistakes. An incompatible ingredient already mixed in cannot be made acceptable by editing metadata or adding a balancing ingredient.

Reversible application-state edits may be restored from the saved pre-change snapshot only if no subsequent physical action makes that restoration false. Timers retain real elapsed time. Undoing a recorded quantity is a correction of the record, not subtraction from a pan. Every confirmed mutation increments the revision, invalidates old proposals, and rejects delayed tool responses from prior state/recipe/account generations.

If switching recipes, load and authorize the new graph before changing the active attempt, then change the specialist context without ending the user's conversation. Failure keeps the existing attempt intact. Timers from a parked attempt remain explicit and visible; the agent must not misattribute them to the newly active recipe. The first implementation is one active recipe with retained outstanding timers, not a general multi-dish scheduling system.

Keep recovery details in the cooking snapshot and a compact adjustment summary for the completed-dish record. Do not write personalized changes back to the shared catalog, use them as billing events, or claim the resulting variation is a chef-published recipe.

### Completion, photo capture, and profile history

On confirmed dish completion, save the completed attempt locally and offer a warm closing prompt once:

> "You made it! Would you like to take a picture for your cooking history?"

Show a native Take photo action, preview/retake/use controls, and Skip for now. The user explicitly opens the camera and grants camera permission. Offer Add photo later from the profile if they skip, cancel, or deny permission. A photo is not a condition of recipe completion. Optional library selection can use the native picker. Reconcile audio interruptions on return to the app; capture must not discard the cooking result or silently end unrelated timers. See [Apple camera capture](https://developer.apple.com/documentation/uikit/uiimagepickercontroller?changes=latest_major).

Trigger this on completed cooking, not on every microphone stop, pause, disconnect, app background event, or abandoned recipe. A completion ID and persisted prompt state prevent duplicate records and repeated invitations after reconnect/relaunch. If the user returns to cooking during wrap-up, invalidate the provisional completion and reconcile any queued history write so the profile does not show an unfinished dish as complete.

Store completed-dish metadata in `users/{uid}/completedRecipes/{attemptID}`:

- Source `recipeID` and `recipeVersion`.
- Display snapshots such as title and chef name.
- Actual servings and completion time (Firestore Timestamp); preserve the local completion time across offline upload.
- Compact adjustment summary, including confirmed substitutions and recovery actions that were actually performed.
- Optional `photoPath`, populated only after a successful image upload.

Use the cooking attempt ID rather than the recipe ID, so cooking spaghetti three times produces three separate memories. The full effective recipe/progress remains in the local history initially; the cloud profile record is deliberately small. Do not place all history entries or image bytes inside the user's root document.

Store one compressed dish image initially in Cloud Storage at `users/{uid}/completedRecipes/{attemptID}/dish.jpg`. Re-encode a bounded image suitable for the profile, exclude unneeded location metadata, and enforce file size/type and owner-UID checks. Store its object path, not a public share link. Fetch through authenticated Storage access. The photo remains private and is not sent to a vision model as part of this feature. See [Firebase Storage authorization and validation](https://firebase.google.com/docs/storage/security/rules-conditions).

Save locally first, show pending upload when offline, and retry using the same account/attempt/object identities. Storage and Firestore do not form a cross-service atomic transaction: upload the image, then attach its path to the history document; retry safely if either operation fails. Guard late callbacks and queued uploads across sign-out/account changes. Guest results stay local until the user signs in and the app's account-adoption flow applies. Completion saving must not depend on optional analytics consent.

In Profile, show Completed recipes as paginated cards ordered by completion time, with photo/placeholder, recipe title, and date. Detail shows servings and what changed. Include add/replace/remove photo and delete entry; delete associated Storage objects and pending uploads as well. Account deletion must remove both profile records and images through a retryable cleanup path. Preserve local ended/unfinished history separately; it does not enter the completed list.

Cloud completed-history/photo sync is in scope even though live cross-device cooking synchronization remains deferred.

### Specialist behavior without an agents database

Keep the shared contract and the three style prompts in version-controlled backend files. Recipe `style` selects the specialist; discovery tags do not implicitly choose permissions or agent behavior. The first creator release uses the supported pasta, bread, and tequila specialists. Additional cooking domains require reviewed guidance and compatible recipe validation before publication; arbitrary tag names cannot enable a new specialist.

For chef packs, compose shared rules + style guidance + reviewed pack guidance + current cooking state. Introduce private per-set guidance when chef pack authoring ships, rather than storing prompts on public sales cards. Pin the guidance revision for a voice session. Chef-supplied text cannot override preparation, entitlement, allergy, quantity, or progress checks.

Do not store xAI/OpenAI assistant IDs in canonical recipes. Provider/model configuration belongs to the voice backend; provider and model identifiers belong in usage records. A provider change should leave food IDs, graphs, sessions, and ownership intact.

## Accounts, subscriptions, and measurement

### Account data

The app currently saves preferences, bookmarks, and cooking history locally per account. Firestore does not currently sync them.

Add private `users/{uid}/completedRecipes/{attemptID}` records and Storage photos for the requested completed-dish profile. Private `users/{uid}` preferences and `users/{uid}/savedRecipes/{recipeID}` bookmarks can follow separately. Keep bounded preferences together; store growing bookmark/history lists separately. Sync meaningful changes, preserve local guest/account separation, and extend account deletion to remove new cloud records and files. Keep device-only settings, such as keeping the screen awake, local.

Keep allergies, dietary constraints, alcohol avoidance, disliked ingredient IDs, taste preferences, and guidance detail distinct. Do not store pantry quantities merely because the user confirmed ingredients for one recipe. Personal edits belong to the session; the shared recipe remains unchanged.

User-editable documents must not contain writable admin, voice-block, or purchase-access fields. Existing admin/entitlement records remain independently protected.

### Recipe-set access

Free set: an explicit free access kind. No zero-price/currency/null-interval/null-product boilerplate is needed in the compact format.

Subscription set: subscription access kind and its StoreKit product ID. When checkout is implemented, obtain the offered/localized price and subscription details from StoreKit; Apple's [`displayPrice`](https://developer.apple.com/documentation/storekit/product/displayprice?changes=_9) supplies the storefront-localized price label. Firestore stores the mapping and server-verified access, rather than a separately editable copy of the price. Legacy USD cents fields were removed in the September 18 cleanup.

Treat paid publication as a separate release gate: a creator's proposed price does not create an App Store product or grant purchasing access. The platform provisions and approves the product mapping. Verify purchases on the backend, bind them to the signed-in account, process renewal/expiry/refund/revocation events idempotently, and restore access after reinstall. Honor the verified access period when auto-renewal is canceled; handle any supported grace period explicitly.

Independent recurring pack purchases require deliberate subscription-group setup: Apple permits only one subscription in a group at a time, while subscriptions in different groups can be held and billed separately. Monthly/yearly options for the same pack belong together; independently purchased packs need separate groups under this model. Start with a small number of platform-configured paid packs, and evaluate product provisioning and creator payouts before opening paid creation broadly. See [Apple's subscription guidance](https://developer.apple.com/app-store/subscriptions/). Do not silently change the chosen per-pack recurring business model to one app-wide subscription.

Keep one set reference per recipe for now. Do not introduce many-to-many pack membership until a recipe actually needs sale through several sets. If that requirement arrives, represent membership separately instead of copying the recipe graph.

### Usage and spend

Keep three responsibilities distinct:

1. Cooking progress: personal functional state needed to resume.
2. Voice ledger: server-observed provider usage, account, connection status, timestamps, and estimated cost. It enforces spend controls independently of optional analytics.
3. Product analytics: opted-in events such as recipe opened, preparation completed, cooking completed/abandoned. Existing optional usage events are local; they do not yet provide a centralized product dashboard.

Keep raw audio, transcripts, and allergy lists out of the usage ledger. When implementing centralized analytics, choose the existing Firebase analytics capability instead of a Firestore document for every interaction. Verify the collection/consent configuration separately before enabling it.

Record provider/model and the estimation rate version when metering changes. Estimates are not provider invoices. Preserve atomic reservations and explicit account blocks. Remove old `activeID`/`activeUntil` compatibility fields only after no deployed backend revision relies on them.

The current `expiresAt` field marks intended voice-log retention; it does not delete documents by itself. Verify and enable the corresponding Firestore TTL policy as an operational follow-up. Do not delete the active budget ledger with usage-log retention.

## Retrieval and indexes

Design indexes around actual queries:

- Published recipe cards, optionally for one set or one discovery tag, paginated by title.
- Recipe title/keyword search, optionally inside one set.
- Published recipe sets, paginated.
- Ingredient name/alias search or one category, paginated.
- Private draft list and direct authorized detail/version reads.

For the POC, do not store `searchTokens`. Typed and voice search match existing metadata in Swift while scanning authorized Firestore pages. Keep normal browsing paginated and full recipe graphs lazy-loaded. This trades extra metadata reads for a smaller schema; move matching to a text-search index when catalog size warrants it.

Firestore filters publication status, set membership, and one tag/category before Swift applies the text match. The scan continues past empty pages, so search does not silently miss later matches. Multi-tag intersection and ranked/fuzzy search remain deferred. See [Firestore query limitations](https://firebase.google.com/docs/firestore/query-data/queries).

Keep only composite indexes used by supported screens/queries, including still-supported old clients. Do not create every combination of hypothetical filters. Exempt graphs, long prompts, and unqueried snapshots from indexing; the current version `recipe` map already has an exemption. See [Firestore best practices](https://firebase.google.com/docs/firestore/best-practices).

Bounded recipe structures fit embedded arrays/maps. Growing histories and logs belong in separate documents if cloud storage is introduced. Enforce size limits during import rather than discovering them during publication. See [Firebase data structure guidance](https://firebase.google.com/docs/firestore/manage-data/structure-data).

## Rollout plan

1. **Consolidate discovery metadata.** Map classifications and graph tags to one reviewed canonical tag list. Preserve useful discovery labels; move diet/alcohol claims to their actual ingredient-derived checks. Update imports, validation, filters, voice search, and offline fallback together.
2. **Trim unused authoring fields.** Remove `appliesTo` and generic classification ancestry from the new format; omit empty optional fields. Keep ingredient hierarchy, graph validation, draft revisions, and query-serving generated fields. Add numeric duration estimates and compact set access metadata where the new client uses them.
3. **Preserve supported TestFlight clients.** The initial migration backed up data and temporarily dual-wrote old/new fields. September 18 cleanup targets build 5 or newer; older builds require updating. Retain formatted `minutes` because build 5 still requires it when decoding. Test cleanup against the emulator and preserve existing immutable publications.
4. **Migrate without touching active cooking snapshots.** Compare IDs, recipe counts, tags, ownership, and access before/after. Keep users, admin access, entitlement records, budget totals, voice blocks, and historical usage intact. Publish new content versions for material content-format changes.
5. **Verify the real boundaries.** Public users cannot read drafts; paid graphs remain protected; stale draft publication fails; ingredient changes still trigger preference checks; ordinary scaling cannot erase incorporated ingredients; recovery records actual additions; timers survive corrections/pause/relaunch; voice resume uses revised state; remote and bundled search agree on tags. Check correction dependencies, failed recipe switches, stale/repeated tool calls, and preserved timers from an unfinished attempt. Verify completion invitation deduplication, cancellation/permission denial, offline photo retry, separate repeated cooks, private image access, account switching, and entry/account deletion.
6. **Remove obsolete data.** Completed September 18: removed legacy classification documents/fields, set price metadata, duplicate published drafts, and five unused indexes; backed up every changed document and checked the retained catalog. Retire anonymous voice migration separately. Cloud preferences/bookmarks, centralized analytics, chef pack guidance, and StoreKit checkout are subsequent feature increments, not prerequisites for this cleanup.

The result should be fewer independently authored facts and fewer special cases, while retaining the structured cooking state that makes Oui Chef useful.

## Feature sequence after schema migration

| Phase | Deliverable | Completion condition |
| --- | --- | --- |
| 1. Catalog cleanup | Canonical tags, lean fields, generated cards, compatible readers/writers | Existing cooking and private-preview flows work with old and new data during rollout. |
| 2. Adaptive cooking | Mutable session recipe, correction/undo semantics, reported actual quantities, bounded recovery actions, recipe switching within a conversation | Published content stays unchanged; dependent work and physical ingredient state remain truthful; stale actions fail; unaffected timers and progress survive. |
| 3. Completed dishes | End-of-cook photo invitation, native capture, local persistence, private Storage upload, Firestore completion records and profile cards | Photo is optional; retry/reconnect creates no duplicate completion; repeated cooks remain distinct; records/files are private and deletable. |
| Later, separately scoped | Cloud preferences/bookmarks, centralized analytics, additional cooking styles, richer search or multi-device cooking | Each extension has a real product use case and its own account/query/runtime verification. |
| Deferred; schema support only | Creator authoring, public JSON import APIs, collaborative editing, pack prompt editing and paid marketplace | Existing ownership, set IDs, publication/version paths and entitlement boundaries allow later implementation without building these workflows now. |

The xAI-to-OpenAI voice migration is an independent workstream and can happen before creator or paid-pack features. Reuse the current provider boundary, update provider-specific audio/events and metering, and verify interruption, reconnection, tool confirmations, and simultaneous-account isolation. No catalog reorganization is required. Foreground voice remains the first release scope; lock-screen voice is separate.

Retain the three free Chef Margarita starter recipes, manual ingredient preparation, no required tool verification, compact preference screens, personal return greetings, and sensory check-ins throughout every phase. Seeded or imported recipes still need cooking review; schema validation alone does not establish that a recipe works well in a kitchen.
