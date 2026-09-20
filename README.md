# Oui Chef

## Companion redesign

The app now opens into the private cookbook, recipe import, guided cooking, and cooking album flow. Equipment is optional. See [Companion redesign](docs/COMPANION_REDESIGN.md) for the import pipeline, Firebase model, beta limits, deployment requirements, and verification commands.


A native iPhone cooking companion with three normalized recipes, persistent cooking state, timer reminders, and an xAI voice integration. Cooking works locally; connected voice uses a restricted development backend. The xAI key is connected and a live tool-to-spoken-answer test passes. Cloud voice is available to signed-in accounts, with up to three independent sessions at once; guests can use manual cooking and local voice.

## Run

Open **OuiChef.xcodeproj**, choose the **OuiChef** scheme and an iPhone simulator or Colin’s connected iPhone, and press Run. Deployment target: iOS 17+. Automatic signing uses Jianing Xie’s development team (`84KXUNPGCM`); other developers should select their own team under Signing & Capabilities. Bundle identifier: `com.xie.ouichef`.

The iOS app uses Apple frameworks, Firebase Core/Auth/Firestore, and Google Sign-In through Swift Package Manager. The voice server uses Firebase Admin and the `ws` WebSocket package.

## Implemented

- Firestore recipe sets, classified recipe cards, reusable ingredients, cursor pagination, private drafts, immutable publication, and verified catalog-admin access. See [catalog operations](docs/FIRESTORE_CATALOG.md).

- Cream/sage SwiftUI interface based on `designs/`: onboarding, discovery, one-screen ingredient preparation, cooking, bookmarks, and history.
- Preferences use short pages and compact choice grids to fit without scrolling at the default text size on iPhone 14; larger accessibility text retains a scrolling fallback.
- Free starter recipes attributed to **Chef Margarita**, in the free Kitchen Essentials recipe set; no subscription is required.
- Optional Apple, email/password, Google, and phone account screens, account linking, password reset, verification, sign-out, and account deletion.
- Separate local preferences/history for each signed-in account. The first sign-in adopts a guest kitchen only if the account has no saved kitchen on this iPhone.
- Three JSON recipe graphs: spaghetti, yeasted bread, margarita. Stable ingredient/state IDs, dependencies, equipment scheduling, actions, waits, and checkpoints.
- Manual ingredient and product-label confirmation on one screen before starting. Saved preferences apply approved substitutions and supported taste ratios automatically; pantry basics are collapsed and specialized equipment remains visible. Everyday tools selected during signup are omitted from preparation.
- A shared catalog of 66 foods in 31 hierarchical categories, ingredient search, saved dislikes, and sprite asset slots. See the [ingredient catalog and growth plan](docs/INGREDIENT_CATALOG.md).
- Independent persisted timer deadlines, local notification reminders, readiness confirmation, and checkpoint rechecks. First and second proof remain separate.
- Ratio previews with fixed-base arithmetic, supported ranges, confirmation, stale-proposal rejection, and protection for ingredients already used. Initial ratio editing is available during preparation.
- Atomic local session storage and recovery after termination; pauses leave timers running.
- xAI voice transport, specialist prompt routing, and validated cooking tools, with native voice commands as a selectable fallback. Warm return check-ins and recipe-authored coaching cues use the same cooking state. Voice shuts down when the app backgrounds.
- Opt-in local usage event counts. No audio, transcripts, or allergy values in usage events.

### Voice in this build

Tap the bottom microphone to open a white voice screen that expands from the navigation button. The button becomes a red X; closing it stops audio while cooking timers continue. Connection and permission failures stay visible with retry or Settings actions. The listening indicator waits for the first microphone packet to be sent. Reduce Motion disables the expanding transition.

**Cloud voice:** the iPhone sends audio and cooking context to the authenticated Cloud Run relay, which loads the pasta, bread, or tequila prompt and connects to xAI. The cooking tool supports recipe selection, quantity questions from current state, ratio proposals/confirmation, task readiness, and pause/resume. The live relay test verified xAI reading recipe state through a tool and returning the correct lime quantity in spoken audio. Physical-device microphone/playback behavior and full cooking conversations remain unverified. See [voice setup](docs/VOICE_SETUP.md).

**Local voice:** preset commands include `pasta`, `bread`, `margarita`, `start step`, `done`, `not yet`, `repeat`, `pause`, `resume`, `where are we`, `less talking`, and `stop listening`. Touch controls work without microphone permission. During native speech playback, only explicit pause/mute interruption commands are accepted.

Local recognition uses Apple's on-device capability when available and may otherwise use Apple's speech service. Cloud audio is processed by xAI via Oui Chef; no audio or transcript is stored in the server ledger. Interruptions require tapping to reconnect. Spoken coaching requires an active foreground voice session. Speaker echo, AirPods, interruption behavior, and power use still need physical-device tests.

The relay loads the versioned specialist files in `prompts/`. The local command recognizer does not run system prompts. xAI is for the proof of concept only. The user plans to switch to OpenAI voice on pay-as-you-go billing; its adapter and pricing-specific accounting are not implemented yet. Shared account access, cooking state, and session limits stay in the backend.

## TestFlight

Release packaging and upload instructions: [TestFlight setup](docs/TESTFLIGHT.md).

## Firebase

- Project: `oui-chef-dev-20260914` ([console](https://console.firebase.google.com/project/oui-chef-dev-20260914/overview)).
- Registered iOS app: `com.xie.ouichef`.
- Firebase SDK configuration: `Configuration/GoogleService-Info.plist` (project identifiers, not a server credential).
- `.firebaserc` points to the development project.

Blaze is enabled. The Cloud Run voice backend is deployed with a dedicated, restricted service account. Firebase Auth verifies each user’s identity. Google, Apple, email/password, and phone accounts can use voice without manual enrollment; anonymous guests receive a sign-in prompt. An explicit `voiceTesters/{uid}.enabled = false` still blocks an account. Firestore stores the shared recipe and ingredient catalog alongside the server-only voice ledger. Published recipe cards and ingredients are readable by users; drafts and paid cooking graphs have separate access checks. Secret Manager version 1 of `XAI_API_KEY` is bound to the ready backend revision; the key is never included in the iPhone app.

Apple, Google, email/password, and phone providers are enabled. Phone SMS is restricted to US numbers in development. Cooking-history/preference sync, product analytics, and Crashlytics remain future work. See [account setup](docs/AUTH_SETUP.md). Voice cost telemetry is separate from opt-in product analytics. Firebase costs are separate from the user's $17 xAI credit; server guardrails reserve a conservative $15 testing allowance.

## Checks

Verified: simulator build, signed build/install/launch on Colin’s iPhone 14, sixteen core checks, eleven backend checks (including signed-in authorization, three concurrent isolated conversations, shared-budget reservations, and account-transfer authorization), a bounded live xAI tool/spoken-answer check through the deployed relay, and a live synthetic-account check of email sign-in plus one-time voice enrollment transfer. Synthetic accounts/records were removed afterward. The account lifecycle and full local cooking UI flows passed on iPhone 14 / iOS 18.4 after the account changes; microphone behavior and real Google/SMS sign-in are not covered by those tests. The earlier manual ingredient flow and account configuration were installed and launched on Colin’s iPhone. The grouped ingredient catalog/preference flow was uploaded as TestFlight 1.0 (3); Apple had begun processing it when upload completed. Its matching voice backend is live.

Core checks (graph validity, readiness, timers/recovery, proofing retries, coaching deduplication, ratios, allergens, command negations, and equipment conflicts):

```sh
swift test
npm ci --prefix backend
npm test --prefix backend
```

The shared Xcode scheme includes **OuiChefUITests**, which walks through onboarding, ingredient search/dislikes, approved pasta substitutions, manual ingredient readiness, a margarita timer, pause, and relaunch. Run Product → Test on an isolated simulator. The test deliberately preserves session data after relaunch and attaches screenshots.

## Current limits

Recipe content and adjustment ranges are development content awaiting kitchen review. Food photography has not been added; the app uses native illustrations and a green voice-orb app icon. Recipe images in the supplied design boards remain references.

One cooking session on one iPhone is supported. Ratio changes after mixing, live multi-device handoff, camera checks, arbitrary substitutions, and lock-screen listening are not implemented. Elapsed timers restore using device wall-clock deadlines; handling manual device-clock changes remains a follow-up. The development voice relay has a 10-minute connection/audio allowance, explicit reconnects, and a shared testing budget; these are development controls, not the final long-session experience.

The complete product scope and delivery sequence are in [the MVP plan](docs/MVP_PLAN.md).

Catalog update validation: 18 Swift core tests, 12 backend tests including real Firestore emulator access rules, and the iPhone 14 / iOS 18.4 cloud-catalog cooking flow passed. Live recipe/set queries and ingredient search passed after index deployment. No paid AI calls were made for this update.

The Firestore catalog/admin update is uploaded as TestFlight **1.0 (4)** and was processing when accepted. See [release details and SDK symbol warnings](docs/TESTFLIGHT.md). The source commit is `1bff9644814e895c69ea7655005691fa8a6bd8ff`.
