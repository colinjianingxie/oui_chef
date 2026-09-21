# Oui Chef companion redesign

## Product flow

Native SwiftUI replaces the catalog-first entry point with account creation, three short preference pages, and a private cookbook. The reference is `Downloads/new_design.png` and the twelve individual cooking-companion screens. Cream backgrounds, olive controls, serif headings, generous spacing, and food photography carry through onboarding, import, recipe review, preparation, cooking, completion, and the album.

Home shows saved recipes, imports, unfinished cooks, and recently cooked dishes. Cookbook supports search and favorites. The center action imports a link. Album contains finished attempts, including those without photos. Profile holds persistent preferences and account controls. Equipment is optional, collapsed context. Only ingredients and usable instructions are required to import or cook.

Cooking keeps the recipe visible, shows the current action, allocated ingredients, sensory cues, temperatures and multiple timers, and supports voice or touch. Browsing back does not undo completed work. Explicit repeat actions reopen a step and leave its earlier completion in history. Timer expiry means check the food, never automatic completion. Finishing preserves the recipe snapshot, events, substitutions, questions, notes, rating and optional dish photo. The screen stays awake by preference; microphone listening ends when the app backgrounds. Native local notifications identify the timer and its cooking cue.

## Import pipeline

1. Paste a URL, or use the bundled iOS Share Extension. The extension saves a durable App Group receipt before submitting. Signed-in receipts are tied to the account; anonymous receipts are claimed after sign-in. If submission fails, opening the main app retries the saved link.
2. An authenticated endpoint creates a Firestore job and queues a Cloud Task. Deduplication includes the user, normalized URL and retry attempt. Work continues after the phone closes. Jobs expose queued, fetching, extracting, transcribing, checking, ready, skipped, failed and canceled states.
3. The worker reads public HTML, recipe JSON-LD, metadata and surrounding text through a Python standard-library parser. Social sources additionally use pinned yt-dlp and its matching EJS package (using the existing Node runtime) to read descriptions and caption tracks. Public DNS addresses are checked and pinned for page requests, redirects, thumbnails and media connections. Cookies, credentials, local-network addresses and login bypasses are not accepted.
4. xAI structured extraction decides whether supported ingredients and actionable steps exist. If useful evidence remains in video, the worker downloads bounded media, transcribes its audio and samples four timestamped frames with ffmpeg. Otherwise it can search for the original creator recipe or missing context and retry normalization. If the evidence remains insufficient, no recipe is invented or saved.
5. The normalized recipe separates ingredients, preparation, named components, stages, steps, suggested timers, visual cues and source timestamps. Source, inferred and supporting evidence remain distinguishable. Simple preference adjustments are described explicitly; uncertain substitutions stay suggestions, and allergy conflicts remain visible for review. Recipes and private source thumbnails are saved in Firebase.

Original videos remain at their attributed source. YouTube technique links seek to supported timestamps; other platforms open the original source while preserving cooking state. A timestamp is never fabricated when the source does not provide one.

### Concrete beta limits

- Public sources only. Social-platform availability varies; failed imports offer retry and pasted source text.
- Downloaded media: up to 20 minutes and 40 MB; four 640-pixel video frames. HLS-only sources may provide captions without downloadable media.
- Up to 150 ingredients and 150 steps. Missing amounts, time, servings and equipment are allowed.
- Up to 20 active timers per cooking attempt. Timer deadlines survive restart; notification delivery depends on iOS notification permissions and system settings.
- The cookbook loads the latest 200 records in each collection. Pagination is needed before exceeding that beta limit.
- Components are named ingredient/step groups in a single ordered recipe; their steps can be visited independently and their timers overlap. There is no general dependency-graph scheduler.
- Import allowance defaults to 1,500 reserved cents globally, reserving 100 cents per attempt. These are conservative quotas, not claims about actual billing. Raise/reset deliberately for further testing. Questions default to 60 per account per UTC day. The existing voice budget and 10-minute connection cap remain.
- No silent learned changes to dietary or allergy settings. Prior attempts are supplied as context; users explicitly save preferences and modifications.

## Data and model records

Firebase Authentication provides identity. Firestore paths are:

- `users/{uid}/settings/cooking`: preferences.
- `users/{uid}/imports/{id}`: asynchronous import state and source receipt.
- `users/{uid}/cookbook/{id}`: normalized recipe JSON and metadata.
- `users/{uid}/cookbook/{id}/versions/1`: the initial normalized result.
- `users/{uid}/cooks/{id}`: recipe snapshot and cooking history, with a server revision.
- `aiRuns/{id}`: provider, requested and returned model, task, user/import/session IDs, prompt/schema versions, request ID, token usage, status and latency. Raw source text and ingredient photos are not logged here.
- `voiceSessions/{id}` and the existing voice ledger retain metering and model metadata.
- `aiBudget/imports`, `aiQuestionLimits/{uid}`: beta quotas.
- `deletedAccounts/{uid}`: prevents in-flight work from recreating deleted account data.

Storage uses private `users/{uid}/cooks/{attemptID}/dish.jpg` and `users/{uid}/recipeMedia/{recipeID}/cover-{attempt}` objects. Ingredient question photos are sent for that question and are not added to the album. Source audio/video and sampled frames are temporary worker files, removed after processing.

The client keeps an atomic, account-specific local archive and a sync outbox. The server accepts session snapshots only against the expected revision. If another device has changed the same cook, the local continuation becomes a separate attempt, preserving both histories. No provider-specific objects are embedded in the recipe/session contract. A future OpenAI change should replace the request/voice adapters and rerun behavior checks; there is no speculative second provider implementation.

Current defaults: `grok-4.3` for extraction, research and questions; `grok-voice-transcribe-2.0` for transcription; `grok-voice-think-fast-2.0` for live voice. Text and transcription defaults can be overridden by `XAI_RECIPE_MODEL` and `XAI_TRANSCRIPTION_MODEL`.

API references checked during implementation: [structured outputs](https://docs.x.ai/developers/model-capabilities/text/structured-outputs), [speech transcription](https://docs.x.ai/developers/model-capabilities/audio/speech-to-text), [voice](https://docs.x.ai/developers/model-capabilities/audio/speech-to-speech).

## Deployment requirements

Use the explicit Firebase/GCP project `oui-chef-dev-20260914`; the workstation's default gcloud project is unrelated.

1. Deploy the updated Firestore and Storage rules. Storage rules read the deletion tombstone from Firestore. Give `service-172500657212@gcp-sa-firebasestorage.iam.gserviceaccount.com` the native `roles/firebaserules.firestoreServiceAgent` role (only `datastore.entities.get`), with a condition matching this project's default database. Rule deployment alone did not add this grant; a live photo upload revealed the missing permission.
2. Give the existing runtime service account Cloud Tasks enqueue permission on `oui-chef-imports` only. Apply `backend/runtime-role.yaml` through the existing default-Firestore-database conditional binding and a binding on the Storage `users/` managed folder. The bucket uses uniform bucket-level access so that this folder grant covers object get/list/create/update/delete without access to `admin-backups/`. Do not grant this custom role unconditionally across the project or put service-account credentials in the app. See [managed-folder access](https://docs.cloud.google.com/storage/docs/managed-folders).
3. Enable Cloud Tasks and create a queue in `us-east1`, initially with one concurrent dispatch. Supply `IMPORT_TASK_QUEUE` as the full `projects/.../locations/us-east1/queues/...` resource and `IMPORT_WORKER_URL` as the HTTPS `/companion/worker` endpoint. Set a 900-second Cloud Run request timeout to match the task deadline. Worker requests are HMAC signed; unsigned calls are rejected.
4. Build with `backend/cloudbuild.yaml` and deploy the resulting image to the existing development service. The image installs Python, ffmpeg and pinned yt-dlp. Supply `XAI_API_KEY` from Secret Manager and `FIREBASE_STORAGE_BUCKET=oui-chef-dev-20260914.firebasestorage.app`. `IMPORT_INLINE=1` is available only for local development and is rejected on Cloud Run.
5. Register `com.xie.ouichef.share` and the App Group `group.com.xie.ouichef` for the Apple team. Both app targets need the shared keychain group and App Group entitlements. Refresh their provisioning profiles. A real device check must confirm sharing from Safari and each installed social app, microphone interruption behavior, and locked-phone timer alerts.

No legacy account/catalog data needs to be deleted to activate the new entry point. The old catalog code is retained alongside the user's existing work, but the new product flow uses the private cookbook collections.

## Verification

- Core: `swift test`.
- Backend: `cd backend && npm test`.
- Rules: start isolated Firestore and Storage emulators, seed `catalog/seed.json` with the existing catalog CLI, then run backend tests with `FIRESTORE_EMULATOR_HOST` set. The old catalog tests require that seed.
- New UI journey: `xcodebuild ... test -only-testing:OuiChefUITests/CompanionFlowTests`. The preexisting UI suites target the retired catalog screens and are not acceptance tests for this redesign.
- Offline visual preview: launch Debug with `--companion-preview`; add `--companion-onboarding` to begin at preferences. The sample recipe and photo are explicitly marked preview data and are never written to Firebase.

The welcome food photograph was generated for this redesign with the image-generation tool: editorial garlic tagliatelle on an ivory ceramic plate and linen, warm natural light, olive accents, and open space above for the welcome heading. It is bundled as `OuiChef/Assets.xcassets/WelcomeFood.imageset/welcome.png`.

Build verification uses a local source copy because several project files are iCloud placeholders. Resolved Swift packages and the first build live under `/Volumes/Margarita01/OuiChef-Builds/redesign-20260920`; the simulator build was compiled on the internal SSD and then moved to the external drive with a symlink at `/tmp/ouichef-redesign-build`. Release compilation uses `/tmp/ouichef-release-derived`. Earlier temporary Oui Chef build caches were relocated under `previous-caches` with symlinks left at their old `/tmp` paths; `relocations.json` records those moves. Keep the drive mounted to reuse those caches.

Verified on September 20: all 27 Swift core tests; all 23 backend tests including isolated Firebase rules tests; one live Grok 4.3 structured extraction (3 ingredients and 3 steps); pinned yt-dlp command-line options. Live smoke testing used a synthetic recipe and kept the API key only in process memory.

Additional live checks: xAI web research returned a cited answer from the original public recipe; speech transcription returned HTTP 200 for an eight-second public-domain test clip. The initial locally synthesized audio fixture was empty and was replaced before the passing transcription run. yt-dlp 2026.8.19 requires matching `yt-dlp-ejs==0.8.0` and `--js-runtimes node`; these are included in the worker image.

The complete app and bundled Share Extension passed an unsigned iOS simulator build (both arm64 and x86_64). The temporary build copy recovered the unchanged icon from its existing generator and the privacy manifest from the earlier exported app because those two source files were iCloud placeholders; their unchanged contents and the other placeholders were restored from preserved copies.

Final simulator acceptance: both onboarding and the complete cooking journey passed, including the pinned onboarding action, timer pause, browsing completed steps, explicit finish, photo skip, and album entry. Screenshots are available in `/tmp/ouichef-redesign-preview/index.html`. `git diff --check` passed.

## September 20 release operations

Source commit `19c2f09` is pushed to GitHub. Firestore's 129 documents were exported successfully to the private project bucket at `gs://oui-chef-dev-20260914.firebasestorage.app/admin-backups/before-redesign-reset-20260920`, then every collection and subcollection was deleted. A subsequent collection listing was empty. Firebase Auth accounts were preserved; no user photo objects existed. The new Firestore indexes, Firestore rules, and Storage rules are deployed.

Cloud Tasks is enabled, with queue `oui-chef-imports` in `us-east1` limited to one concurrent dispatch and three attempts. After explicit approval, the redesigned backend was built and deployed as **`oui-chef-voice-00012-b7c`**, serving 100% of traffic at the existing app URL. It uses 1 GiB memory, a 900-second request timeout, the existing maximum of one instance, and the existing Secret Manager reference. TestFlight 1.0 (7) already points to this service; no new iOS upload is needed.

Cloud Build: `a78a865e-7f27-4e8d-b45c-757f70b3f4dc`. Container digest: `sha256:fc7e62024be80af6213a7f20ed5a710c177e94da39c6224168262beb648b0c2c`. Application source matches `19c2f09`. Runtime data permissions remain bound to the default database and the Storage `users/` managed folder; task enqueue permission is bound to this queue only. The Storage service agent has a separate read-only, default-database-scoped grant for checking deleted-account tombstones.

Live acceptance passed: authenticated public-page import through Cloud Tasks and xAI; a saved recipe with 7 ingredients and 5 steps; `xai` / `grok-4.3` model trace; private artwork upload and owner download, with public reads denied; contextual cooking answer; Swift decoding and validation of the actual returned recipe; synchronization of the Swift-encoded cooking attempt and idempotent retry; client photo upload; and recursive private-data cleanup. Initial photo uploads returned 403 because the Storage rules service lacked Firestore read permission. Adding the native read-only role fixed the issue after IAM propagation. Health returned 200, unauthenticated imports 401, and unsigned worker calls 403. The queue had no remaining test tasks.

Temporary test logins, recipes, cooking attempts, and media were removed. Server-side AI usage records, conservative budget reservations, and deletion tombstones remain for accounting and model provenance. The backup remains outside the runtime's object-access scope. Live check logs: `/tmp/ouichef-live-import-check.log` and `/tmp/ouichef-live-storage-check.log`. This verifies a public recipe website; real-device social Share Sheet behavior and platform-specific media availability still require device acceptance checks.

Automatic provisioning and the signed Release archive succeeded for both `com.xie.ouichef` and `com.xie.ouichef.share`, including the shared App Group. Both app and extension dSYMs are preserved in `/Volumes/Margarita01/OuiChef-Builds/redesign-20260920/release/OuiChef-1.0-redesign.xcarchive`. See [TestFlight](TESTFLIGHT.md) for the upload receipt and build number.


## Preference checklist update

Allergies, dietary restrictions, avoided foods, and optional kitchen equipment use searchable checklists. Search filters existing local options and aliases; it does not create custom entries. The ingredient options reuse the bundled ingredient library, so no network or legacy Firestore catalog is required. Selected items stay visible while filtering. An empty allergy list is `unspecified`; only explicitly choosing “No known allergies” sets `noneKnown`.

Cooking profiles now encode `profileVersion: 2`, stable selection IDs, allergy answer status, and readable selection names for import, question, and voice agents. Earlier free-text values remain in `previousPreferencesPendingReview` and are shown for explicit review before replacement. Cooking history and recipes are preserved. No server schema deployment is needed because the existing private settings payload and AI context accept this structured JSON.

The email entry opens its form directly and closes after successful authentication. Sign-in-method linking and verification-email prompts were removed from the normal account screen. Account deletion is available only inside Privacy & Account; any deletion reauthentication remains attached to that explicit action.

Search, URL, email/password/phone, question, recipe-text, note, timer, and substitution inputs use a keyboard Done toolbar. Timer and substitution entry use sheets so numeric keyboards have the same dismissal action. Done dismisses the keyboard without submitting or clearing input. This update is separate from the previously uploaded TestFlight 1.0 (7).

Verified September 20: all 29 Swift core tests and all four simulator acceptance flows passed (email sign-in to preferences, searchable selections and keyboard dismissal, optional equipment, and cooking through timers to saved memory). The email test used the local Firebase Auth emulator and an ad-hoc signed simulator build; unsigned simulator builds could not persist Firebase credentials in Keychain. Emulator identities use the app-local keychain rather than the real shared account group. Checklist and cooking screenshots were inspected. Logs: `/tmp/ouichef-preferences-core-all.log`, `/tmp/ouichef-preferences-ui.log` (cooking and optional-equipment flows), and `/tmp/ouichef-preferences-signed.log` (passing sign-in and checklist reruns). No cloud deployment or TestFlight upload was performed for this update.

## Import modes and cooking-only sources

The import screen leads with Paste a link and a centered, padded Make it a recipe action. Paste the text switches to a standalone text editor; no URL is required. Upload a photo is a non-interactive Coming soon row. The platform icon strip and decorative quote were removed. Link and text drafts survive mode changes, and keyboard Done does not submit. Pasted-text recipes display their source label without a fabricated original-source link.

The Share Extension accepts public URLs, text containing URLs, attributed text, and UTF-8 provider data. Its existing shared keychain, private App Group queue, and authenticated backend submission remain in place: signed-in shares queue immediately; offline/signed-out shares are retained until the main app can submit them. It is offered through the native iOS Share Sheet (Share → More → Oui Chef when necessary). Host apps decide which items they expose to the system Share Sheet.

Source host selects public HTML extraction or yt-dlp’s platform extractor. Social imports first retrieve written descriptions and up to three public description links, prioritizing links labeled as recipes. After the cooking-scope check, normalize the written evidence; only if insufficient, search for the creator’s original written recipe. Captions, bounded media download, audio transcription, and key frames are secondary fallbacks when written instructions remain insufficient. Transcript evidence is kept separate and must not override explicit written quantities or instructions. Unknown sources may use the secondary media evidence for another scope check; non-food sources stop without research or media fallback. The existing limits remain 20 minutes and 40 MB for downloadable media. Login-only, unavailable, or unsupported media can fall back to public page evidence or pasted recipe text; successful extraction from every platform link is not guaranteed. Tool reference: [yt-dlp options](https://github.com/yt-dlp/yt-dlp#usage-and-options).

A separate structured xAI scope check admits only culinary food/drink preparation before recipe normalization or web research. Chemical synthesis, non-food manufacturing, cleaning products, cosmetics, crafts, and similar content are skipped. Unknown or malformed classification cannot produce a recipe. Normal cooking fermentation and food-grade techniques remain eligible. Normalization also rejects out-of-scope content and still requires ingredients plus actionable steps. Import records store retrieval method, extractor, transcript availability, scope, and the scope model-run ID; AI runs retain requested/reported models, usage, and prompt/schema version 3. This is model-based classification, not a claim that automated classification is infallible.

## Firestore structure review, September 20

The companion's product data lives under `users/{uid}`: `settings/cooking` holds preferences, `cookbook` holds saved recipes, `imports` holds background import state, and `cooks` holds cooking attempts/history. Photos belong in private Cloud Storage. These subcollections can exist without a parent user document, so a zero count of root `users` documents does not mean there is no user data.

| Server-owned path | Current behavior | Recommendation |
| --- | --- | --- |
| `deletedAccounts/{uid}` | A deletion marker checked by workers, sync, Firestore writes, and photo uploads. It survives deletion of the user's subtree so delayed work cannot recreate that data. | Keep this protection outside the deleted subtree. It stores a UID and deletion time, not a copy of the account. Do not remove markers until old credentials and queued work can no longer write. |
| `aiQuestionLimits/{uid}` | One rolling counter per account; the UTC date resets the count on the next request. Default: 60 question attempts/day. Failed provider requests currently count too. | Keep the rate limit. Deletion currently leaves this record behind; remove it during account cleanup, accounting for in-flight requests, when implementing that cleanup change. Moving the path alone adds no value. |
| `aiBudget/imports` | One global, transactional quota. Each new/retried import reserves 100 cents against a default 1,500-cent ceiling. Reservations are never reconciled or automatically reset. | Keep a beta quota, but describe it as 15 shared import attempts, not measured spending or a daily allowance. A later change should use explicit attempt units and reset policy, or implement actual spend reconciliation if that is the intended limit. |
| `aiRuns/{id}` | Model, task, usage, timing, and result metadata for debugging AI work. | Keep useful receipts with a defined retention period. They contain UIDs, so account deletion needs an explicit policy for removing/anonymizing them. |
| `voiceBudget/development`, `voiceSessions/{id}` | Separate voice concurrency reservations and estimated usage; created when voice is used. | Keep while voice is enabled. Import and voice allowances are separate; neither is a total AI invoice ceiling. |

Read-only inspection found one import-quota document (`reservedCents: 400`), one question-limit document, six AI run documents, and five deletion markers. No voice budget document existed at inspection time. No documents or rules were changed by this review. The catalog/chef/set collections described in older design documents belong to the retired catalog flow; do not recreate them for the private companion. Retire their code and rules together in a separate cleanup after checking supported older builds.

The import quota and question limit address different traffic and are not redundant. Both remain server-only under the default-deny rules. The main issues are quota semantics and record lifecycle, rather than the number of top-level collections.

## YouTube import diagnostics and progress — September 20

The reported Apple-account attempt for video `d31CCyGSGZA` reached `skipped` in about seven seconds: the platform extractor failed, public HTML fallback had no transcript, and the scope check returned `unknown`. Recipe extraction and supplemental research never ran. The old worker discarded the extractor exception, so the original low-level failure cannot be recovered from this record. The example supplied for this fix, `W_-D8PZwtSY`, is a different video.

YouTube share/watch/shorts URLs now normalize to one video URL without rewriting caption endpoints. Metadata extraction tolerates unavailable video formats. Public-page fallback reads the embedded full description and caption tracks as data, without executing scripts. Empty or invalid caption responses no longer count as transcripts. The worker saves safe retrieval diagnostics and scope reasons, and supplies the original title and creator when researching missing recipe context.

The import sheet stays focused on the submitted job and displays real worker stages. Pending imports appear in Home and Cookbook with placeholders; source title/creator arrive first, then normalized ingredients and steps before the final saved recipe replaces the card. Failed jobs remain inspectable and retryable. Preferences include a saved spoken language, defaulting existing profiles to English; voice follows it independently of the source recipe language.

Verification: 30 Swift core tests and 24 backend tests passed; three Firebase-emulator-only tests were skipped. The iOS simulator build passed. The new progress/cookbook UI test passed, and the existing import-form test passed on rerun after its initial sheet-opening timeout. Exported screenshots were visually inspected at `/private/tmp/oui-import-ui-attachments`. Live public retrieval also recovered the failed video’s title, `红烧牛肉` (braised beef), and 797 characters of source text. It recovered the example video's full bilingual ingredient description, but its caption endpoints returned HTTP 200 with empty bodies and the audio request timed out. After explicit user approval, one live import verification reserved one shared import attempt and made four AI calls: scope, extraction, supplemental research, and extraction again. Scope correctly returned food; the first extraction correctly reported missing cooking instructions. Research followed by extraction returned an eight-roll Matcha Streusel Bread recipe with 15 ingredients and five steps, passing structural validation. This is a partial acceptance, not a clean normalized recipe: egg wash and optional almond slices appear in instructions but not ingredients; butter-addition order was lost; final proof and baking were combined under a single 14-minute timer. Supplemental research claimed transcript-derived steps, but the local retrieval did not independently recover that transcript. The current structural validator does not detect these semantic errors. No further paid attempts were run, no user cookbook/settings records were changed, and no backend deployment or TestFlight upload was performed.

Live verification artifacts: `/private/tmp/oui-live-conversion.log`, `/private/tmp/oui-normalized-youtube.json`, and `/private/tmp/oui-youtube-research.txt`. Final extraction run ID: `4b7ef60f-df8c-4936-aae2-fa958936b5c0`. The shared reservation is an attempt allowance, not measured provider spending. Ingredient completeness, source fidelity, and separate proof/bake steps still require correction and a fresh acceptance check before claiming clean conversion.


### Written-source priority follow-up

Description links use the existing public URL, DNS pinning, redirect and response-size guards. Linked pages are candidates; extraction must confirm the dish and creator and ignore sponsor, shop and unrelated content. Research now seeks written original recipes only, rather than purported transcript summaries. Complete written recipes skip caption/audio retrieval entirely. Missing links or research-provider failures can still proceed to the secondary media fallback. Progress labels and the simulator fixture reflect the written-first order. Prompt version is now `companion-4`.

The extraction instructions explicitly require washes/garnishes in the ingredient list, consistent step allocations, preserved ingredient-addition order, and separate rest/proof/bake steps with timers attached only to their own step. These are model instructions, not new deterministic semantic validators; they do not establish that the earlier Matcha output is corrected. Its retrieved description contains ingredient amounts and baking temperature/time but no full method; the links are labeled for subscribing and music. Another supported source or readable media is still needed for the method.

Verification: 26 backend tests passed, with three emulator-only tests skipped; 30 Swift core tests passed. Mocked worker checks cover written-only completion, HTML fallback, written research before media, unavailable links/research, empty captions, and unknown/non-food scope. No additional paid AI run, deployment or TestFlight upload was performed for this follow-up.


### Backend deployment — September 20

Committed source `260ef8e` is deployed as `oui-chef-voice-imports-260ef8e`, serving 100% of the existing Cloud Run service traffic. Cloud Build `b13f01c8-6ed7-4311-be2b-c75eb42ce07b` produced image digest `sha256:4cfde4fc716235289528583c74f8ac978e9505b46308211a1cc2e2c131883ae6`. Existing service configuration, secrets, account data, and quotas were preserved. Health returned 200, unauthenticated imports 401, and unsigned worker calls 403. Deployment validation made no paid AI calls; semantic quality of a fresh Matcha import remains unverified.
