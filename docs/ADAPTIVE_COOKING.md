# Adaptive cooking and completed dishes

Implemented September 17, 2026. Chef authoring, paid packs, cross-device live cooking, and the OpenAI provider migration remain deferred.

## Catalog

- Recipe/set `tags` use the approved vocabulary in `OuiChef/Core/Resources/catalog-tags.json`. Imports normalize, deduplicate, and reject unknown tags. The app queries tags directly; safety still comes from ingredients.
- Recipe versions embed the executable graph and optional authored `recoveryOptions`. `totalMinutes` and optional `maximumMinutes` drive displayed time estimates.
- Set `access` is `{kind: "free"}` or `{kind: "subscription", productID: "…"}`. Actual checkout is deferred.
- Legacy classifications, `classificationIDs`, price fields, and display-time strings remain for installed TestFlight clients. New cards mirror canonical tags into the legacy field. Remove these only after retiring those clients; new app/import validation does not use `appliesTo`.
- Published versions remain immutable. The free Chef Margarita starters now use spaghetti v3, bread v2, and margarita v3. Active sessions retain their original version.

## Corrections and recovery

A cooking attempt owns a source recipe snapshot, an effective recipe, actual reported quantities, task state, timer deadlines, and a compact adjustment summary. Published content is never edited by cooking tools.

`report_amount` records an actual total in the displayed unit, including out-of-range facts. `undo_correction` can reverse the most recent unperformed edit/incorrect report while its revision is current. `reopen_node` corrects a premature completion only before dependent work starts; it restores the original timer deadline. These operations do not undo physical cooking.

Recovery uses authored options, with stages, quantities, cumulative limits, instructions, and sensory checks. `propose_recovery` computes exact additions. Acceptance requires a later user turn, then manual extra-ingredient checks. A further explicit report is required to record physical additions. Time alone never completes recovery or a cooking step. Cancel means nothing was added.

The initial options are deliberately limited: restore a margarita's original proportions within a bounded batch size; extend spaghetti sauce with the same unsalted tomatoes; add small measured amounts of water during bread kneading within its hydration limit. Unsupported ingredients, mixtures, or transformations require clarification or a restart. This is not a general autonomous recipe-rewriting system.

Changing recipes parks the previous attempt and leaves its timers running. The replacement needs manual preparation. Saved unfinished attempts can be resumed; overdue checks identify the earlier recipe. Explicitly ending an attempt cancels its app reminders. Stopping voice only turns off the microphone.

The backend advertises new tools only to clients declaring `adaptiveCooking`. The shared and style prompts remain provider-independent; actual permission/progress/quantity checks run in Swift.

## Completed-dish history

One `users/{uid}/completedRecipes/{attemptID}` record per completed attempt contains source ID/version, title, chef, servings, completion date, adjustment summary, and optional `photoPath`/`photoVersion`. Repeated completion of the same attempt is idempotent; cooking again creates a new ID. Correcting a premature completion withdraws the profile entry and preserves its local photo for later completion.

The chef offers a photo once at completion. Taking/selecting a photo is optional. The native camera and Photos picker require an explicit user action; images are never sent to the voice agent. A fresh JPEG removes source/location metadata, limits the longest edge to 1600 pixels, and enforces a 2 MB cap.

Storage path: `users/{uid}/completedRecipes/{attemptID}/dish.jpg`. Firestore and Storage rules permit only the matching Firebase account. The app uses authenticated reads, not shareable download URLs. Guests keep photos locally; signing into a new account adopts their local kitchen.

Local writes precede uploads. A serial uploader retries pending changes on foreground entry, profile refresh, new changes, or Retry sync. Replacements reuse the same object path. Account generation checks isolate in-flight work during sign-out. Remote history loads in pages of 12; refresh also reconciles deletions within loaded date ranges. Dirty local edits win until uploaded; simultaneous edits to the same completed entry use last-write-wins. Live cooking remains device-local.

Remove photo, delete entry, and reauthenticated account deletion clean up images and metadata. Account deletion also removes orphan uploads before deleting Firebase Auth. Network failures leave pending local work available to retry. Voice accounting/security retention remains separate.

## Deployment and verification

Firebase Storage uses the existing configured bucket `oui-chef-dev-20260914.firebasestorage.app` in US-EAST1, provisioned through the [Firebase default-bucket API](https://firebase.google.com/docs/reference/rest/storage/rest/v1alpha/projects.defaultBucket/create). Firestore/Storage rules and tag query indexes are deployed.

The compatible tag/access migration preserves old fields and versions. Its local backup is `.firebase/catalog-before-tags-20260917.json` (ignored by git). Operator command:

```sh
node backend/catalog-admin.mjs migrate-tags /new/path/catalog-backup.json oui-chef-dev-20260914
node backend/catalog-admin.mjs draft /path/to/recipe.json oui-chef-dev-20260914
node backend/catalog-admin.mjs publish spaghetti oui-chef-dev-20260914
```

Publishing requires an allowlisted gcloud operator account. Client publication still uses verified Firebase identity. Chef creation/import UI and public creator APIs were not added.

Checks: 23 Swift cooking/persistence tests and 15 backend tests pass, including Firestore and Storage emulator isolation, image size/type/path limits, replacements/deletes, old-client tool compatibility, and voice budget/concurrency controls. The signed simulator cooking flow passes manual preparation, timer pause/relaunch, completion, photo selection, guest-to-account upload and reauthenticated account deletion. The separate email account lifecycle test also passes; emulator inspection confirms no completed-dish records or photos remained after deletion. Seed a test image with `xcrun simctl addmedia <simulator-id> OuiChef/Assets.xcassets/AppIcon.appiconset/AppIcon.png` before running the photo flow. Physical camera capture and a real spoken recovery still need device acceptance; automated checks spend no xAI credit.
