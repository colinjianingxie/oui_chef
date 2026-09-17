# TestFlight

App Store Connect: **Oui Chef AI** (`6812917370`) · Bundle ID: `com.xie.ouichef` · Team: `84KXUNPGCM`.

## Current release: 1.0 (4)

Apple accepted the Firestore catalog/admin build on **September 17, 2026 at 03:08:27 UTC** (September 16 at 11:08:27 p.m. Eastern). Xcode reported **Upload succeeded / EXPORT SUCCEEDED**; the last observed upload state was **PROCESSING**. Check availability in [App Store Connect → TestFlight](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `1bff9644814e895c69ea7655005691fa8a6bd8ff`. Upload ID: `eec90ca2-b2b3-43df-a668-c3423eb876e7`. Receipt: `.build/testflight/OuiChef-1.0-4-upload-receipt.json`.

Archive: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-16/OuiChef-1.0-firestore-2310.xcarchive`. Oui Chef’s dSYM is retained. Xcode assigned uploaded build **4**; source/archive version remains **1.0 (2)**. Signature verification passed; the archive contains 30 privacy manifests.

This build adds paginated Firestore recipe/set cards, on-demand graph and ingredient loading, six-item ingredient pages, shared classifications, chef/set ownership, price metadata, private drafts, and authenticated draft publication. Verified sign-in with either configured catalog-admin email enables draft previews. Starter recipes belong to Chef Margarita’s free Kitchen Essentials set. StoreKit sales remain disabled. The corresponding backend is `oui-chef-voice-00007-lcd`, with existing voice budget/concurrency settings retained.

Validation: 18 Swift core tests, 12 backend tests including Firestore emulator access rules, and the iPhone 14 / iOS 18.4 cooking UI flow passed. Live published recipe/set queries, ingredient search, denied private reads, service health, and unauthenticated publication rejection passed. No paid AI calls were made.

**Symbol warnings:** Xcode reported missing dSYMs for FirebaseFirestoreInternal, absl, grpc, grpcpp and openssl_grpc. The installed Firebase binary artifacts did not contain matching dSYM files. Upload succeeded; app symbols are preserved, while crash frames inside those SDK binaries may lack source-level detail. Do not generate placeholder symbols or re-upload this accepted build to hide the warnings.

No tester groups, beta review, or App Store release submissions were changed. This build was not installed directly on Colin’s phone. Physical-device voice and real Google/SMS sign-in still need device acceptance testing; recipe content needs kitchen review.

## Previous release: 1.0 (3)

Apple accepted the ingredient catalog/preparation update on **September 17, 2026 at 02:10:13 UTC** (September 16 at 10:10:13 p.m. Eastern). Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's upload record reported **PROCESSING**, with no errors or warnings. Check its current availability in [App Store Connect → TestFlight](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `681f8cff43aefaf922a89bc107fd853db490caf0`. Upload ID: `49eed264-14db-4231-96a4-473f52a4facf`. Sanitized receipt: `.build/testflight/OuiChef-1.0-3-upload-receipt.json`.

Archive: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-16/OuiChef-1.0-ingredients-220618.xcarchive`. Its dSYMs are preserved inside the archive. Xcode automatically changed the uploaded package to build **3**; the original source/archive build setting remains **2**. The archive remains available in Xcode → Window → Organizer → Archives.

This release includes the grouped ingredient flow, ingredient-based preferences, 66 reusable ingredients in 31 categories, saved dislikes, approved pasta substitutions, and informational kitchen tools. The matching voice backend is deployed as `oui-chef-voice-00006-m6g`. Cloud voice still requires account sign-in, permits three independent concurrent sessions, and retains the 10-minute session limit and shared $15 estimated xAI guardrail.

Tester-group assignment and beta-review submission are separate from uploading. No tester groups or review submissions were changed.

## Releasing again

Use the Apple account already signed into Xcode and automatic signing. Archive the generic iOS destination, then upload with `Configuration/TestFlightExportOptions.plist`. Its `manageAppVersionAndBuildNumber` setting lets Xcode select the next upload build number; a source build-number edit is unnecessary.

```sh
xcodebuild -exportArchive \
  -archivePath /path/to/OuiChef.xcarchive \
  -exportPath /tmp/oui-chef-testflight-upload \
  -exportOptionsPlist Configuration/TestFlightExportOptions.plist \
  -allowProvisioningUpdates -hideShellScriptEnvironment
```

No private API key is included in the repository. Apple processes uploads before they become available in TestFlight; uploading does not publish an App Store release. The privacy manifest declares app-local UserDefaults access; App Store privacy answers still need to cover Firebase authentication, voice processing, and server usage accounting.

## Build 3 validation

16 Swift core tests, 11 backend tests with a fake provider, and the iPhone 14 / iOS 18.4 cooking UI flow passed. Release archiving and code-signature verification passed, including the bundled ingredient catalog and app dSYM. The deployed backend passed health, missing-auth rejection, guest sign-in messaging, and three independent signed-in connections across two temporary accounts. Temporary accounts were removed; this release validation made no paid xAI calls.

This new build was uploaded to TestFlight, not installed directly on Colin's iPhone. Physical-device voice conversations and real Google/SMS/Apple sign-in still need device acceptance testing. Recipe content needs kitchen review.

## Previous upload

Build **1.0 (2)** was accepted September 16, 2026 at 22:44:51 UTC. Its archive remains at `/Users/xie/Library/Developer/Xcode/Archives/2026-09-16/OuiChef-1.0-2.xcarchive`, with receipt `.build/testflight/OuiChef-1.0-2-upload-receipt.json`.
