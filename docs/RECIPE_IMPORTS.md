# Recipe import diagnostics — September 22, 2026

## Root cause

The supplied failure log showed successful food classification from metadata but no captions, duration, audio or frames. An isolated Cloud Run job reproduced the cause for all three supplied YouTube links: YouTube returned **“Sign in to confirm you’re not a bot”** from the datacenter IP. Successful metadata retrieval did not mean successful media retrieval. The old pipeline also suppressed these warnings, skipped media with unknown duration, and could select audio without video for silent clips.

The diagnostic job was `oui-parser-check-20260922`, execution `oui-parser-check-20260922-vnbt6`, project `oui-chef-dev-20260914`, region `us-east1`. Its source-only process exited successfully because descriptions existed; the logs, not its exit status, show zero captions/audio/frames. The diagnostic image is an earlier snapshot, **not** the final fix or a production deployment.

A second live failure was classification of the silent Short as an eating-only ASMR video from its vague title, before inspecting the footage. Metadata-only social rejections now become `unknown` until media inspection/research; actual non-food evidence still stops recipe extraction.

Manual comparison with the Short's actual frames found a further accuracy issue: one-frame-per-second native inspection reversed the drizzle/closing order and inferred an oven from an offscreen tray transition. Silent clips up to 60 seconds now receive one denser four-frame-per-second inspection. Both the reader and recipe prompts distinguish unseen actions from observed cooking; missing heating details belong in warnings, not invented steps. This is a bounded second pass, not an unlimited retry.

## Implemented

- Preserve original-language captions and transcribe available audio. Translate into `settings/cooking.voiceLanguage`, also used for recipe text.
- Reuse source metadata; retrieve video and audio independently; inspect duration with ffprobe when metadata omits it. Download progressive media in validated byte ranges; use the existing yt-dlp dependency for HLS through the public-IP-only proxy.
- Sample up to 24 frames, denser for short clips. Fall back to up to six public post images without falsely labeling them video frames. Try embedded video on websites when written instructions are insufficient.
- Search the exact URL/post ID and creator rather than substituting a similar recipe. Keep third-party transcriptions attributed as supplemental evidence.
- Verify the draft against the evidence, including displayed quantities, water, ingredient additions, step order, timing and pressure release.
- Optionally send public YouTube URLs to Vertex AI's native video reader when transcript or frames are missing. Preserve timestamped original speech and separate visual observations in the import record. Never use cookies or bypass login walls.

The native reader uses existing Firebase application-default credentials and REST calls, not another SDK. `YOUTUBE_VIDEO_MODEL=gemini-2.5-flash` enables it; absence disables it. Its video input is capped at 20 minutes. Model usage is recorded in `aiRuns` under provider `google`, task `source_video`. The source remains untrusted data, not instructions. Long, inaccessible or insufficient sources can still fail; this is not a guarantee that every social link is publicly readable.

## Verification

- Real local media retrieval: beef video `d31CCyGSGZA` produced Chinese captions and 24 frames; cookie video `50vc67EXTwk` produced Chinese captions and 21 frames; silent Short `86NHFK1RAJ0` produced 18 frames. HLS retrieval was also exercised on the Short.
- Live Vertex calls with the signed-in developer credential recovered original Chinese speech and video observations for both Chinese videos, and visual-only observations for the Short. Timestamp strings are converted deterministically to seconds. Large `maxItems` schema constraints caused HTTP 400; array limits are now enforced after response parsing instead.
- Live xAI extraction/verification produced recipes for all three local media sources. Full worker import of the BBC Good Food easy-pancakes page saved a Spanish recipe with seven ingredients and five steps in an in-memory cookbook.
- Simulated Cloud Run missing-media conditions through the real worker, replaying the independently captured Vertex evidence and making live xAI calls: all three imports reached `ready`. Beef: 17 ingredients/seven steps, original Chinese and English translation; cookies: five ingredients/nine steps, original Chinese and English translation; Short: six ingredients/11 steps, no invented speech, warnings for the ambiguous drizzle and unknown oven temperature/duration. This verifies integration locally, not Cloud Run credentials or deployment.
- Swift core: 30 tests passed; changed UI files also passed syntax parsing. Backend excluding `catalog.test.mjs`: 31 passed, two emulator-only tests skipped. The full backend run stalled while importing the existing catalog/Firestore dependency; no claim is made that the full suite or Firebase rules were verified in this run.
- Public-image fallback, split media, missing duration, failed audio, original Chinese captions, preferred-language translation, native response validation, bounded dense inspection and worker recovery have runnable regression checks.
- Instagram/TikTok/RedNote share URLs and shared retrieval paths are covered, but live acceptance is deferred by the user's subsequent YouTube-only scope decision.

Run public retrieval without AI or Firebase writes:

```sh
node backend/import-smoke.mjs 'https://www.youtube.com/watch?v=d31CCyGSGZA'
```

Run the full worker with a configured `XAI_API_KEY` and in-memory cookbook (billed provider usage, no saved Firebase recipe or import-attempt reservation):

```sh
IMPORT_CHECK_LANGUAGE=English node backend/import-smoke.mjs --live 'https://www.youtube.com/shorts/86NHFK1RAJ0'
```

Python with the Docker-pinned yt-dlp/EJS versions, Node 22, ffmpeg and valid TLS certificates are required. Native video also needs `GOOGLE_CLOUD_PROJECT`, `YOUTUBE_VIDEO_MODEL`, and a credential authorized for model invocation. Do not disable certificate checks.

## Deployment status

Cloud Run service `oui-chef-voice` now serves revision `oui-chef-voice-youtube-d016cd` at 100% traffic. Deployment occurred September 22 local time (September 23 UTC), preserving the prior service account, resources, timeout, concurrency and all existing environment settings, with only the image and `YOUTUBE_VIDEO_MODEL=gemini-2.5-flash` changed across the rollout. The final revision's image digest was checked directly. Health returned 200; unauthenticated imports returned 401; unsigned worker calls returned 403. The Vertex AI API was enabled and custom role `projects/oui-chef-dev-20260914/roles/ouiChefVideoReader` was created from `backend/video-reader-role.yaml`. That role contains only `aiplatform.endpoints.predict`.

Automatic approval review initially rejected the project-level binding because it expands runtime permissions. The user subsequently explicitly approved it, and the role was granted to `oui-chef-voice@oui-chef-dev-20260914.iam.gserviceaccount.com` on September 22. The permission allows billed model invocation in this project; no new Firestore, Storage or IAM-management permission was granted. The user also narrowed current acceptance to YouTube; Instagram, TikTok and RedNote are deferred.

The user confirmed keeping Gemini. Initial-image build `4079df6b-110e-4494-b0ff-9213788835bf` succeeded for tag `youtube-20260922`, digest `sha256:9903b4df9a2276a93fd94cbb53dcb0727064569c3ef58a830ef53005d6180be2`. Isolated Cloud Run execution `oui-parser-check-20260922-skr4n` used the actual runtime account and `YOUTUBE_VIDEO_MODEL=gemini-2.5-flash`; all three examples reached `ready`, and the execution completed successfully in 5m32s. This established cloud media fallback and runtime IAM, but the subsequent manual Short audit required the visual-evidence correction above.

Final build `10e2261a-d626-49b7-ad8d-a2011b6b57bd`, tag `youtube-20260922-visual`, produced digest `sha256:d016cd8dd1920ae3cc1ffc51cd16b9da0168f55f3caf7f02e59e48902e586263`. Cloud execution `oui-parser-check-20260922-gbq4m` tested this exact image with the runtime account and completed successfully in 4m48s: all three imports reached `ready`. The Short placed the drizzle before closing the sandwich and warned about unseen heating instead of inventing an oven step; both Chinese videos retained original speech plus English translations, and the beef recipe included pressure release before both openings. The actual Swift models decoded and validated all three final recipes. The final image was then deployed without consuming further normal app attempts. Recipe outputs can still vary and require review, especially visually ambiguous ingredients and omitted actions; successful import is not a guarantee of perfect transcription or reconstruction.

Measured AI costs for that execution (USD):

| Example | Gemini estimate from reported tokens | xAI reported charge | Combined estimate |
| --- | ---: | ---: | ---: |
| Braised beef | $0.0445 | $0.0338 | $0.0783 |
| Butter cookies | $0.0352 | $0.0244 | $0.0596 |
| Silent Short (both video passes) | $0.0170 | $0.0264 | $0.0434 |

These figures exclude Cloud Run, storage, builds, retries and taxes. Gemini estimates use standard rates checked September 22: $0.30/M text/image/video input tokens, $1/M audio input tokens for these under-200K-token requests, and $2.50/M output plus thinking tokens. xAI reports the actual discounted charge in `usage.cost_in_usd_ticks` (divide by 10^10). IAM itself has no charge. Sources: [Google pricing](https://cloud.google.com/vertex-ai/generative-ai/pricing), [xAI cost tracking](https://docs.x.ai/developers/cost-tracking), [IAM pricing](https://cloud.google.com/iam/pricing).

App-facing authenticated checks completed for the Chinese beef video and silent Short: normal queued imports reached `ready` in 121 and 57 seconds, saved private cookbook recipes, and decoded in the actual Swift models. The beef recipe preserved Chinese speech, English translation and both pressure-release instructions. The later frame audit identified the Short's visual-order issue described above; a saved/decodable recipe alone is not a semantic accuracy test. Both temporary accounts and their test recipes/settings/imports were deleted through the normal deletion flow; operational AI-run records and deletion tombstones remain. One earlier test assertion failed after a successful beef import, so these checks consumed three attempts in total. The shared beta allowance now has **two import attempts remaining**; its limit was not raised or reset. Subsequent diagnostic jobs use an in-memory cookbook and do not reserve app attempts, but their AI calls are still billed. New video-observation UI requires an app build; the backend recipe import itself remains compatible with existing clients.

Official API reference: [Vertex AI public YouTube video input](https://docs.cloud.google.com/vertex-ai/generative-ai/docs/samples/googlegenaisdk-textgen-with-youtube-video).
