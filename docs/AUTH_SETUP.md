# Account setup

## Current scope

Google, email/password, and phone sign-in use Firebase Auth. Google uses the new `Configuration/GoogleService-Info.plist` supplied September 15 and its reversed client ID URL scheme. Phone uses silent APNs verification with Firebase's reCAPTCHA fallback; the encoded Firebase app ID URL scheme is also registered. Firebase configures during `didFinishLaunchingWithOptions`, after UIKit is available. App-delegate swizzling is disabled, so callbacks are handled in `OuiChefApp.swift`. The Keychain access group is scoped to this app.

Apple sign-in is enabled. Its native UI, nonce, account linking, reauthentication, token revocation, and account-deletion paths use Firebase Auth. The app carries the Sign in with Apple entitlement and `OuiChefAppleSignInEnabled = true`.

The three bundled recipes are free under Anonymous Chef. Accounts are optional. Chef-pack subscriptions, imports, and pack-specific agent prompts are future work, as recorded in [the MVP plan](MVP_PLAN.md).

## Firebase and Apple configuration

- Project: `oui-chef-dev-20260914`; iOS bundle: `com.xie.ouichef`; Apple team: `84KXUNPGCM`.
- Google, password-required email, phone, anonymous, and Apple providers are enabled.
- SMS region allowlist is US only. Real SMS may incur Firebase costs, separate from the xAI prepaid voice budget. No SMS is sent by automated checks.
- For silent phone verification, upload an APNs authentication key in Firebase Project settings → Cloud Messaging when available. With no key, test reCAPTCHA fallback on the real phone before release.
- Apple uses Services ID `com.xie.ouichef.auth`, bundle ID `com.xie.ouichef`, and Firebase's OAuth code-flow configuration for account-deletion token revocation. The `.p8` private key remains outside the repository.
- Suggested Apple web domain: `oui-chef-dev-20260914.firebaseapp.com`; return URL: `https://oui-chef-dev-20260914.firebaseapp.com/__/auth/handler`.
- Configure Apple's private email relay for Firebase verification/password-reset messages before supporting Apple-linked email accounts.

References: [Google](https://firebase.google.com/docs/auth/ios/google-signin), [phone](https://firebase.google.com/docs/auth/ios/phone-auth), [Apple and token revocation](https://firebase.google.com/docs/auth/ios/apple).

## Data and development voice

The Firebase SDK keeps auth credentials in the iOS Keychain. Passwords and provider tokens are not written into local kitchen JSON. Local kitchen filenames are SHA-256 hashes of Firebase UIDs, with a separate guest file. A validated guest kitchen is moved to a new account's file only when no account file exists. Signing out stops voice and loads the separate guest kitchen. An unreadable archive remains preserved and cannot overwrite another account's data.

An existing development device may hold the previous REST anonymous voice identity. After explicit account sign-in, `/account/claim-voice` verifies both Firebase ID tokens and transfers only an enabled anonymous tester enrollment in a Firestore transaction. It disables the old enrollment and records a single destination. It cannot merge account ownership, grant subscriptions, or choose a destination UID from request JSON. A failed transfer leaves the old credential available for retry. Signed-in accounts now receive voice access automatically; anonymous guests cannot use cloud voice. The compatibility transfer cannot re-enable an explicitly blocked account.

Account deletion requires fresh sign-in, deletes the Firebase Auth user and this account's local kitchen. Apple-linked deletion additionally revokes Apple authorization. Development voice usage/security documents are retained: usage has an `expiresAt` value but Firestore TTL still needs enabling before wider rollout. Client account deletion does not remove the server's enrollment/migration records. No audio or transcripts are retained in that ledger.

## Checks

`swift test` covers archive isolation, guest adoption, deletion, path handling, and corrupt-data preservation alongside recipe execution. `npm test --prefix backend` includes transfer authorization, idempotency, and HTTP request limits.

For the isolated account UI check, start a Firebase Auth emulator on `127.0.0.1:9099`, then run `OuiChefUITests/AccountFlowTests` on a simulator with normal code signing enabled (do not set `CODE_SIGNING_ALLOWED=NO`; Firebase needs the Keychain entitlement). The test passes `--auth-emulator`, which only Debug builds honor; this directs Firebase Auth to the emulator and skips production voice migration. The test creates and deletes a synthetic email account without sending email or SMS. Do not pass this argument on the development iPhone.

Google OAuth, SMS/reCAPTCHA, and Apple sign-in need real provider/device verification; passing the email emulator test does not verify those services.

The migration endpoint is deployed in Cloud Run revision `oui-chef-voice-00003-s2b`. A live synthetic-account check passed email sign-in, transfer, old enrollment disabling, and idempotent retry; all synthetic users/enrollment records were removed. No audio, email or SMS was sent.

The emulator account UI check passed creation, sign-out, sign-in, reauthenticated deletion, and guest Free-category browsing on iPhone 14 / iOS 18.4. The final device build also compiled and signed; Colin’s iPhone was disconnected, so this update has not been installed. Google OAuth and real SMS remain unverified on device.

Final regression: the clean-install onboarding/ingredient-readiness/timer/pause/relaunch UI flow passed on iPhone 14 / iOS 18.4 after these changes.
