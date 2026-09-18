# Firestore catalog

See [adaptive cooking and dish history](ADAPTIVE_COOKING.md) for the September 17 schema migration, session corrections, private photos, and compatibility boundaries.

## Data layout

| Path | Purpose |
| --- | --- |
| `chefs/{chefID}` | Public display profile and an explicitly assigned Firebase `ownerUID`. One chef can own many sets. |
| `recipeSets/{setID}` | Chef reference, name, canonical tags, publication status, and compact free/subscription access. |
| `recipes/{recipeID}` | Lightweight card metadata, chef/set references, canonical tags, published version, and whether an owner-only draft exists. |
| `recipes/{recipeID}/versions/{version}` | Immutable published cooking graph. Read separately when opening a recipe. |
| `recipes/{recipeID}/versions/draft` | Editable graph visible only to the owning chef account or a catalog administrator. Editing a live recipe does not replace its published graph. |
| `ingredients/{foodID}` | Shared ingredient identity, composition, allergens, diet metadata, category ancestry, aliases/search tokens, sprite key. |
| `ingredientCategories/{categoryID}` | Hierarchical ingredient browsing categories. |
| `classifications/{classificationID}` | Legacy directory retained for installed clients; new filters/imports use the version-controlled tag vocabulary. |
| `users/{uid}/recipeSetEntitlements/{setID}` | Server-issued subscription access and expiry; users cannot grant themselves access. Purchases remain a later StoreKit integration. |

## Publication and access

Public clients read published set/recipe cards. Full cooking graphs additionally require the containing set to be published and either free or covered by a valid server-issued entitlement. Owners may preview their own drafts; catalog administrators may preview and publish all drafts. Public access to the `draft` version is denied even when the recipe also has a published version.

Authoring uses a trusted operator import command. It validates graphs and ingredient dependencies with the same Swift engine as the app, then checks approved tags and ownership references. The iOS preview switch is available to catalog administrators; the rules and publication endpoint also support an ordinary chef’s assigned owner UID. The app cannot directly write catalog documents or entitlements. Its admin draft preview includes a Publish button that calls an authenticated backend endpoint. The endpoint checks ownership/admin access, the exact reviewed draft revision, and validated import data before publishing. The voice ledger stays inaccessible to clients.

A new draft starts private. Publishing creates a numbered immutable version and atomically updates the public card. Editing that recipe writes only the private draft; the public card and published graph remain unchanged until the next publication. Unpublishing blocks new public reads; it cannot recall copies of content already legitimately downloaded.

## Loading

Browse recipe-set and recipe-card pages with Firestore document cursors; never download every cooking graph to show the home screen. Opening a card fetches its current authorized graph and referenced ingredient/constituent records. Ingredient selection searches and paginates independently. The app keeps an active recipe plus its ingredient metadata in the account's cooking-session snapshot so timers and guidance survive a network interruption.

The bundled three public starter recipes provide an explicit offline fallback. They are not a fallback for inaccessible paid or draft content. Signing out clears in-memory draft browsing state and returns to the account-isolated kitchen. No draft is included in the bundled catalog.

## Starter content and pricing

The initial free `kitchen_essentials` set belongs to **Chef Margarita** (`chef_margarita`). The display name replaces Anonymous Chef throughout the app. The starter chef is managed by the two catalog administrators. Admin access uses a private allowlist of verified Firebase sign-in emails: `colinjianingxie@gmail.com` and `wonmargarita@gmail.com`. This also supports an administrator who has not signed up yet, without creating passwords or Firebase users. Unverified email/password accounts do not qualify. Ordinary chef ownership remains a separate Firebase UID.

Future paid sets use recurring subscriptions, as previously selected. Canonical access stores the kind and StoreKit product ID; legacy USD price fields remain for installed clients. StoreKit product configuration, purchase verification, localized prices, renewals, and refunds must be connected before sales are enabled. Paid graph reads fail closed without an entitlement.

## Query and security references

Firestore queries must satisfy the rules for every possible returned document; client-side filtering cannot protect drafts. See [Firestore secure queries](https://firebase.google.com/docs/firestore/security/rules-query), [cursor pagination](https://firebase.google.com/docs/firestore/query-data/query-cursors), and [Swift Codable mapping](https://firebase.google.com/docs/firestore/solutions/swift-codable-data-mapping).

## Operations

From the repository root, with the existing gcloud operator account authenticated:

```sh
node backend/catalog-admin.mjs seed catalog/seed.json oui-chef-dev-20260914
node backend/catalog-admin.mjs draft /path/to/recipe-import.json oui-chef-dev-20260914
```

Seed is create-only and safe to repeat; existing edits and disabled admin entries are preserved. To add trusted chefs/sets, extend the seed manifest and rerun it. Set prices use integer USD cents; subscriptions require a StoreKit product ID. Updating existing chef/set/pricing records remains a trusted Firestore-console operation in this first release. Before retiring a published set, also unpublish its recipe cards: public cards are intentionally queryable by their own status, while graph access independently checks the set status. Active cooking sessions keep their already-authorized snapshot.

The import file has two fields: `recipe` (a complete graph in the format used by `OuiChef/Core/Resources/recipes.json`) and `tags` (approved normalized strings; legacy `classificationIDs` is also accepted). Referenced ingredients must already exist. The import command accepts up to 300 ingredients including constituents and alternatives. It keeps the public card unchanged for an existing recipe. In the app, sign in as either verified administrator, enable **Preview drafts**, open the draft, test it, then choose **Publish this draft**. Refresh the library after an email is newly verified.

Do not edit a validated draft directly in the console; re-import it so validation and its revision match. Published versions are immutable through supported commands. Chef ownership changes are separate from recipe imports. No service-account key is needed or stored on the iPhone; the operator command uses a short-lived gcloud token, and the deployed service uses its existing runtime identity.

## Verification

```sh
swift test
firebase emulators:start --only firestore,auth,storage --project demo-ouichef
# In another terminal:
FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 node backend/catalog-admin.mjs seed catalog/seed.json demo-ouichef
FIRESTORE_EMULATOR_HOST=127.0.0.1:8085 npm test --prefix backend
```

Emulator tests cover public queries, both administrators, unverified-email rejection, chef ownership, private draft versions of published recipes, expired subscriptions, denied self-entitlements and catalog writes, stale drafts, and immutable published versions. The iOS UI tests use `--auth-emulator`; release builds cannot enable that path. Firestore uses memory caching; full graph reads explicitly require server authorization. Session snapshots remain account-isolated on disk for offline cooking.

Search uses bounded name/title/alias/category prefixes and individual words, not fuzzy full-text ranking. Recipe and ingredient results use cursors (12 cards or six ingredient choices per page). Ingredient searches reset the category filter; category selection resets search. Ingredient category documents are small and loaded together; introduce pagination if that directory becomes large. StoreKit checkout and chef authoring remain deferred. Private completed-dish image uploads are implemented.
