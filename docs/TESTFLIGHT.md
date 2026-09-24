# TestFlight

## September 23, 2026 — shared imports and Debug mode, build 14

Oui Chef AI **1.0 (14)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **02:49:33 UTC on September 24**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**; App Store Connect is processing the package. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit `8f6ab81` was pushed to `main`. The app adds a default-on Debug mode setting that reveals import metadata, retrieved text, original-language transcripts, video observations, and retrieval errors. The matching backend image `sha256:a33a3a7f8028a4f5b51e20f7af4d587dddf841157c717b2fd38eb2dc292b97b4` is deployed as `oui-chef-voice-00020-qlk` at 100% traffic. It gives free accounts one successful import per UTC day, recognizes the Firebase `admin` custom claim for unlimited imports, reuses successful public URL recipes for matching preferences, and allows a longer native YouTube inspection. The exact reported 15-minute video returned original `zh-CN` speech and visual observations in 158 seconds with the longer timeout.

The signed archive, app dSYM, and Share Extension dSYM are at `/Users/xie/Library/Developer/Xcode/Archives/2026-09-23/OuiChef-1.0-14-20260923.xcarchive`. The device build and archive passed; 31 Swift core and 27 runnable backend tests passed. After deployment, health returned 200, unauthenticated import 401, and unsigned worker 403. Firestore index exemptions deployed. The obsolete global import budget and its reservation field on the reported import were removed; the old recipe version was retained because it is a distinct original snapshot. The existing missing-dSYM warnings for five prebuilt Firebase/gRPC dependencies remained, but upload succeeded. No tester assignments or review submissions were changed.

## September 22, 2026 — direct cooking from imports, build 13

Oui Chef AI **1.0 (13)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **02:42:50 UTC on September 23**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's receipt is **PROCESSING**; tester availability is not yet verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `6b46bd3`, pushed to `main`. Upload ID: `a8b0ca02-a23b-4c48-959e-316d4dc4a630`. Completed link imports now offer **Start cooking** without showing parsed evidence; saved YouTube recipes use the video's thumbnail when a stored cover is unavailable. The existing parser backend was unchanged.

Verification: 31 Swift core tests and 32 backend tests passed; three emulator-only backend tests were skipped. The focused simulator direct-start journey and final iOS build passed. The signed Release archive and app/Share Extension dSYMs are at `/Users/xie/Library/Developer/Xcode/Archives/2026-09-22/OuiChef-1.0-direct-start-6b46bd3.xcarchive`. Xcode repeated the existing missing-dSYM warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc; upload succeeded, but crash frames inside those dependencies may have limited symbols. The source/archive build setting remains 1.0 (2); Xcode assigned upload build 13.

No tester assignments, Beta App Review submissions, or App Store release submissions were changed.

## September 22, 2026 — video recipe evidence, build 12

Oui Chef AI **1.0 (12)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **00:56:40 UTC on September 23**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's receipt is **PROCESSING**; tester availability is not yet verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `9d13b21`, pushed to `main`. Upload ID: `c35106e6-b512-4d3c-8723-a51f7e995067`. This build shows original speech, preferred-language translation, and video observations in recipe import evidence. The matching backend code was already deployed as `oui-chef-voice-youtube-d016cd` before this app upload.

Verification: 30 Swift core tests and 32 backend tests passed; three emulator-only backend tests were skipped. The signed Release archive and App Store Connect upload succeeded. The archive and app/Share Extension dSYMs are at `/Users/xie/Library/Developer/Xcode/Archives/2026-09-22/OuiChef-1.0-video-9d13b21.xcarchive`. Xcode repeated the existing missing-dSYM warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc; upload succeeded, but crash frames inside those dependencies may have limited symbols. The source/archive build setting remains 1.0 (2); Xcode assigned upload build 12.

No tester assignments, Beta App Review submissions, or App Store release submissions were changed.

## September 21, 2026 — layered recipe parsing, build 11

Oui Chef AI **1.0 (11)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **22:21:39 UTC**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's receipt is **PROCESSING**; tester availability is not yet verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `60a58f6`, pushed to `main`. Upload ID: `93175c7a-415a-4876-b0b3-63c9d6843fb5`. This build shows the layered flow: metadata and original transcript, food classification, translation and video inspection, normalized ingredients and steps, then cookbook save. Its matching backend revision, `oui-chef-voice-layered-60a58f6`, stops uncertain and non-food sources before translation/media work and gives food sources one extraction pass with all available written, transcript, translation, and frame evidence.

Verification: all 30 Swift core tests, all 29 runnable backend tests, and the focused simulator import-progress journey passed; three emulator-only backend tests were skipped. Health returned 200, unauthenticated import returned 401, and unsigned worker access returned 403 after deployment. Build 11 was installed on Colin’s iPhone; automatic launch was denied because the phone was locked.

Archive and app/Share Extension dSYMs: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-21/OuiChef-1.0-layered-60a58f6.xcarchive`. Xcode repeated the existing missing-dSYM warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc; upload succeeded, but crash frames inside those dependencies may have limited symbols.

No tester assignments, Beta App Review submissions, or App Store release submissions were changed.

## September 21, 2026 — import evidence and video frames, build 10

Oui Chef AI **1.0 (10)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **21:37:23 UTC**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's receipt is **PROCESSING**; tester availability is not yet verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `f5aa75d`, pushed to `main`. Upload ID: `49197697-7077-4307-a959-3d2bf80f430f`. This build exposes import metadata, the last incomplete parsing stage, partial ingredients, the original transcript, its English translation, and sampled video-frame timestamps. Its matching backend revision, `oui-chef-voice-evidence-f5aa75d`, sends original/translated captions and up to 24 evenly sampled frames to extraction when written evidence is incomplete.

Verification: all 30 Swift core tests, all 29 runnable backend tests, and the focused simulator import-evidence journey passed; three emulator-only backend tests were skipped. Health returned 200, unauthenticated import returned 401, and unsigned worker access returned 403 after deployment. Build 10 was installed on Colin’s iPhone; automatic launch was denied because the phone was locked.

Archive and app/Share Extension dSYMs: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-21/OuiChef-1.0-evidence-f5aa75d.xcarchive`. Xcode repeated the existing missing-dSYM warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc; upload succeeded, but crash frames inside those dependencies may have limited symbols.

No tester assignments, Beta App Review submissions, or App Store release submissions were changed.

## September 21, 2026 — cookbook deletion and Chinese captions, build 9

Oui Chef AI **1.0 (9)** (`com.xie.ouichef`, team `84KXUNPGCM`) uploaded successfully at **12:55:03 UTC**. Xcode reported **Upload succeeded / EXPORT SUCCEEDED**. Apple's receipt is **PROCESSING**, with no record-level errors or warnings; tester availability is not yet verified. [App Store Connect](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios).

Source commit: `ff53653`, pushed to `main`. Upload ID: `7542d54e-684f-4d25-9a7c-6876b54bbe7c`. This build adds confirmed recipe deletion that preserves cooking history and resists stale device saves. The matching deployed backend, `oui-chef-voice-history-c1cbdf2fd553`, adds reliable caption fallback, original-language selection, English step extraction, corrected timestamp units, and safe re-import after clearing history. Firestore rules are deployed. The app changes were also built, installed, and launched on Colin’s iPhone before uploading.

Verification: 30 Swift core tests, 29 backend tests, 16 companion tests with Firestore/Storage emulators, the simulator deletion journey, signed Release archiving, signature verification, and App Store Connect upload passed. Three unrelated emulator-only tests were skipped in the general backend run. Prior live Chinese-caption extraction returned six English steps; the release upload made no new paid AI calls.

Archive and app/Share Extension dSYMs: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-21/OuiChef-1.0-cookbook-ff53653.xcarchive`. Sanitized receipt: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-21/OuiChef-1.0-9-upload-receipt.json`. Xcode assigned upload build 9; the source/archive setting remains 1.0 (2). The existing missing-dSYM warnings for FirebaseFirestoreInternal, absl, grpc, grpcpp, and openssl_grpc do not block the upload, but those dependency crash frames may have limited symbols.

No tester assignments, Beta App Review submissions, or App Store release submissions were changed.

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
