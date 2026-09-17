# xAI voice development

Oui Chef uses xAI only for the proof of concept. The next provider is planned to be OpenAI voice on pay-as-you-go billing; its adapter and provider-specific spending policy will be implemented during that switch. The iPhone streams mono PCM16 audio at 24 kHz over an authenticated WebSocket to a small Cloud Run relay in the Firebase development project. The relay connects to xAI; the permanent provider key never reaches the iPhone. Cooking progress remains local and authoritative.

## Current connection

- Project: `oui-chef-dev-20260914`, Blaze enabled.
- Region: `us-east1`.
- Service: `oui-chef-voice` (scales to zero, maximum one instance).
- Endpoint: `wss://oui-chef-voice-172500657212.us-east1.run.app/voice`, configured in `Configuration/Info.plist`.
- xAI model: `grok-voice-think-fast-2.0`; voice: `eve`.
- Secret: `XAI_API_KEY` version **1**, bound to ready revision `oui-chef-voice-00005-vqf` on September 16, 2026 (US Eastern).
- Firebase Auth: signed-in Google, Apple, email/password, or phone accounts. Voice no longer requires tester enrollment. Anonymous guests are prompted to sign in through Profile. A user ID is an account identifier, not an iPhone hardware ID.
- Firestore: default database holds server-owned account access overrides, legacy enrollment transfers, and the voice usage ledger. Client reads/writes are denied. Recipe/session sync is not implemented.
- App Check remains deferred for this limited TestFlight proof of concept. Sign-in is required; app attestation and per-user quotas remain work for a public rollout.

## Test on your iPhone

The key has been saved and connected. For a later key rotation, add a version to the existing [XAI_API_KEY secret](https://console.cloud.google.com/security/secret-manager/secret/XAI_API_KEY/versions?project=oui-chef-dev-20260914), then explicitly update the service's pinned version:

```sh
gcloud run services update oui-chef-voice \
  --project oui-chef-dev-20260914 --region us-east1 \
  --update-secrets XAI_API_KEY=XAI_API_KEY:NEW_VERSION_NUMBER
```

1. Keep xAI automatic credit top-ups off and the invoiced spending limit at $0 to stay within prepaid credit. These account settings have not been independently verified. [xAI billing controls](https://docs.x.ai/console/billing)
2. On each iPhone, open **Profile** and sign in with an account. Tap the microphone again. No tester ID or new TestFlight build is needed. One account can be used on multiple devices, but each cooking conversation and its local progress remain separate. Missing/invalid tokens are rejected, guests receive a sign-in message, and explicitly blocked accounts remain blocked.

   Administrators can block an account by setting `voiceTesters/{uid}.enabled` to `false`. Missing records allow signed-in users. The existing `node backend/admin.mjs allow UID` helper can re-enable an explicitly blocked account; it does not grant anonymous guests access.

3. Start voice again. The microphone changes into a red X as a white background expands into the voice screen. **Microphone on** appears only after microphone audio has been sent; permission or a connected socket alone is insufficient. Tap the red X to close voice. Ask for one margarita, complete the manual ingredient/tools/labels checklist, review amounts, then start voice from the ready summary and cook through the final checkpoint. The mic remains active in the foreground until stopped; leaving the app closes voice and preserves timers. Touch and local voice remain available.

## The $17 testing budget

`backend/budget.mjs` allows **$15 in conservative estimated usage**, leaving $2 of the stated xAI credit unallocated. This allowance is shared across test devices and does not reset monthly.

- Each connection reserves $1.50 atomically before contacting xAI. Up to three voice sessions may be active at a time, including separate devices using the same account. A fourth receives a busy message before contacting xAI.
- The server closes each connection after 10 minutes, 10 total minutes of audio sent/received, or 50 text messages, whichever comes first. A new connection requires a tap and restores cooking context.
- Estimates use $0.10/audio minute and $0.008/text item: twice xAI's documented starting rates of $0.05 and $0.004 as checked September 14, 2026. These are guardrails, not provider invoices. [xAI pricing](https://docs.x.ai/developers/models/speech-to-speech)
- Tool results are not counted as billable text messages. Input silence streamed from the microphone is included in our estimate. Stop voice during long waits when you want to conserve testing credit; cooking timers keep running.
- The shared Firestore transaction reserves both a session slot and budget atomically; concurrent requests cannot each spend the same remaining allowance. Existing spend is preserved during rollout. On normal close, only that session’s slot and unused reservation are released using server-observed audio byte counts and text events. A crashed session keeps its full reservation; clients cannot report lower usage or reset the allowance.
- Usage documents include connected seconds, input/output seconds, text count, estimated cents, provider, and UID. Audio, transcripts, recipe snapshots, and allergy values are not written to the server ledger. `expiresAt` marks a 30-day retention date; enable Firestore TTL before a wider test rollout.
- xAI billing settings are the account-level limit. Estimates cannot guarantee the exact invoice or cover usage of the same account elsewhere. Firebase/Cloud Run charges are separate from the xAI credit.

Inspect `voiceBudget/development` and `voiceSessions` in the Firebase console. Do not reset the ledger just to bypass a depleted allowance; reconcile it against xAI's usage dashboard first.

## Provider boundary and specialist prompts

`backend/xai.mjs` holds xAI's URL, model, audio/session configuration, event translation, and system-prompt assembly. The iPhone sends provider-independent `start`, `audio`, `context`, `text`, `cue`, `tool_result`, and `interrupt` events. It receives `ready`, audio, transcripts, speech activity, tool requests, and lifecycle events.

The relay loads `prompts/shared.md` plus the current recipe's pasta, bread, or tequila prompt. All specialists call the same `cooking` tool. Swift validates session/revision, prerequisites, ingredient restrictions, and supported ratios. Ingredient and product label checks are manual and cannot be completed by voice tools. Kitchen equipment is informational in the updated preparation flow. An explicit user report can complete an active step without a prior readiness question; a task cannot be started and completed in the same voice turn. Ratio confirmation still requires a later user turn. The engine owns calculations and recurring check-ins; elapsed time never completes a step. Recipe source instructions are not executed by the model as code.

Switching to OpenAI means implementing its adapter and reviewing its usage accounting, authentication, audio configuration, and interruption behavior. The iPhone transport and recipe engine can stay the same. No OpenAI adapter or provider key is included yet; protocol compatibility is not assumed. [Official OpenAI voice API reference](https://developers.openai.com/api/reference/typescript/resources/live)

## Build and checks

```sh
npm ci --prefix backend
npm test --prefix backend
swift test
gcloud builds submit --project oui-chef-dev-20260914 --config backend/cloudbuild.yaml
```

The backend check uses a fake provider on localhost: it verifies authentication, tool sequencing, audio metering, and cleanup without spending xAI credit. Swift checks cover the recipe engine, stale voice commands, unknown operations, and confirmation ordering. The simulator build checks compilation; it does not validate microphone echo cancellation, latency, or real xAI response behavior.

The default `backend/smoke.py` checks missing-auth rejection, the guest sign-in message, and three authenticated connections across two temporary accounts. It sends no start events, makes no xAI calls, creates no enrollment records, and deletes its temporary accounts afterward. `--live` separately opts into a paid provider check.

After binding the key, `SSL_CERT_FILE=/etc/ssl/cert.pem python3 backend/smoke.py --live` verified a real cooking-state tool call followed by spoken audio containing the recipe's correct 15 mL lime quantity. The paid probe allows one text question, at most two read-only tool calls, a 30-second deadline, and at most 10 seconds of received output audio. It closes the connection, removes its temporary identity/enrollment, and checks server usage finalization.

Two initial live probes recorded a combined **4 cents in conservative server estimates**. The first ended on a spoken preamble; the corrected probe waits for the response after the tool result and verifies the quantity. This is not an xAI invoice or an account-balance reading.

In earlier device tests, Colin’s iPhone was manually enrolled. The physical-device check received xAI output audio but recorded zero microphone input seconds; the stricter first-input-packet check correctly failed. On September 15, device diagnostics confirmed that the engine started with a valid unmuted 48 kHz input, then stopped before delivering its first buffer. The app now rebuilds capture on startup audio-configuration changes within the existing connection timeout. That signed fix is installed on Colin’s iPhone; its live microphone retest remains pending because the phone switched apps during automation. The new white voice overlay, microphone-permission failure, close action, and anchored navigation passed the isolated iPhone 14 simulator check. Full live cooking acceptance is still pending. The probe supplies text input and verifies returned audio bytes; it does not exercise an iPhone microphone or speaker. Verify speaker echo, interruption while speaking, Bluetooth route changes, backgrounding, two proofing stages, and return to an overdue timer. No production release is implied by a successful build.

## Runtime access

The dedicated server-only `oui-chef-voice` service account has a custom `ouiChefVoiceLedger` role limited by an IAM condition to the development database. It can read/create/update documents and transact, but cannot delete data or administer Firebase Auth. It may read only `XAI_API_KEY` in Secret Manager. The broader initial IAM proposal was rejected by automatic approval review; the narrowed grants were accepted.

## September 16 preparation and coaching update

The development relay now serves revision `oui-chef-voice-00004-vtp`, built as `dadda3ca-9091-4b76-9dfe-47d1e968c58a`. The health endpoint responds successfully. Updated shared instructions require manual ingredient/equipment/label checks and accept explicit reports of completed active steps without a second readiness question. Ratio changes still require preview and confirmation. No paid AI session was used for this update’s tests.

The native engine now checks untimed actions using authored `checkAfterSeconds`, follows up on unanswered questions, and schedules another check for Not yet. Reminders never complete a step. Preparation state, adjusted amounts, and timers survive a relaunch. UI completion uses an inline Done button.

Validation: 12 core tests, 7 local backend tests, and the iPhone 14 simulator cooking flow passed. The UI flow checks bulk selection/clear, equipment and labels, a lime adjustment from 15 to 17.5 mL, the ready summary, inline completion, timer pause/relaunch, and a typed done report without a modal. Screenshots were inspected. The final signed iPhone build and signature verification passed. This update was subsequently installed and launched on Colin’s iPhone. Live microphone/voice acceptance remains pending.

## Signed-in multi-device beta

Revision `oui-chef-voice-00005-vqf` serves the account-based access and three-session policy. Cloud Build: `fc01f70d-707d-4413-9fdd-77812a458678`. Eleven backend tests pass, including two devices sharing an account, conversation isolation, rejection of a fourth session before any provider connection, concurrent spending reservations, crash reservation retention, and compatibility with the old ledger. The deployed no-credit smoke check also passed: missing-auth rejection, a clear guest sign-in prompt, and three signed-in connections across two temporary accounts. The temporary accounts were removed. No native app changes or paid AI test calls were needed.

## Ingredient catalog update (local)

The shared prompt and tool description now match ingredient-only verification. Voice context includes current ingredient preference reviews and restrictions from the selected recipe snapshot, including approved substitutions. These prompt changes are in source and require the next backend deployment; the deployed revision above has not changed as part of this UI/catalog update.
