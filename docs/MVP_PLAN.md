## September 16 update: manual preparation and continuous guidance

Before cooking, users manually select ingredients (individually or in bulk), confirm equipment and product labels, review servings and supported ratio adjustments, and see a ready summary. Changed amounts must be confirmed again. Voice recipe search opens this checklist; voice tools cannot mark preparation complete. Existing cooking sessions keep their saved progress.

During cooking, readiness cues stay inline with Done and Not yet controls. Explicit spoken completion reports need no second confirmation. Approximate checks cover untimed actions as well as cooking timers; unanswered prompts do not block later checks. Not yet schedules another check, pausing guidance suppresses coaching, and time alone never advances the recipe. Timers no longer trigger a notification-permission pop-up; background reminders remain available when already authorized.

# Oui Chef — iOS MVP plan

Status: implementation started, September 14, 2026. This document describes the full planned product; [README.md](../README.md) records what the current runnable iOS slice implements and what remains. The repository initially contained three PNG design boards and no application code.

Provider decision updated: the user enabled Firebase Blaze and selected **xAI voice with $17 prepaid testing credit**, for the proof of concept only, followed by a planned switch to OpenAI voice on pay-as-you-go billing. The current implementation uses a Cloud Run relay, a provider adapter, signed-in Firebase accounts, and a server-owned usage ledger. [Voice setup](VOICE_SETUP.md) supersedes the earlier provider/credential-backend proposals below. The saved secret is bound and a live tool-to-spoken-answer probe passes; iPhone testing, account sync, and production signup remain planned work.

## September 15 scope update

The three starter recipes (spaghetti, bread, margarita) remain in the **Free** category under **Anonymous Chef**, available without an account. Current account work adds Google, email/password, and US phone sign-in. Apple configuration is deferred at the user's request. Preferences/history remain local and isolated per account; sign-in does not yet provide cloud sync.

Future expansion, recorded rather than implemented:

- Chefs import **structured recipe JSON**, validated against the executable recipe schema before publication.
- Each chef recipe pack gets its own versioned system prompt, constrained by the same cooking engine, ingredient safety checks, and ratio confirmations.
- Access to paid chef packs uses **recurring subscriptions** through Apple's in-app purchase system. Billing, verified entitlements, restore purchases, imports, and chef publishing are deferred until the pack release.
- Keep creator identity, recipe style, and access tier separate when introducing packs. Anonymous Chef is the starter collection's attribution; pasta/bread/tequila remain specialist styles.

## 1. Recommendation

Build a native SwiftUI cooking companion around three curated, versioned recipes. A small deterministic Swift execution engine owns progress, ingredient readiness, checkpoints, ratio calculations, and timers. Style-specific agents, each configured by a system prompt, own conversation and propose typed commands to that engine. Persist cooking state independently of the model's conversation history.

The executable-recipe idea is sound. The first version needs a constrained graph, not an arbitrary programming language. Start with actions, waits, and checkpoints; dependencies express parallel work. Preserve ingredient and intermediate-state IDs. Add general subrecipe invocation and modifier composition when actual recipes need them.

Initial assumptions: iPhone, iOS 17+, English, one active cooking session on one device, curated recipes, no subscriptions. Confirmed scope: foreground cooking first, with continuous listening after explicit voice activation. Lock-screen voice is deferred; timers and scheduled reminders continue when the app leaves the foreground.

## 2. Product flow and design changes

The boards in `designs/` establish cream backgrounds, sage green controls, orange primary voice actions, serif headings, food photography, and a central voice orb. Preserve that direction using SwiftUI, SF Symbols, Dynamic Type, VoiceOver labels, reduced-motion support, and large touch targets.

### Onboarding and signup

Design constraint: preference selection should fit on one screen without vertical scrolling at the default text size. Use short pages, compact choice grids, and a fixed Continue button; allow scrolling on smaller screens or with larger accessibility text so every option remains reachable.

1. Welcome and a short explanation of hands-free cooking.
2. Dietary restrictions and a distinct allergy screen/section. Offer explicit “none” and “prefer to skip”; missing answers mean unknown, not no allergies.
3. Taste profile: spice, sweetness, salt preference, dislikes, cuisines, skill level, and metric/US units. Defaults are neutral and editable.
4. Kitchen equipment: stove, oven, pans, mixer, shaker, and practical alternatives relevant to the three recipes.
5. Offer optional Google/email/phone sign-in from welcome and Profile; allow guests to cook all free recipes. Apple activation and preference/history cloud sync are deferred. Cloud voice requires account sign-in; guests retain manual cooking and local voice. The backend supports three independent simultaneous cooking conversations.
6. Explain voice processing, then request microphone access when the user activates voice. Offer a short practice exchange. Request notifications when starting the first timer. Declining permissions retains the touch workflow.

Taste preferences influence recommendations and approved adjustments. Never silently change salt, hydration, yeast, or other structural baking quantities because of a slider. Allergies and dietary exclusions filter recipe selection and substitutions; they are separate from ranking preferences.

Firebase's Apple authentication requires Apple-side configuration and enabling the provider in Firebase. [Firebase Apple authentication](https://firebase.google.com/docs/auth/ios/apple)

### Discovery → readiness → cooking → completion

- **Home/recipes:** show the three actual recipes, search, metadata filters, and “Ask Oui Chef.” With three entries, Home and Recipes can share the same catalog data and filtering code. Saved can be a filter; no separate recommendation service.
- **Voice discovery:** “Find something quick,” “I want to bake bread,” or “Make a margarita for two.” Search only the published catalog and explain when no recipe fits. Confirm the choice before starting a session.
- **Recipe detail:** ingredients, equipment, base yield, supported serving changes, active/elapsed time estimates, dietary/allergen information, and source. Hide ratings, nutrition, popularity, or claims that lack real data.
- **Before you start:** confirm servings, validate restrictions, then check ingredients and equipment. Checkmarks begin empty. “I have everything” can confirm the visible list explicitly; do not assume a pantry. Record missing items, approved replacements, and optional omissions. Required unresolved items block cooking.
- **Cooking:** show the current focused task, other active tasks, all timers, next eligible task, and a compact conversation area. Support “repeat,” “done,” “what's next?”, “how much flour?”, “where are we?”, “pause,” and “resume.”
- **Completion:** confirm the final checkpoint, save the result/history, and offer optional feedback. Continuing cleanup/cooling timers stay visible until explicitly resolved.

Changes to the mockups:

- Replace ambiguous “Skip to next step” with “Done / Continue.” Inspecting another step never completes it. Skipping an optional step is explicit; required checkpoints cannot be bypassed with navigation.
- Replace “Step 4 of 8 / 50%” as a time promise with a named phase and completed-task count. Parallel tasks and waiting make task count different from elapsed progress.
- Give the orb a visible status: connecting, listening, speaking, muted, reconnecting, or offline. Animation alone is insufficient.
- Put pause guidance, microphone mute, and end session on distinct controls.
- Remove generic timer pause buttons from proofing/heating processes. An app button cannot pause fermentation or heat.
- Replace “Your voice stays private” with specific processing and retention copy. Cloud voice sends audio off-device; do not imply on-device-only processing.
- Defer the camera answer screen. The first release asks users to report texture/color/volume; it does not claim vision has verified readiness.

## 3. Recipe model

Normalize identities and relationships while packaging each recipe version as one fetchable document. Firestore does not require one collection for every conceptual entity.

| Concept | Fields / purpose |
| --- | --- |
| Recipe version | Stable recipe ID, immutable version, schema version, title, description, locale, base yield, metadata, source, review status |
| Ingredient use | Recipe-scoped ID, canonical food ID, quantity/unit, preparation, optional flag, approved alternatives, scaling rule |
| Food definition | Canonical name, aliases, known allergens, compound-food constituents, completeness/source of that information |
| Ingredient state | ID, label, originating ingredient uses, producing node, quantity/portion when material is split |
| Tool requirement | ID, required/optional status, approved alternatives, capacity where relevant |
| Action node | ID, input/output IDs, action, typed parameters, dependencies, instructions, completion criteria, confirmation requirement |
| Wait node | ID, dependencies, timer-definition reference, readiness checkpoint reference |
| Checkpoint node | ID, dependencies, prompt, accepted observations, pass outcome, recheck policy |
| Timer definition | Stable ID, associated node, target seconds, reminder offsets, whether the physical process can actually pause |
| Cooking session | Pinned resolved recipe, servings/preferences snapshot, ingredient readiness, node states, timer instances, event history |

Use distinct `schemaVersion` and `recipeVersion`: a corrected instruction is different from changing the data format. Published versions are immutable; sessions keep their resolved snapshot so later edits cannot change an in-progress loaf.

Keep structured values and human instructions separate. Units use explicit identifiers, durations use seconds, and temperatures specify C/F. Avoid free-form strings where the runtime needs arithmetic or validation.

Illustrative graph fragment, not a complete executable recipe:

```json
{
  "id": "knead_dough",
  "kind": "action",
  "action": "knead",
  "dependsOn": ["mix_dough"],
  "inputs": ["mixed_dough"],
  "outputs": ["kneaded_dough"],
  "instruction": {
    "short": "Knead the dough.",
    "detailed": "Knead until smooth and elastic."
  },
  "durationEstimateSeconds": 480,
  "completionCriteria": [
    {"kind": "sensory", "attribute": "texture", "expected": "smooth and elastic"}
  ],
  "requiresConfirmation": true
}
```

### Graph rules

- Use an acyclic dependency graph for the MVP. A node becomes eligible when all required dependencies and input states are satisfied. Stable display order chooses what to suggest among eligible tasks.
- An action is complete only when the user confirms completion, including any required observation. Reading or hearing its instruction does not start a physical timer; “it's in the oven” does.
- A timer reaching zero makes a check due. It does not prove food readiness or automatically complete a downstream checkpoint.
- A failed proofing check keeps the checkpoint unresolved and schedules another check with a new attempt ID. This handles repeated checks without graph cycles or running earlier actions again.
- Split material into named portions when parallel tasks consume different amounts. Prevent two nodes from consuming the same exclusive portion. Derived states do not count as new shopping ingredients.
- Model tools used concurrently and their capacity. The suggested next task must not assume a second pot or occupied oven is available.
- Before publishing, validate unique IDs, all references, graph acyclicity, reachable outputs, input producers, tool references, quantities/units, valid timer values, and complete checkpoints.

### Scaling, components, and modifiers

Implement linear, fixed, ratio-based, and to-taste quantities with explicit supported serving ranges. Piece counts round according to the authored rule. Never multiply all cooking durations by serving count. Pan/shaker capacity can require batches. Serving scaling and ratio adjustment are different operations: changing the balance of a drink should not accidentally double the drink.

Bread initially offers the authored loaf size; additional loaf/pan sizes require tested profiles. Ratio changes within that size, such as hydration, use recipe-specific supported ranges and must update affected guidance. Margaritas support adjustable ingredient ratios and liquid amounts while preserving per-batch shaking guidance. Spaghetti scaling includes pot/pan capacity checks and adjustable sauce-to-pasta balance.

Design recipe references as `recipeID + immutable version + input/output bindings + required quantity`. Later, resolve subrecipes into a session snapshot with namespaced IDs and reject circular references. Do not build this resolver for three self-contained recipes.

Initial variations are explicit approved choices, such as omitting an optional garnish or selecting a documented tool alternative. General “add potatoes” requires authored steps, dependencies, timing, and validation; free-form model-generated graph patches are outside the MVP.

## 4. Three launch recipes

| Recipe | Proposed content | What it proves |
| --- | --- | --- |
| Spaghetti with tomato sauce | Ingredient/tool check → prepare sauce and boil water in parallel → cook/check pasta → combine → serve | Dependencies, concurrent timers, sensory doneness, serving changes |
| Basic yeasted bread | Ingredient/tool check → mix → knead/check → first proof/check → shape → second proof/check alongside oven preheat → bake/check → cool | Long sessions, named proofing stages, retries, recovery, timers surviving voice reconnects |
| Classic margarita | Ingredient/tool check → measure → combine → shake/check → strain → optional garnish | Short session, voice discovery, batch capacity, quantity/unit handling |

These are content outlines, not kitchen-validated cooking instructions. Before release, author exact quantities, criteria, realistic duration ranges, source/licensing, and tested equipment alternatives; cook each recipe with the app. Mark the margarita as alcoholic and exclude it for users avoiding alcohol. An alcohol-free version needs its own reviewed formulation.

Metadata v1: aliases, cuisine, dish type, meal, active-time estimate, elapsed-time range, difficulty, primary ingredients, techniques, tools, dietary tags, known allergens, alcohol flag, supported yields, and source. Search uses local text matching and filters over the three entries. No embeddings or external search index yet.

Derive ingredient count, tool list, known allergens, and techniques from the resolved recipe. Elapsed time follows the critical path and checkpoint ranges, not the sum of every parallel task. Dietary claims require complete enough ingredient information; missing data cannot become a positive safety claim.

## 5. Execution, persistence, and timers

Implement one Swift `CookingSession` model and one serialized command handler, shared by touch and voice. Suggested commands: search/select recipe, propose/confirm ratio adjustment, confirm ingredient/tool, start action, confirm completion/checkpoint, extend timer, pause/resume guidance, and get session status. Supply schemas to the voice model; validate every command in Swift.

For each mutation: verify recipe/session IDs, command arguments, expected session revision, prerequisite state, and any required confirmation; deduplicate command IDs; update and persist the snapshot and small event record atomically. Return the resulting state to the model before it announces success. Reject stale commands and send fresh state. “Yes” applies only to the currently pending confirmation, never an arbitrary earlier question.

Node states: pending, active, awaiting confirmation, completed, skipped (optional only). Session states: preparing, cooking, guidance paused, completed, abandoned. Audio connection state is independent.

Keep an atomic local Codable session file as the active device's durable record, including recipe snapshot and timer deadlines. Sync changes to the user's Firestore session when available. Firestore also offers persistent offline caching on Apple platforms, but it uses last-write-wins conflict behavior; do not use this as an active multi-device coordination protocol. MVP sessions have a single controlling device and no live handoff. [Firestore offline behavior](https://firebase.google.com/docs/firestore/manage-data/enable-offline)

Timer instances contain timer ID, node ID, attempt ID, start time, deadline, status, actual pause intervals when supported, and notification IDs. Persist state changes rather than writing each countdown tick. Derive the visible countdown from time. Use a monotonic clock while running and persisted wall-clock deadlines after relaunch; detect major clock changes and ask the user to verify ambiguous timing rather than silently inventing elapsed time.

| User action | Guidance | Microphone | Cooking timers |
| --- | --- | --- | --- |
| Pause recipe / guidance | Stops advancing and stops current narration | Continues listening if voice is enabled | Continue |
| Resume | Warm check-in grounded in saved state; reconcile what happened while away before continuing | Continues | Continue |
| Mute / stop listening | Touch controls remain available | Capture and transmission stop | Continue |
| Silence current speech | Current playback stops | Continues listening | Continue |
| End voice conversation | Voice connection closes | Off | Continue; cooking session remains |
| Lock phone / leave app | Paused and persisted | Voice connection closes; capture stops | Continue through persisted deadlines and scheduled reminders |
| End cooking | Session is completed or abandoned explicitly | Off | Show unresolved processes and explicitly decide which reminders remain |

Schedule local notifications at timer start and reschedule on extension/cancellation. Notifications are reminders, subject to permission and device settings. On relaunch, reconcile overdue timers immediately and show time overdue. Do not depend on continuous background code or Firebase pushes to advance a timer. [Apple local notifications](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)

## 6. Voice architecture and iOS behavior

Proposed first provider: OpenAI Realtime over WebRTC, with a small Firebase HTTPS endpoint that checks Firebase Auth and App Check before issuing short-lived client credentials. Keep the permanent provider key in server secrets. Audio goes directly between the iPhone and provider; Firebase holds structured app data. WebRTC is useful here for conversational media handling; choose a maintained native distribution during the device spike rather than inventing transport infrastructure. [OpenAI WebRTC guidance](https://developers.openai.com/api/docs/guides/voice-webrtc)

A viable alternative is Gemini Live through Firebase AI Logic, which has a Swift integration but is documented as Preview. It may reduce integration work. Compare it only if the first provider fails latency, tool reliability, cost, or device requirements; do not ship two providers in v1. [Firebase Live API](https://firebase.google.com/docs/ai-logic/live-api)

Voice behavior:

- One activation begins a conversation; the user does not hold a button for every utterance. Listen while the assistant speaks and support interruption without interpreting speaker echo as user speech.
- “Stop” immediately silences speech and pauses guidance; the UI clearly indicates whether listening remains enabled. “Stop listening” mutes capture. A muted app cannot hear “resume”; provide a visible resume control.
- Questions are answered using the pinned recipe and current session snapshot. Unclear progress statements trigger clarification, not silent advancement.
- Ground quantity answers in the selected yield and ingredient use. Default to attentive, hand-held guidance: brief instructions, concrete readiness cues, and room for the user to respond. Offer longer explanations on request.
- Reconnect with current task states, timers, pending confirmation, and recent structured events. Never ask the model to reconstruct progress from memory.
- Long recipes outlive provider connections. OpenAI currently documents a 60-minute Realtime session limit; rotate connections and restore state. An entire bread recipe must survive multiple connections. [Realtime conversation lifecycle](https://developers.openai.com/api/docs/guides/realtime-conversations)
- Keep listening during explicitly enabled sessions, including guidance pauses. Offer a clearly labeled quiet-wait mode that disconnects voice for long proofing waits; do not silently substitute it for continuous listening.
- Offline mode retains instructions, touch progress, timers, and optional native speech playback. Cloud conversation shows as unavailable.

Use `AVAudioSession` with `playAndRecord`, appropriate voice processing, and interruption/route-change handling. For v1, stop capture/playback and close the voice connection on backgrounding or screen lock, while persisting cooking progress. Show “Resume voice” on return and recap outstanding tasks/timers after activation. Offer an explicit keep-screen-awake setting during foreground cooking; restore normal idle behavior afterward. No audio background mode is needed for this scope. Apple's recording consent and indicator requirements still apply. [Apple audio sessions](https://developer.apple.com/documentation/avfaudio/avaudiosession), [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)

Test iPhone speaker, AirPods, phone calls, Siri interruptions, route changes, screen lock, poor connectivity, noisy extraction fans, long silence, and force quit/relaunch. Verify backgrounding stops recording and leaves timer deadlines intact. Do not restart microphone capture after explicit mute or on relaunch without user activation. When iOS interrupts recording, show that listening has stopped and require a clear recovery path. Future lock-screen voice requires its own background-audio implementation and device/review validation.

### 6.1. Style-specific agents and system prompts

Confirmed requirement: one agent identity/system prompt for each cooking style. Start with a Pasta Chef, Bread Baker, and Tequila & Cocktails specialist. Each recipe version declares an `agentProfileID`; the server selects the corresponding versioned prompt. A short discovery prompt handles recipe search before the choice is known.

Use one voice connection and the same execution engine, loading the relevant specialist prompt. There is no need for simultaneous agents talking to one another. Preserve the cooking snapshot when switching prompts, cancel pending mutations from the previous specialist, and require explicit recipe selection before switching the active recipe. For a side question outside the current specialty, answer without losing cooking context or changing recipes.

The effective system instructions combine a shared cooking contract, the chosen specialist prompt, and structured context. Treat recipe/user text as data, never as privileged instructions. Keep authoritative prompt files and allowed profile mappings server-side; pin prompt versions in session/usage records. Begin with three source-controlled Markdown prompts, not a prompt editor or provider abstraction.

**Shared cooking contract — starter prompt:**

> You are Oui Chef, a hands-free cooking companion. Use the supplied recipe and live session state as the source of truth. Speak briefly and offer one actionable instruction at a time. Answer questions without advancing progress. Use tools to propose changes; only report a mutation as successful after the tool confirms it. Never infer that the user completed a task because you described it. Check required ingredients and tools before cooking. Confirm readiness using the recipe's criteria. Treat allergies and dietary exclusions as constraints, and unknown ingredient composition as unknown. Explain ratio adjustments in ordinary language and obtain confirmation before applying them. Preserve timers and completed actions. If a request is ambiguous, ask one short clarifying question.

> Be a warm, attentive cooking partner. When the user turns voice back on, welcome them back and ask how the current task is going, using the actual saved state. During active cooking and waits, offer occasional useful cues about what to look for and invite the user to tell you what they notice. Tie each cue to the recipe's completion criteria. Leave space to cook and answer; do not repeat reminders just to fill silence. Never claim to see, smell, or verify the food. When the user reports a problem, acknowledge it and offer one appropriate next action from the recipe's supported guidance. Respect requests for quieter guidance.

| Agent | Starter specialist system prompt | Ratio capabilities |
| --- | --- | --- |
| Pasta Chef | “You specialize in pasta and sauces. Coordinate sauce preparation with pasta cooking using eligible tasks. Use the recipe's texture and consistency checks. When adapting sauce balance, use actual quantities and the amount of pasta being cooked. Distinguish ingredients still available from ingredients already in the pan.” | Sauce-to-pasta balance; supported liquid/fat/acidity adjustments; serving changes within equipment capacity |
| Bread Baker | “You specialize in bread. Name every proofing stage explicitly. Use flour mass as the basis for baker's percentages where the recipe specifies them. Explain the effect of supported hydration changes on handling and timing estimates. Never claim elapsed time alone proves readiness, or alter structural ingredients solely from a taste preference.” | Hydration and other authored baker's percentages within supported ranges; distinguish total flour/water in compound components |
| Tequila & Cocktails | “You specialize in tequila drinks and cocktail balance. Distinguish tequila, citrus, sweetener, liqueur, and dilution. Clarify whether the user wants different flavor balance, serving size, or alcohol strength. Calculate through tools, respect shaker capacity, and never describe a stronger drink as lower in alcohol.” | Tequila/citrus/liqueur ratios; sweetness adjustments; fixed-total-volume or fixed-base-ingredient calculations; batch size |

Prompts guide expertise and communication. All specialists use the same validation, quantity calculations, timer semantics, and allergy constraints. A prompt alone cannot guarantee correctness.

### 6.2. Flexible ratio adjustments

Support conversational requests such as “more sauce,” “less sweet,” “keep the same amount of tequila but reduce the liqueur,” or an explicit numeric ratio. Accept continuous values within the recipe's supported bounds, rather than limiting users to a few named presets. When “more” is ambiguous, propose a concrete small adjustment for confirmation or ask for a quantity.

Each adjustable recipe parameter records:

- Ingredient-use IDs and a basis: relative parts, percentage of a base ingredient, or amount per unit of another ingredient.
- What remains fixed: the base ingredient quantity, final total quantity, or number of servings. Make this visible in the confirmation.
- Supported range, measurement dimension, rounding precision, and equipment/batch limits. Do not invent universal ranges for all recipes.
- Affected instructions, state quantities, readiness checks, and any expected texture/handling changes.

The specialist calls `proposeAdjustment` with the requested target and basis. Swift calculates a draft containing old/new quantities and the delta still to add. It validates ingredient restrictions, units, supported ranges, equipment capacity, completed actions, and the current session revision. The UI/agent reads the concrete changes; `confirmAdjustment` applies that exact draft once and records it. Revalidate if anything changed while the user was considering the proposal.

Illustrative arithmetic, not a tested margarita formulation: an existing tequila/liqueur/lime ratio of `2:1:1` with tequila fixed at `60 mL` means `60/30/30 mL`. Changing the ratio to `2:0.75:1` gives `60/22.5/30 mL`. If total volume were fixed instead, every quantity would be recalculated; do not silently choose between these meanings. Sweetness also depends on the specific ingredients, so reducing a liqueur's volume is not a precise sugar-content calculation.

For relative parts at fixed total, compute `amount = total × part / sum(parts)`. At fixed base amount, compute `amount = baseAmount × part / basePart`. Baker's percentages use the authored base flour mass. Validate finite positive bases, nonnegative quantities, nonzero denominators, dimensional compatibility, and valid measurement precision. Convert units within the same dimension; mass-to-volume conversion requires an ingredient-specific density, and syrup-strength changes require known concentration.

Mid-cooking constraints matter: once `30 mL` of liqueur is mixed in, the app cannot reduce it to `22.5 mL`. Explain that limitation and offer a feasible rebalancing proposal using additional ingredients, a larger batch, or a fresh batch. Recheck available ingredients and capacity before accepting additions. Similarly, liquid already incorporated into dough cannot simply be subtracted. Known completed quantities remain in session history.

Persist the user's accepted adaptation as a session-specific resolved recipe revision, with original recipe version, specialist/prompt version, requested ratio, chosen basis, calculated quantities, and confirmation event. Keep the published base recipe unchanged. Ask separately before saving the adaptation as a future preference.

For requests outside the authored operating range or requiring new ingredients/steps, explain the limitation and offer a reviewable alternative; do not silently invent a validated recipe. The first release supports real parameter adjustments, while arbitrary graph rewriting remains deferred.

### 6.3. Personable return and proactive coaching

Confirmed requirement: hand-held guidance is the default. The specialist should help the user assess progress throughout cooking, including while a timer runs. Its personality comes through natural phrasing and attention to what the user has said.

**When voice is turned back on:**

1. Restore the session and reconcile elapsed/overdue timers before speaking. Check for any pending readiness question.
2. Offer a brief welcome and one relevant question: “Welcome back! How's the sauce coming along—is it starting to thicken?” For bread: “Hey, welcome back. We're on the second rise—how's the dough looking?” Only name a phase that the saved state supports.
3. Prioritize an overdue check: “Welcome back—the pasta timer finished while we were away. Have you checked its texture yet?” Avoid burying that information behind small talk.
4. Wait for the answer. If the user cooked ahead, reconcile their reported actions and any required criteria through the normal command handler before advancing. Do not blindly restart narration or assume progress during the absence.

A short automatic network reconnect does not trigger another welcome every time. Resume interrupted conversation gracefully; use the full check-in for an explicit return or a material gap in cooking context. If no recipe is active, ask what the user would like to make.

**While cooking or waiting:**

- At task start, explain the target: “We're looking for lightly golden edges. Let me know when you start seeing that.” This wording is illustrative and only applies to a step with that authored target.
- At a recipe-authored observation point, ask one specific question: “How's the color now—still pale, or getting golden?” Tie this to the active task, not just any running timer.
- Near a readiness check, invite the relevant observation: “The timer is nearly up. Let's check the texture before moving on.” A timer never substitutes for that observation.
- For a long proof, offer a concise cue about the recipe's rise target, then leave longer quiet periods. Short tasks do not need multiple interjections.
- Respond to the user's observation with an appropriate authored next action or recheck. If the user reports an unexpected result, ask what is happening and acknowledge uncertainty rather than assuring them that everything is correct.

Add a small optional `coachingCues` list to action/wait definitions: stable cue ID, trigger offset or node event, relevant completion-criterion ID, and instruction/prompt intent. The engine decides when a cue is due; the selected specialist phrases it naturally using current state. Reuse the existing timer/event handling rather than adding a separate coaching service.

Before speaking, check that the task is still active, the cue remains relevant, foreground voice/guidance is enabled, the user is not speaking, and no other question awaits an answer. User speech and due readiness checks take priority. Drop stale cues instead of replaying a backlog after resume; coalesce competing timer prompts into one brief check-in. Persist spoken cue IDs with the session so reconnects do not repeat them. If playback is interrupted, retain the pending question rather than treating it as answered.

Silence is not confirmation. Keep required checkpoints unresolved; allow one gentle recipe-appropriate follow-up rather than repeated escalating prompts. Optional coaching never changes cooking state or timer deadlines. Paused guidance, muted voice, quiet-wait mode, and backgrounding suppress unsolicited coaching; existing timer reminders remain independent.

Support “talk me through it” and “less talking” as a simple guidance preference. Detailed guidance is the default; quieter guidance removes optional tips while keeping essential instructions and required readiness checks. Record coaching offered/answered/dismissed as consented event types without storing the user's raw response in analytics.

## 7. Firebase and backend

Use Swift Package Manager for the Firebase Apple SDK. Proposed services: Authentication, Firestore, Analytics, Crashlytics, App Check, and one small TypeScript Cloud Functions backend for voice credentials and account-data deletion. Bundle the three initial recipe assets; Cloud Storage is unnecessary until remote content updates need it.

```text
recipes/{recipeID}                         # discovery metadata + current version
recipes/{recipeID}/versions/{versionID}    # immutable execution package
foods/{foodID}                            # curated identities and constituent data
users/{uid}                              # preferences, settings, onboarding status
users/{uid}/sessions/{sessionID}          # compact session snapshot
users/{uid}/sessions/{sessionID}/events/{eventID}
users/{uid}/savedRecipes/{recipeID}
voiceSessions/{voiceSessionID}            # server-owned issuance/usage status
```

Embed small arrays/maps of nodes, ingredients, states, tools, and timer definitions inside each version. Embed the few active timer instances in the session snapshot. Events live separately to keep document size bounded. Source-controlled seed JSON is the authoring workflow; no admin CMS initially.

Security requirements for implementation:

- Published catalog content is readable; only trusted publishing code can write recipe/food definitions.
- User data is isolated by authenticated UID, with allowed-field/type/size validation. Deny access by default elsewhere.
- Credential issuance verifies Auth, App Check, request limits, and allowed configuration. App Check complements authentication; it does not replace authorization. [Firebase App Attest](https://firebase.google.com/docs/app-check/ios/app-attest-provider)
- Client-supplied prompt/model settings cannot widen the server's permitted configuration. Avoid general Firestore-write tools exposed to the model.
- Account deletion includes nested sessions/events, saved recipes, applicable usage identifiers, and authentication cleanup; deletion must be retryable.
- Allergy checks expand known compound ingredients and approved replacements, including optional garnishes. Record unknown composition and label-check requirements explicitly. Ingredient metadata cannot establish absence of cross-contact.

### Provisioning scope

Created during planning: **Oui Chef Dev**, project ID `oui-chef-dev-20260914`, project number `172500657212`. [Open Firebase console](https://console.firebase.google.com/project/oui-chef-dev-20260914/overview). The repository's `.firebaserc` points to this project. During implementation, the user selected `com.xie.ouichef`; the iOS app was registered in Firebase and its configuration downloaded to `Configuration/GoogleService-Info.plist`. No billing account has been attached, database created, or backend deployed. The current local app does not yet link the Firebase SDK.

Create one development project initially. Register the iOS app after choosing the real bundle identifier and Apple team; Firebase's registered bundle identifier cannot be changed for that app. Create production separately before public release. [Firebase Apple setup](https://firebase.google.com/docs/ios/setup)

Choose a Firestore location based on the initial audience before database creation; assume a US audience for planning only. Configure production access rules before loading user data. Set up emulator checks before deployment.

Cloud Functions deployment requires Blaze billing. Creating a project alone does not deliver a running voice backend. Budget approval and a provider account/key are implementation prerequisites; do not promise a free hosted voice product. [Firebase Functions pricing requirements](https://firebase.google.com/docs/functions/quotas)

## 8. Usage tracking

Track three separate things so elapsed cooking time is not mistaken for AI usage:

| Layer | Events / measurements | Purpose |
| --- | --- | --- |
| Product analytics | Onboarding stage completed, recipe viewed/selected, readiness started/completed, cooking started/completed/abandoned, voice activated, reconnect, checkpoint retry | Activation funnel, recipe completion, friction, retention |
| Operational telemetry | Crash-free sessions, connection failures, command rejection reasons, response latency, notification scheduling errors | Reliability |
| AI usage | Issued voice-session ID, model, connected seconds, input/output audio/text usage where reported, finalization status, estimated cost | Cost per cooking session and completed recipe |

Define activation as readiness completed plus first cooking action confirmed. Report completion rate by recipe/version, median time to start, checkpoint retry rate, voice failure rate, and seven-day return among users with analytics consent. Split active cooking minutes, elapsed waiting minutes, and connected voice minutes.

Use Firebase Analytics for consented product events and Crashlytics for diagnostics. Keep raw utterances, recordings, allergy values, and free-text preference values out of analytics and crash logs. Default product analytics collection off until the user chooses; restore the choice at startup. [Firebase analytics collection controls](https://firebase.google.com/docs/analytics/ios/configure-data-collection)

The backend records credential issuance with a server timestamp and rate-limits issuance per UID. Initial client-reported provider usage is useful telemetry but untrusted and potentially incomplete; label estimates and reconcile aggregate spend with provider reporting. Do not use client totals as subscription billing or a hard quota. Before selling usage allowances, collect provider events through a server-controlled connection and enforce session termination there. Server-side voice controls can observe/manage the same session. [OpenAI server-side controls](https://developers.openai.com/api/docs/guides/voice-server-controls)

Do not invent a monthly price estimate before a voice spike. Measure a short drink, a pasta session, and bread with long waits. Estimate `sessions × measured usage per session × current provider rates`, then include backend costs. Token expiry controls credential validity, not necessarily an existing connection's duration. Issuance limits and budget alerts are not a hard ceiling on active-session spend.

Proposed retention: no app-stored raw audio or full transcript by default; retain structured cooking history until user deletion; remove detailed diagnostic/usage events after a defined short window, initially 30 days. Document provider retention separately before release. The small excerpt shown during conversation can stay in memory.

## 9. Delivery sequence and acceptance gates

| Phase | Deliverable | Acceptance gate |
| --- | --- | --- |
| 1. Device voice spike | One physical-iPhone screen, conversation, interrupt, mute, lock/unlock, one persisted timer | Resume correctly after interruption/reconnect; know voice latency, battery behavior, and cost of long silence |
| 2. Cooking core + content | Swift models, JSON recipes, validator, ratio calculations, engine, local persistence | All three graphs traverse; proofing stages stay distinct; checkpoint retries work; ratio basis and already-added quantities are respected |
| 3. Main UI + onboarding | Design-based signup/preferences, discovery, detail, readiness, cooking, history | Voice/touch select the same recipes and use the same commands; readiness blocks unresolved required items; permissions can be denied |
| 4. Cloud + integrated voice | Auth, Firestore sync/rules, credential endpoint, three specialist prompts, contextual return check-ins, proactive coaching, grounded tool calls | Correct specialist loads; check-ins reflect saved progress; cues respect conversation/paused state; confirmed adjustments persist; cross-user access fails; local cooking survives outage |
| 5. Measurement + TestFlight | Usage dashboards, diagnostics, content review, release preparation | Real cooks finish each recipe; no checkpoint auto-completes from elapsed time; cost and failure rates are measurable |

Rough planning estimate: 4–6 focused engineering weeks for one experienced iOS developer, including device work and recipe testing. This is an estimate, not a commitment; Apple configuration, provider access, and voice reliability results can change it. The first checkpoint should be a working device slice in a few days, before polishing every screen.

Minimum meaningful automated coverage during implementation: graph validation; proofing retry + recovery; guidance pause leaves physical timers running; duplicate/stale command rejection; missing/unknown compound ingredients do not pass validation; ratio adjustments preserve the chosen basis and cannot subtract already-mixed ingredients; specialist selection does not reset state; owner-only Firebase access. Add one end-to-end UI smoke flow. Test microphone/audio behavior on hardware rather than treating simulator results as sufficient.

Coaching acceptance checks: returning to an overdue timer prioritizes its readiness check; returning mid-proof names the correct stage; user speech interrupts a tip; completing a task cancels its pending cues; reconnecting does not repeat delivered cues; paused/muted/background sessions receive no unsolicited coaching; silence never completes a checkpoint.

## 10. Deferred work and decisions

Defer lock-screen voice, camera checks, arbitrary recipe import/generation, universal substitution, a general modifier engine, advanced scaling formulas, nutrition estimates, shopping integrations, social ratings, multi-device live handoff, and subscriptions. Add these when real usage shows the need and the underlying content can support them.

Remaining setup inputs: Apple team, approved cloud/voice spending budget, provider account, and first deployment audience/location. The user selected bundle identifier `com.xie.ouichef` and confirmed foreground-only voice for the first release.

The MVP succeeds when a user can choose one of the three recipes by voice, verify readiness, cook hands-free, pause and return, and trust that Oui Chef remembers exactly what they actually completed.
