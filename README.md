# Oui Chef

An iOS AI cooking companion: import a recipe link, review its ingredients, cook with persistent steps and timers, and save the finished dish in a private album. Equipment is optional. The app uses native SwiftUI, Firebase Auth/Firestore/Storage, and xAI.

## Run

Open **OuiChef.xcodeproj**, choose **OuiChef**, select an iPhone or simulator, and press Run. Deployment target: iOS 17+. Automatic signing uses team `84KXUNPGCM` and bundle ID `com.xie.ouichef`. The bundled Share Extension uses `com.xie.ouichef.share`; both targets share the App Group `group.com.xie.ouichef`.

See [the companion design and implementation](docs/COMPANION_REDESIGN.md) for the complete import pipeline, data model, provider tracking, beta limits, and deployment requirements. [TestFlight release records](docs/TESTFLIGHT.md) contain build receipts and archive locations.

## Product flow

- Account and persistent cooking preferences, with optional equipment.
- Private cookbook, favorites, URL imports, and iOS Share Sheet imports.
- Structured ingredients, preparation, stages, steps, source attribution, and uncertainty labels.
- Current-step guidance, explicit completion, concurrent timers, voice questions, ingredient photos, and source-video timestamps.
- Local cooking recovery, private cloud synchronization, finished-dish photos, and cooking history.

The cooking screen can stay awake. Voice requires the foreground app; timer notifications work on the lock screen. Public source extraction is best effort: blocked sources can use user-supplied recipe text, and sources without supported ingredients and steps are skipped.

## Firebase and release status

Use project **oui-chef-dev-20260914** explicitly; the workstation's default gcloud project is unrelated. Firebase client configuration is in `Configuration/GoogleService-Info.plist`; the xAI credential stays in Secret Manager.

On September 20, all Firestore data was backed up and cleared, Firebase Auth accounts were retained, and the private cookbook/photo rules were deployed. The import task queue exists. **The redesigned Cloud Run backend and its runtime permissions still await deployment approval**, so the redesigned AI/import endpoints are not live yet. See [release operations](docs/COMPANION_REDESIGN.md#september-20-release-operations) for the exact status.

## Checks

The redesign passed 27 Swift core tests, 23 backend/rules tests, both new simulator UI journeys, and live xAI extraction, research, and transcription checks. The signed Release archive includes the Share Extension.

```sh
swift test
npm ci --prefix backend
npm test --prefix backend
```

Run the new UI suite with `-only-testing:OuiChefUITests/CompanionFlowTests`. Rules tests require isolated Firestore/Storage emulators and the existing catalog test seed; details are in [verification](docs/COMPANION_REDESIGN.md#verification). Older UI suites exercise the retired catalog screens. Debug preview arguments `--companion-preview --companion-onboarding` provide an offline sample without cloud writes.

Physical-device social sharing, microphone interruptions, and locked-phone timer alerts still need device acceptance checks. Legacy catalog code and its historical design documents remain in the repository; the redesigned app uses the private cookbook flow.
