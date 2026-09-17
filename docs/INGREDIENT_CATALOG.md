# Ingredient catalog and preparation

The Firestore implementation supersedes the original delivery roadmap below; see [catalog architecture and operations](FIRESTORE_CATALOG.md). Recipe and ingredient pages now load from Firestore; bundled JSON remains the seed and offline starter fallback.

## Ingredient model

The three free Chef Margarita recipes reference one shared ingredient library: **66 foods in 31 categories**. Recipe quantities and preparation names belong to each recipe; identity, classification, composition, aliases, preferences, and artwork belong to the shared food.

Files:

- `OuiChef/Core/Resources/ingredients.json`: canonical foods and category tree.
- `OuiChef/Core/Resources/recipes.json`: recipes with `foodID` references, quantities, execution graphs, and explicitly supported substitutions.
- `OuiChef/Core/IngredientCatalog.swift`: catalog validation, category navigation, search, and ingredient preference checks.

### Preparation flow

1. **Overview:** recipe, serving size, and the three preparation areas.
2. **Preferences:** review allergies, disliked ingredients, dietary style, and any ingredient conflicts. A conflicted recipe can enter preparation so an available substitution can resolve it.
3. **Ingredients:** grouped overview, bulk confirmation, expandable quantities, individual selection, product-label review, and supported substitutions.
4. **Amounts:** change servings or supported ratios; preview applicable taste preferences. Recommended kitchen items are informational and require no confirmation.
5. **Ready:** confirmed amounts and a choice to cook with or without voice.

Tools remain in the execution graph to prevent two simultaneous tasks claiming the same pan or appliance. They no longer participate in manual readiness. The agent directs users to ingredient preparation; it cannot tick off ingredients or bypass the manual review.

The ingredient picker uses search, category filters, and six items per page. Regular-size preference screens fit without scrolling on the tested iPhone 14; scrolling remains available for larger text and smaller available heights.

## Identity and classification

Example:

```json
{
  "id": "garlic",
  "name": "Garlic",
  "categoryID": "alliums",
  "aliases": ["garlic clove"],
  "allergens": [],
  "constituents": [],
  "compositionKnown": true,
  "dietaryTags": ["Vegetarian", "Vegan"],
  "traits": [],
  "spriteAsset": "ingredient_garlic"
}
```

IDs are permanent and independent of display names, category placement, recipe pack ownership, and language. Preserve the existing IDs when editing the library. A recipe-local ingredient ID such as `sauce_salt` identifies a particular use of the canonical food `salt`; the same recipe can also use `salt` for its pasta water.

Categories are records with `id`, `name`, `parentID`, and a fallback SF Symbol. Current roots:

| Root | Examples of descendants |
| --- | --- |
| Produce | Vegetables → Alliums, Roots, Leafy greens, Fruiting vegetables, Cruciferous; Fruit → Citrus, Orchard fruit, Berries; Herbs; Fungi |
| Pantry | Grains, Baking, Seasoning, Oils, Legumes, Nuts/seeds, Sauces |
| Dairy & eggs | Milk products, Cheese, Eggs |
| Protein | Meat, Seafood |
| Drinks | Spirits, Water & ice |

Each food has one primary category. Cross-cutting properties belong in metadata, not duplicate food records. For example, an ingredient can be in Pantry and have a soy allergen. Categories organize browsing; they never determine whether food suits a user's diet.

Validation rejects duplicate IDs, missing references, category cycles, and ingredient-composition cycles. Recipe validation also checks alternative references and execution-graph nodes.

## Preferences and substitutions

- **Allergies:** inspect the ingredient and every declared constituent. Unknown composition is unresolved when allergies are selected. A checkbox cannot override a known conflict or fill in unknown composition.
- **Dietary rules:** check ingredient metadata and constituents, independent of recipe marketing tags. Gluten-free and dairy-free checks consider relevant allergens and unknown composition. Vegetarian/vegan checks need explicit tags.
- **Alcohol:** follow ingredient traits, including constituents.
- **Dislikes:** store canonical food IDs; surface a note wherever that food appears, including a compound ingredient. These are nonblocking taste preferences.
- **Taste:** only recipe-authored ratio options can suggest a change. Currently sauce salt and margarita sweetness have mappings. The user sees quantities before applying them. Unsupported spice changes and baking changes are not invented.

Substitutions are recipe-specific. The first example is dry wheat spaghetti ↔ rice spaghetti at the same dry weight, with package-based cooking instructions. Selecting it clears that ingredient's confirmation, product-label confirmation, and preparation completion. The actual recipe snapshot and voice context carry the choice. No substitution is allowed after cooking starts. There is no generic “replace any flour” rule.

These are generic ingredient descriptions, not verified branded-product records. A future product record must carry its actual label, composition, source, and review status. Continue asking users to inspect packaging and cross-contact information. The FDA distinguishes ingredient labeling from cross-contact risks: [Food allergies: read the label](https://www.fda.gov/consumers/consumer-updates/have-food-allergies-read-label). The catalog is not a certification that a particular product is safe.

## Sprites

Supply transparent square PNGs, preferably 512 × 512, named by `spriteAsset`, for example `ingredient_garlic.png`. Add them to matching image sets in `OuiChef/Assets.xcassets`. The app uses an existing sprite when available and a category icon otherwise. Artwork is decorative; names and quantities remain accessible text. A sprite change does not alter ingredient identity.

## Catalog delivery and future work

Firestore is now the editorial source for shared ingredients and categories. The app queries six ingredients per page and fetches a recipe’s referenced foods and constituents when opening it. Active sessions retain a validated ingredient snapshot for offline cooking. See [Firestore operations](FIRESTORE_CATALOG.md) for the seed/import commands, publication rules, ownership, and pricing.

Structured recipe imports already validate with the shared Swift engine and stage a private draft. Verified catalog administrators can preview and publish it from the app. Unknown food IDs must be resolved before import; chef wording and quantities remain recipe-specific. Published versions stay immutable through supported operations.

Still deferred: chef-facing authoring screens, StoreKit subscriptions, a branded-product review workflow, remote sprite delivery, and automatic metadata generation. Keep aliases and stable IDs as the library grows. Add product provenance, localized names, review timestamps and cross-contact status only with reliable data and a consuming feature. Retired ingredient IDs must remain resolvable by older sessions.

## Validation

- 18 Swift core tests cover recipe graphs, ingredient composition/category validation, dietary and allergy checks through constituents, nonblocking dislikes, supported substitutions, unchanged quantities, re-confirmation, archive compatibility, and bounded taste suggestions.
- 12 local backend tests pass, including Firestore emulator rules and a fake voice provider; no xAI credit was used.
- The iPhone 14 / iOS 18.4 UI flow exercises preference editing, ingredient search and dislike persistence, pasta substitution/restoration, bulk selection, label gating without tool verification, amount adjustment, cooking, and pause/relaunch.

The original ingredient UI shipped in build 3; the Firestore implementation is uploaded as TestFlight **1.0 (4)**. The matching backend is `oui-chef-voice-00007-lcd`. See [release details and SDK symbol warnings](TESTFLIGHT.md). Direct installation on Colin’s iPhone was not part of this release.
