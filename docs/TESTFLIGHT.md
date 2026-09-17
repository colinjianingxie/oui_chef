# TestFlight

App Store Connect: **Oui Chef AI** (`6812917370`) · Bundle ID: `com.xie.ouichef` · Team: `84KXUNPGCM` · Version: `1.0` · Build: `2`.

## Current release

The release archive built successfully on September 16, 2026. Its code signature, app icon, version metadata, and app privacy manifest were verified. Distribution export also succeeded; the upload-ready IPA is saved at `.build/testflight/OuiChef-1.0-2.ipa`. Apple accepted version **1.0 (2)** on September 16, 2026 at **22:44:51 UTC**, with no upload errors or warnings. The package had begun processing when upload completed. The upload receipt is saved at `.build/testflight/OuiChef-1.0-2-upload-receipt.json`.

Archive: `/Users/xie/Library/Developer/Xcode/Archives/2026-09-16/OuiChef-1.0-2.xcarchive`. It is available in Xcode → Window → Organizer → Archives.

The app record is **Oui Chef AI**. Check processing and manage test builds in [App Store Connect → TestFlight](https://appstoreconnect.apple.com/apps/6812917370/testflight/ios). The app's home-screen name remains **Oui Chef**. Tester groups and beta-review submission are managed separately from uploading.

For future uploads, create a new archive and use its path below from the repository root:

```sh
xcodebuild -exportArchive \
  -archivePath /path/to/OuiChef.xcarchive \
  -exportPath /tmp/oui-chef-testflight-upload \
  -exportOptionsPlist Configuration/TestFlightExportOptions.plist \
  -allowProvisioningUpdates
```

The export uses the Apple account already signed into Xcode, automatic distribution signing, symbol upload, and automatic build-number management. No API key is included in the repository. Apple processes successful uploads before they appear in TestFlight; uploading does not publish an App Store release.

For the next release, increment `CURRENT_PROJECT_VERSION` in both app build configurations, then choose Product → Archive. `Info.plist` now reads the version and build from Xcode build settings. The release icon reuses the app's green voice orb. The privacy manifest declares app-local UserDefaults access; App Store privacy answers still need to cover Firebase authentication, voice processing, and server usage accounting.

## Testing scope

The latest manual ingredient flow passed the simulator cooking UI test, 12 core checks, and 7 backend checks; the current app was also built, installed, and launched on Colin's iPhone. Release packaging changes were checked by archiving and inspecting the signed app. Live microphone conversations, Google/SMS sign-in, and Apple sign-in still need device acceptance testing.

This build connects to the development Firebase/voice backend. Cloud voice requires account sign-in, allows three independent concurrent sessions, and retains the 10-minute session limit and shared $15 estimated xAI guardrail. On a new phone, sign in through Profile and tap the microphone; no tester-ID enrollment or new TestFlight build is required. Guests receive a sign-in message. Recipe content still needs kitchen review. Use internal testing first; external testing requires Apple's beta review and beta app information.
