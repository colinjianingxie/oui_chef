# Recipe sharing and cooking-session deletion

## Current flow

This beta assumes the recipient already has a TestFlight invitation, an account, and Oui Chef installed.

1. Open a saved recipe and tap the native share button.
2. Oui Chef creates an unlisted link at `https://oui-chef-dev-20260914.web.app/r/<random-id>`.
3. iOS opens the link in Oui Chef. The app saves the already parsed recipe to the recipient's cookbook and opens it.
4. **Cook with voice guidance** starts a fresh cooking session and asks for microphone permission if needed. Recipe warnings still require review. Existing voice account restrictions and usage limits apply.

The same link reopens the same cookbook entry and preserves the recipient's edits and favorite state. Sharing an unchanged recipe reuses its link. A changed recipe gets a new snapshot. Links contain no sender account identifiers. Recipe content, source credit, notes, and warnings are shared; private storage paths, favorites, AI diagnostics, conversations, cooking sessions, and personal profile settings are excluded. Deleting the sender's account revokes and removes their links. Deleting a cookbook entry alone does not revoke a previously shared snapshot.

Firebase Hosting serves the Apple association file and routes `/r/**` to the existing Cloud Run backend. The fallback webpage has an explicit **Open in Oui Chef** button using `ouichef://recipe/<id>`. If the app is missing, the page tells beta testers to use their existing invitation and reopen the link. This version does not implement an install handoff or web sign-in.

The app remembers a received link through sign-in and preference setup. It postpones opening a new recipe while a cook is on screen. Failed downloads retain the pending link for retry when the app next becomes active.

## Deployment

Deployed October 3, 2026: Cloud Build `a0d326d0-2410-4033-9da0-31ec257ee527`, image `sha256:c8b4a6e43038ac8f67794169c1d63c4d1bf2edef4e3417da5defc7283565e8d5`, Cloud Run revision `oui-chef-voice-sharing-20261003`. The backend was checked without user traffic before promotion to 100%; service account, environment, resources, concurrency, and timeout were preserved. This image includes the previously committed recipe source-retention validation. Firebase Hosting is deployed. Live health, unauthenticated write rejection, the Apple association JSON, and the Hosting recipe rewrite passed. No user recipes were changed and no paid AI validation calls were made.

Verification: 38 backend tests passed (two emulator-only checks skipped), the link parser test passed, and the sharing and swipe simulator journeys passed. The share-sheet check initially used a button selector for iOS's **Copy** cell; corrected and passed. The final swipe test passed after restoring the native swipe button style. A disk-space failure occurred during an intervening build; only generated project intermediates and superseded test artifacts were removed. Release archives and dSYMs were preserved.

- Hosting config: `firebase.json`; public files: `web/`.
- Domain: `oui-chef-dev-20260914.web.app`.
- Apple app association: `84KXUNPGCM.com.xie.ouichef`, `/r/*` only.
- Backend: `share-recipe`, `receive-share`, and `delete-cook` under `/companion/`; all require Firebase authentication. Only the recipe landing page is public.
- Firestore: server-owned `recipeLinks/{opaqueID}` and private `users/{uid}/recipeLinks/{contentHash}`. Existing deny-by-default rules cover these collections; no new client access is required.
- Deploy the backend before Firebase Hosting. Build **1.0 (16)** includes the Associated Domains entitlement and was accepted by Apple; processing/tester availability remains pending. Its signature and provisioning profile were verified. Build 15 cannot handle these links. Apple's association CDN still cached a pre-deployment 404 from 20:28:03 UTC with a one-hour lifetime; the fallback webpage's Open button remains available. Verify direct HTTPS opening on a physical device after installing the new build and cache propagation.
- No existing user cookbook or cooking-history records need migration.

## On the go

Swipe a cooking session left and tap **Delete**, or complete the native full swipe. This deletes only that session and stops its timers and voice guidance. The recipe, completed history, and other sessions remain.

Deletion requires a successful server response. Failures keep the session available and show an error. The server keeps a deletion marker, including for sessions that had not synced yet. Listeners and later stale saves recognize this marker instead of restoring or forking the deleted session.

## Checks

- `swift test --filter RecipeShareLinkTests`: accepts the supported HTTPS/custom links and rejects unrelated hosts, credentials, extra path components, and invalid IDs.
- `node --test backend/recipe-sharing.test.mjs`: recipient copies, idempotence, private-field exclusion, HTML escaping, deleted-account handling, and authentication.
- `node --test --test-name-pattern='deleting one cook' backend/companion.test.mjs`: independent sessions, preserved cookbook/other users, stale saves, repeated deletion, and unsynced sessions.
- `CompanionFlowTests/testSwipeDeletesOnlySelectedCookAndKeepsRecipe`: real left swipe and two independent sessions of the same recipe.
- `CompanionFlowTests/testSharedRecipeIsSavedAndStartsVoiceCookingDirectly`: saved recipe, immediate cooking, fixture voice activation, and native share sheet. This uses local fixtures and makes no paid voice calls.
