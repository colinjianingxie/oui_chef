# Oui Chef

An iOS AI cooking companion: import a recipe link, review its ingredients, cook with persistent steps and timers, and save the finished dish in a private album. Equipment preferences are optional. The app uses native SwiftUI, Firebase Auth/Firestore/Storage, and xAI.

Recipe sharing uses Firebase Hosting links to save and open an already parsed recipe in another account. In-progress cooking sessions support native swipe-to-delete. See [recipe sharing and session deletion](docs/RECIPE_SHARING.md) for the beta flow, deployment, and checks.

## Run

Open **OuiChef.xcodeproj**, choose **OuiChef**, select an iPhone or simulator, and press Run. Deployment target: iOS 17+. Automatic signing uses team `84KXUNPGCM` and bundle ID `com.xie.ouichef`. The bundled Share Extension uses `com.xie.ouichef.share`; both targets share the App Group `group.com.xie.ouichef`.

See [the companion design and implementation](docs/COMPANION_REDESIGN.md) for the complete import pipeline, data model, provider tracking, beta limits, and deployment requirements. [TestFlight release records](docs/TESTFLIGHT.md) contain build receipts and archive locations.

The implemented [Berry / Deep Plum design migration](docs/BERRY_PLUM_MIGRATION.md) covers the October 2026 design boards and revised 16-screen specification, including inline voice, persistent preparation, reversible portions, cooking memories, data compatibility, and remaining release checks. The app is uploaded as TestFlight **1.0 (17)**; its matching backend changes remain undeployed. See the [release record](docs/TESTFLIGHT.md).

## Product flow

- Account and persistent cooking preferences, with optional equipment.
- Private cookbook, favorites, URL imports, and iOS Share Sheet imports.
- Structured ingredients, preparation, stages, steps, source attribution, and uncertainty labels.
- Current-step guidance, explicit completion, concurrent timers, voice questions, ingredient photos, and source-video timestamps.
- Local cooking recovery, private cloud synchronization, finished-dish photos, and cooking history.

The cooking screen can stay awake. Voice requires the foreground app; timer notifications work on the lock screen. Public source extraction is best effort: blocked sources can use user-supplied recipe text, and sources without supported ingredients and steps are skipped.

## Firebase and release status

Use project **oui-chef-dev-20260914** explicitly; the workstation's default gcloud project is unrelated. Firebase client configuration is in `Configuration/GoogleService-Info.plist`; the xAI credential stays in Secret Manager.

On September 20, all Firestore data was backed up and cleared, Firebase Auth accounts were retained, and the private cookbook/photo rules were deployed. The redesigned backend is live as `oui-chef-voice-00012-b7c`, with the import queue and scoped runtime permissions configured. Live recipe import, private artwork, cooking questions, session sync, photo upload, and account-data cleanup passed. See [release operations](docs/COMPANION_REDESIGN.md#september-20-release-operations) for the exact status.

## Checks

The September release checks are recorded in the historical release documents. Current Berry/Plum verification is recorded in the migration document; those checks do not establish the status of the hosted backend or live voice.

```sh
swift test
npm ci --prefix backend
npm test --prefix backend
```

Run the simulator UI suites with the OuiChef scheme. Rules tests require isolated Firestore/Storage emulators and the existing catalog test seed; details are in [verification](docs/COMPANION_REDESIGN.md#verification). All four UI suites now exercise the redesigned companion. Debug preview arguments `--companion-preview --companion-onboarding` provide an offline sample without cloud writes.

Physical-device social sharing, microphone interruptions, and locked-phone timer alerts still need device acceptance checks. Legacy catalog core/backend contracts and historical design documents remain in the repository; the redesigned app uses the private cookbook flow.
