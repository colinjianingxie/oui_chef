# TestFlight

## September 20, 2026 — written recipe imports, build 8

Oui Chef AI **1.0 (8)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully on September 21 at **03:02:31 UTC** (September 20 local time). Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's final upload receipt was **PROCESSING**, with no record-level errors or warnings; tester availability has not been verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `260ef8e`, pushed to GitHub. Upload ID: `56b61ab7-fa5b-454a-90ad-22694595103f`. The signed Release app was also installed and successfully launched on **Colin’s iPhone (2)**, an iPhone 14 running iOS 26.6.1. Xcode assigned upload build 8; the source/archive/device build setting remains 1.0 (2).

This release adds written-source-first recipe imports, improved YouTube description retrieval, visible parsing stages, pending cookbook cards with progressive details, and a saved chef spoken-language preference. It also includes the preference checklists and import-form refinements committed since build 7. The matching backend is deployed as **`oui-chef-voice-imports-260ef8e`**, serving 100% of the existing Cloud Run service traffic. Health and authentication guards passed; account data and quotas were preserved.

Verification: 30 Swift core tests, 26 backend tests, the updated simulator import-progress/cookbook acceptance test, signed Release archiving, signature verification, physical-device installation and launch, and App Store Connect upload passed. Three emulator-only tests were skipped. This release validation made no paid AI calls. A fresh live Matcha recipe has not been validated after the written-source priority and extraction-prompt changes; the prior output's semantic issues are not claimed fixed.

Archive and both app/Share Extension dSYMs: `/Volumes/Margarita01/OuiChef-Builds/imports-20260920/OuiChef-1.0-imports.xcarchive`. Sanitized upload receipt: `/Volumes/Margarita01/OuiChef-Builds/imports-20260920/testflight-upload-receipt.json`. Xcode again warned about missing dSYMs for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc; upload succeeded, but crash frames inside those prebuilt dependencies may have limited symbol detail.

No tester-group assignments, Beta App Review submissions, or App Store release submissions were changed.

## September 20, 2026 — companion redesign, build 7

Oui Chef AI **1.0 (7)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **23:02:05 UTC**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**; Apple's upload record was **PROCESSING** with no record-level errors or warnings. Tester availability has not been verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `19c2f09`. Upload ID: `e6d6ee3d-cac0-4b07-b5d0-70f70233c831`. Sanitized receipt: `.build/testflight/OuiChef-1.0-7-upload-receipt.json`.

This release contains the private cookbook, persistent preferences, URL imports, iOS Share Extension, normalized recipe screens, guided cooking with stateful timers, contextual AI interface, and private cooking album. Equipment is optional. **Backend deployment completed after approval:** revision `oui-chef-voice-00012-b7c` serves the redesigned AI/import endpoints at the URL already used by this build. Firestore was backed up and cleared, Auth accounts were retained, the new Firestore/Storage rules and indexes are live, and the import queue exists. See [deployment status](COMPANION_REDESIGN.md#september-20-release-operations).

Verification: 27 Swift core tests, 23 backend/rules tests, both new simulator UI journeys, live xAI structured extraction/research/transcription checks, and signed Release archiving passed. Both app and Share Extension profiles include the shared App Group. The archive signature verifies. Live Cloud Tasks import, private artwork access, contextual cooking answers, Swift recipe decoding, cooking-session sync, photo upload, and account-data cleanup passed after deployment. A missing read-only Firestore grant for Storage rules was found and fixed during the live photo check. Temporary accounts and private data were removed; model/usage audit records remain. Physical-device Share Sheet, microphone interruptions, and locked-phone alerts still require acceptance checks.

Archive: `/Volumes/Margarita01/OuiChef-Builds/redesign-20260920/release/OuiChef-1.0-redesign.xcarchive`. App and Share Extension dSYMs are retained. Xcode assigned upload build 7; the source/archive setting remains 1.0 (2). Missing dSYM warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc did not prevent upload; those dependency crash frames may have limited symbol detail.

No tester-group assignments, beta-review submissions, or App Store release submissions were changed.

## September 18, 2026 — metadata search, build 6

Oui Chef AI **1.0 (6)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at 14:07:25 UTC. Xcode reported that Apple is processing the package; tester availability is not yet verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

This build includes the streamlined ingredient screen and token-free metadata search for typed/voice recipe discovery and ingredient names/aliases/categories. Live Firestore no longer stores `searchTokens`; earlier builds must update for search. Ordinary browsing and recipe detail loading remain paginated/lazy. POC text matching scans metadata pages and should move to a search index as catalog size warrants it.

Checks: 25 Swift core tests, 15 backend/emulator tests, and the full simulator cooking flow passed, including finding “Zucchini” by “COURGETTE” beyond the first metadata page with no token fields. No paid voice calls were made. Backend revision `oui-chef-voice-00011-mjb` is deployed; five obsolete token indexes were removed.

Archive: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-18/OuiChef-1.0-search-1003.xcarchive`. The app signature verifies and its dSYM is retained. Xcode assigned upload build 6; the source/archive setting remains 1.0 (2). Xcode again warned about missing dSYMs for prebuilt dependency frameworks; the upload succeeded.

App Store Connect: **Oui Chef AI** (`6812917370`) · Bundle ID: `com.xie.ouichef` · Team: `84KXUNPGCM`.

## Current release: 1.0 (5)

Apple accepted the adaptive cooking/photo build on **September 18, 2026 at 12:02:50 UTC** (8:02:50 a.m. Eastern). Xcode reported **Upload succeeded / EXPORT SUCCEEDED**; the last observed upload state was **PROCESSING**. Check availability in [App Store Connect → TestFlight](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `990f009cbb7082966422be7b81c99d23b3b1157f`. Upload ID: `cdd72f35-0c0a-4b32-a74b-6a6f32fbd2db`. Sanitized receipt: `.build/testflight/OuiChef-1.0-5-upload-receipt.json`.

Archive: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-18/OuiChef-1.0-adaptive-0800.xcarchive`. Oui Chef’s dSYM is retained. Xcode assigned uploaded build **5**; source/archive version remains **1.0 (2)**. Signature verification passed, including bundled recipes, ingredients, tags, camera permission text, and 30 privacy manifests.

This build adds cooking corrections, supported ratio/taste recovery, and recipe switching that preserves progress and timers. Completed dishes can include an optional camera or library photo in the user's private profile; history and photos sync after sign-in. Ingredient checks remain manual. Catalog tags and recipe-set access metadata are simplified while retaining compatibility with installed builds. Chef authoring, subscription sales, and the OpenAI voice migration remain deferred.

Backend: `oui-chef-voice-00008-vqh`. Private Firestore/Storage rules and tag indexes are deployed. Starter recipe versions are spaghetti 3, bread 2, and margarita 3, with previous versions retained. The three-session concurrency limit, 10-minute voice limit, and shared $15 estimated xAI guardrail are unchanged.

Validation: 23 Swift core tests, 15 backend tests including Firestore/Storage emulator access rules, and the iPhone 14 / iOS 18.4 cooking and account UI flows passed. Checks covered manual preparation, timer persistence, completion photos, guest-to-account synchronization, and account/photo deletion. Live authentication/concurrency and catalog checks passed; temporary accounts were removed. No paid AI calls were made during release validation.

**Symbol warnings:** Xcode again reported missing dSYMs for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc. Upload succeeded and app symbols are preserved; crash frames inside those SDK binaries may lack source-level detail. The upload record itself reported no errors or warnings.

No tester groups, beta review, or App Store release submissions were changed. Physical camera capture, spoken cooking recovery, real provider sign-in, and kitchen content review still need device acceptance testing. This build was not installed directly on Colin’s phone. App Store privacy answers must also account for private completed-dish metadata and photo uploads; they were not changed by this upload.

## Previous release: 1.0 (4)

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
