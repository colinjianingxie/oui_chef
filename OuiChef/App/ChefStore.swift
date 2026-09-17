import Foundation
import Observation
import UserNotifications

@MainActor @Observable
final class ChefStore {
    private(set) var catalog: RecipeCatalog?
    private(set) var archive = AppArchive()
    var error: String?
    var notificationNotice: String?
    var chefMessage = "What sounds good today? Let's make something together."
    var selectedRecipeID: String?
    var voice = GuidedVoice()
    var showingVoice = false
    var foreground = true
    private var canPersist = true
    private var notificationTask: Task<Void, Never>?
    private var coachingTask: Task<Void, Never>?
    private var handlingVoiceTool = false
    private var voiceToolResults: [String: String] = [:]
    private var voiceProposal: RatioProposal?
    private var ratioConfirmation: VoiceConfirmation?
    private var stepStartConfirmations: [String: VoiceConfirmation] = [:]
    private let storage = KitchenStorage()
    private var accountID: String?

    var session: CookingSession? { archive.session }
    var preferences: ChefPreferences { archive.preferences }
    var recipes: [Recipe] { catalog?.recipes ?? [] }

    init(accountID: String? = nil) {
        self.accountID = accountID
        do {
            catalog = try RecipeCatalog.bundled()
            archive = try storage.load(accountID: accountID, catalog: catalog!)
            archive.session?.guidancePaused = true
            if let session { chefMessage = session.resumeMessage(at: Date()) }
        } catch {
            canPersist = false
            self.error = "Your saved kitchen could not be loaded. It has been preserved. \(error.localizedDescription)"
        }
        voice.onCommand = { [weak self] text in self?.handle(text) }
        voice.context = { [weak self] in self?.voiceContext() ?? [:] }
        voice.onTool = { [weak self] id, name, arguments in self?.performVoiceTool(id: id, name: name, arguments: arguments) ?? "{}" }
        voice.onAssistantText = { [weak self] text in self?.chefMessage = text }
        voice.onReady = { [weak self] in
            guard let self, self.foreground else { return }
            self.voiceToolResults = [:]
            self.voiceProposal = nil
            self.ratioConfirmation = nil
            self.stepStartConfirmations = Dictionary(uniqueKeysWithValues: (self.session?.activeNodes ?? []).map { ($0.id, VoiceConfirmation(target: $0.id, userTurn: self.voice.userTurn)) })
            if self.session != nil { self.resume() }
            else { self.say("Hi, I'm Oui Chef. What would you like to make: pasta, bread, or a margarita?") }
        }
        coachingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                guard let self else { return }
                self.offerCoaching()
            }
        }
    }

    func switchAccount(_ uid: String?) {
        guard uid != accountID else { return }
        let adoptGuest = accountID == nil && uid != nil
        voice.stop(); showingVoice = false; selectedRecipeID = nil
        voiceToolResults = [:]; voiceProposal = nil; ratioConfirmation = nil; stepStartConfirmations = [:]
        accountID = uid
        archive = AppArchive()
        chefMessage = "What sounds good today? Let's make something together."
        canPersist = false; error = nil; notificationNotice = nil
        do {
            guard let catalog else { throw CookingError.invalid("Recipes could not be loaded.") }
            archive = try storage.load(accountID: uid, adoptingGuest: adoptGuest, catalog: catalog)
            archive.session?.guidancePaused = true
            canPersist = true
            if let session { chefMessage = session.resumeMessage(at: Date()) }
        } catch { self.error = "This account's saved kitchen could not be loaded. It has been preserved. \(error.localizedDescription)" }
        syncNotifications()
    }

    func eraseAccountKitchen(_ uid: String) throws { try storage.delete(accountID: uid) }

    @discardableResult
    private func commit(_ edit: (inout AppArchive) throws -> Void) -> Bool {
        guard canPersist else { error = "The saved kitchen needs recovery before changes can be saved."; return false }
        do {
            var next = archive
            try edit(&next)
            try storage.save(next, accountID: accountID)
            archive = next
            if !handlingVoiceTool { voice.updateContext() }
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    @discardableResult
    func updateSession(_ edit: (inout CookingSession) throws -> Void) -> Bool {
        let oldTimers = session?.timers
        let result = commit { next in
            guard var session = next.session else { throw CookingError.invalid("Choose a recipe first.") }
            let previousCount = session.events.count
            try edit(&session)
            if next.preferences.analyticsEnabled {
                next.usage += session.events.dropFirst(previousCount).map { UsageRecord(name: $0.kind, recipeID: session.recipe.id) }
                next.usage = next.usage.filter { $0.date > Date().addingTimeInterval(-30 * 86_400) }
            }
            next.session = session
        }
        if result && oldTimers != session?.timers { syncNotifications() }
        return result
    }

    func savePreferences(_ preferences: ChefPreferences) {
        commit { next in
            if next.preferences.allergies != preferences.allergies || next.preferences.dietary != preferences.dietary || next.preferences.avoidAlcohol != preferences.avoidAlcohol {
                next.session?.labelsChecked = false
                next.session?.preparationCompletedAt = nil
            }
            if next.preferences != preferences { next.session?.record("preferences_changed", at: Date()) }
            next.preferences = preferences
            if !preferences.analyticsEnabled { next.usage = [] }
        }
    }
    func toggleSaved(_ id: String) {
        commit { next in
            if next.savedRecipes.contains(id) { next.savedRecipes.remove(id) } else { next.savedRecipes.insert(id) }
        }
    }
    func restriction(for recipe: Recipe) -> String? {
        guard let catalog else { return "The ingredient library is unavailable." }
        return catalog.restriction(for: recipe, preferences: preferences)
    }

    func choose(_ recipe: Recipe, servings: Int) {
        guard session == nil else { error = "Finish or end your current recipe before starting another."; return }
        if commit({ next in
            next.session = try CookingSession(recipe: recipe, servings: servings)
            if next.preferences.analyticsEnabled { next.usage.append(UsageRecord(name: "recipe_selected", recipeID: recipe.id)) }
        }) {
            showingVoice = false
            chefMessage = "Review your preferences and ingredients on screen, then we’ll cook \(recipe.title.lowercased()) together."
        }
    }
    func endSession() {
        guard let current = session else { return }
        voice.stop()
        if commit({ next in next.history.insert(current, at: 0); next.session = nil }) {
            chefMessage = current.finished ? "You made it. I hope every bite is a good one." : "Your cooking session has been saved to history."
            syncNotifications()
        }
    }
    func begin(_ node: CookingNode) {
        if let recipe = session?.recipe, let restriction = restriction(for: recipe) { error = restriction; return }
        if updateSession({ try $0.begin(node.id, at: Date()) }) {
            stepStartConfirmations[node.id] = VoiceConfirmation(target: node.id, userTurn: voice.userTurn)
            say("\(node.instruction) I'll check in as you go. Say done when it's ready.")
        }
    }
    func complete(_ node: CookingNode) {
        if updateSession({ try $0.finish(node.id, confirmed: true, at: Date()) }) {
            if session?.finished == true { say("You did it! How did your \(session!.recipe.title.lowercased()) turn out?") }
            else if let next = session?.eligibleNodes.first { say("Got it. Next, \(next.title.lowercased()). \(next.instruction)") }
            else { say("Got it. Let's keep an eye on the other tasks while they finish.") }
        }
    }
    func notYet(_ node: CookingNode) {
        if updateSession({ try $0.recheck(node.id, at: Date()) }) {
            say("Take your time. I'll check again. \(node.criterion)")
        }
    }
    func pause() {
        voice.cancelSpeech()
        if updateSession({ $0.pause(true, at: Date()) }) { chefMessage = "Guidance is paused. Your timers are still running. Say resume when you're ready." }
    }
    func resume() {
        if updateSession({ $0.pause(false, at: Date()) }) {
            say(session!.resumeMessage(at: Date()))
            if let node = session?.focus(at: Date()), session?.started.contains(node.id) == true {
                _ = updateSession { $0.pendingQuestionNodeID = node.id; $0.record("readiness_asked", nodeID: node.id, at: Date()) }
            }
        }
    }
    func openVoice() { showingVoice = true }
    func say(_ text: String) {
        chefMessage = text
        if foreground && voice.enabled && !handlingVoiceTool { voice.speak(text) }
    }
    func background() {
        foreground = false
        voice.stop()
        if session != nil { _ = updateSession { $0.pause(true, at: Date()) } }
    }
    func offerCoaching() {
        guard foreground, voice.isListening, !voice.isSpeaking, !voice.isResponding, !voice.hearingSpeech,
              Date().timeIntervalSince(voice.lastInteraction) > 5,
              let cue = session?.dueCue(at: Date(), detailed: preferences.detailedGuidance) else { return }
        if updateSession({ $0.deliver(cue, at: Date()) }) {
            say(cue.text)
        }
    }

    func submitText(_ text: String) {
        if voice.usingCloud { voice.sendText(text) } else { handle(text) }
    }

    func voiceContext() -> [String: Any] {
        func object<T: Encodable>(_ value: T) -> Any {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            guard let data = try? encoder.encode(value), let object = try? JSONSerialization.jsonObject(with: data) else { return NSNull() }
            return object
        }
        // Recent events are sufficient; no transcript history or analytics are sent.
        var snapshot = session
        if let events = snapshot?.events { snapshot?.events = Array(events.suffix(8)) }
        return ["now": ISO8601DateFormatter().string(from: Date()), "session": snapshot.map(object) ?? NSNull(),
                "sessionID": session?.id.uuidString ?? "none", "revision": session?.revision ?? 0,
                "catalog": object(recipes), "preferences": object(preferences),
                "restrictions": Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, restriction(for: snapshot?.recipe.id == $0.id ? snapshot!.recipe : $0) ?? "") }),
                "ingredientReviews": (snapshot?.recipe.ingredients ?? []).map { ingredient -> [String: Any] in
                    let review = catalog?.review(foodID: ingredient.foodID, preferences: preferences)
                    return ["ingredientID": ingredient.id, "foodID": ingredient.foodID,
                            "blocking": review?.blocking ?? [], "notes": review?.notes ?? []]
                },
                "pendingRatioProposalID": voiceProposal?.id.uuidString ?? "none",
                "manualPreparationRequired": session.map { !$0.ready } ?? false]
    }

    private func performVoiceTool(id: String, name: String, arguments: String) -> String {
        if let cached = voiceToolResults[id] { return cached }
        var result: [String: Any]
        handlingVoiceTool = true
        defer { handlingVoiceTool = false }
        do {
            guard name == "cooking", arguments.utf8.count < 8000, let data = arguments.data(using: .utf8) else { throw CookingError.invalid("Unknown cooking tool.") }
            let request = try JSONDecoder().decode(VoiceRequest.self, from: data)
            try request.validate(session: session)
            let now = Date()
            func change(_ edit: (inout CookingSession) throws -> Void) throws {
                guard updateSession(edit) else { throw CookingError.invalid(error ?? "Could not save cooking progress.") }
            }
            var detail = "The cooking state below is current."
            switch request.operation {
            case .state: break
            case .select_recipe:
                guard session == nil, let recipe = recipes.first(where: { $0.id == request.target }), let value = request.value,
                      value.rounded() == value, value > 0, value <= Double(recipe.maximumServings) else { throw CookingError.invalid("Choose an available recipe and supported serving count.") }
                choose(recipe, servings: Int(value))
                guard session != nil else { throw CookingError.invalid(error ?? "Could not select this recipe.") }
                selectedRecipeID = nil
                detail = "Recipe selected. The manual ingredient checklist is now on screen. The user must finish it and tap Cook with Oui Chef before starting a task."
            case .confirm_ingredient, .confirm_tool, .confirm_labels:
                throw CookingError.invalid("Finish the manual checklist on screen before cooking.")
            case .start_node:
                if let recipe = session?.recipe, let restriction = restriction(for: recipe) { throw CookingError.invalid(restriction) }
                let target = try request.requiredTarget()
                let alreadyStarted = session?.started.contains(target) == true
                try change { try $0.begin(target, at: now) }
                if !alreadyStarted { stepStartConfirmations[target] = VoiceConfirmation(target: target, userTurn: voice.userTurn) }
                detail = "Task started. Explain its instructions and target. Ask readiness later; time alone is not completion."
            case .ask_readiness:
                let target = try request.requiredTarget()
                try change { current in
                    guard current.started.contains(target), !current.completed.contains(target), !current.guidancePaused else { throw CookingError.invalid("That task is not active.") }
                    current.pendingQuestionNodeID = target; current.record("readiness_asked", nodeID: target, at: now)
                }
                detail = session?.recipe.node(target)?.criterion ?? "Ask if the task is ready."
            case .complete_node:
                let target = try request.requiredTarget()
                let confirmation = stepStartConfirmations[target] ?? VoiceConfirmation(target: target, userTurn: 0)
                try confirmation.validate(target: target, userTurn: voice.userTurn)
                try change { try $0.finish(target, confirmed: true, at: now) }
                detail = "The user-reported task is complete. Explain the next eligible step; start its timer only when the user says they have begun."
            case .recheck: try change { try $0.recheck(request.requiredTarget(), at: now) }
            case .pause: try change { $0.pause(true, at: now) }; detail = "Guidance paused; timers and listening continue."
            case .resume:
                try change { current in
                    current.pause(false, at: now)
                    if let node = current.focus(at: now), current.started.contains(node.id) {
                        current.pendingQuestionNodeID = node.id
                        current.record("readiness_asked", nodeID: node.id, at: now)
                    }
                }
                detail = session?.resumeMessage(at: now) ?? "Welcome back."
            case .propose_ratio:
                guard let session, let value = request.value else { throw CookingError.invalid("Choose a recipe and numeric ratio first.") }
                let proposal = try session.proposeRatio(request.requiredTarget(), value: value)
                voiceProposal = proposal
                ratioConfirmation = VoiceConfirmation(target: proposal.id.uuidString, userTurn: voice.userTurn)
                let ingredient = session.recipe.ingredients.first { $0.id == proposal.ingredientID }!
                detail = "Proposal \(proposal.id.uuidString): change \(ingredient.name) from \(proposal.oldAmount) to \(proposal.newAmount) \(ingredient.unit), keeping the base ingredient and other quantities fixed. Read this change and wait for confirmation."
            case .confirm_ratio:
                let target = try request.requiredTarget()
                guard let proposal = voiceProposal, let confirmation = ratioConfirmation else { throw CookingError.invalid("Propose an adjustment first.") }
                try confirmation.validate(target: target, userTurn: voice.userTurn)
                guard proposal.id.uuidString == target else { throw CookingError.invalid("Unknown adjustment.") }
                try change { try $0.apply(proposal, at: now) }
                voiceProposal = nil; ratioConfirmation = nil
                detail = "Adjustment applied. Recheck the changed ingredient amount before cooking."
            case .set_guidance:
                guard request.value == 0 || request.value == 1 else { throw CookingError.invalid("Choose detailed or quieter guidance.") }
                var prefs = preferences; prefs.detailedGuidance = request.value == 1
                guard commit({ $0.preferences = prefs }) else { throw CookingError.invalid(error ?? "Could not save preference.") }
            case .mute: voice.stop(); detail = "Microphone off; timers continue."
            }
            result = ["ok": true, "message": detail, "state": voiceContext()]
        } catch { result = ["ok": false, "error": error.localizedDescription, "state": voiceContext()] }
        let encoded = (try? JSONSerialization.data(withJSONObject: result)).flatMap { String(data: $0, encoding: .utf8) } ?? "{\"ok\":false,\"error\":\"Could not encode state\"}"
        voiceToolResults[id] = encoded
        return encoded
    }
    func handle(_ text: String) {
        let command = VoiceCommand.parse(text)
        switch command {
        case .pause: pause()
        case .resume: if session != nil { resume() }
        case .mute: voice.stop(); chefMessage = "Microphone off. Your timers will keep running."
        case .recipe(let id):
            if session == nil { selectedRecipeID = id; say("\(recipes.first { $0.id == id }?.title ?? id). Open the recipe below and choose your servings to get started.") }
            else { say("You're already cooking \(session!.recipe.title). Finish or end this session before changing recipes.") }
        case .quieter, .detailed:
            var prefs = preferences
            prefs.detailedGuidance = command == .detailed
            savePreferences(prefs)
            say(command == .detailed ? "Of course. I'll talk you through it." : "I'll keep it quiet and check in when something needs your attention.")
        case .status, .repeatStep:
            if let node = session?.focus(at: Date()) {
                say(command == .repeatStep ? node.instruction : session!.resumeMessage(at: Date()))
            } else { say("Choose pasta, bread, or margarita and we'll get started.") }
        case .start:
            if let node = session?.eligibleNodes.first { begin(node) }
        case .done, .yes:
            if let id = session?.pendingQuestionNodeID, let node = session?.activeNodes.first(where: { $0.id == id }) { complete(node) }
            else if command == .done, let active = session?.activeNodes, active.count == 1, let node = active.first { complete(node) }
            else { say("Which task is done? Choose its Done button so we finish the right one.") }
        case .notYet:
            if let id = session?.pendingQuestionNodeID, let node = session?.activeNodes.first(where: { $0.id == id }) { notYet(node) }
            else if let active = session?.activeNodes, active.count == 1, let node = active.first { notYet(node) }
            else { say("Which task needs more time?") }
        case .unknown:
            say("I can follow cooking commands in this preview. Try repeat, start step, done, not yet, pause, or where are we.")
        }
    }

    private func syncNotifications() {
        notificationTask?.cancel()
        let timers = session?.timers ?? []
        let recipe = session?.recipe
        let sessionID = session?.id.uuidString ?? ""
        notificationTask = Task { [weak self] in
            let center = UNUserNotificationCenter.current()
            let requests = await center.pendingNotificationRequests()
            guard !Task.isCancelled else { return }
            center.removePendingNotificationRequests(withIdentifiers: requests.filter { $0.identifier.hasPrefix("oui-chef-") }.map(\.identifier))
            guard !timers.isEmpty else { return }
            do {
                let settings = await center.notificationSettings()
                let allowed = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
                guard !Task.isCancelled else { return }
                guard allowed else { return }
                self?.notificationNotice = nil
                for timer in timers where timer.deadline > Date() {
                    guard !Task.isCancelled else { return }
                    let content = UNMutableNotificationContent()
                    content.title = "Time to check \(recipe?.node(timer.nodeID)?.title.lowercased() ?? "your recipe")"
                    content.body = recipe?.node(timer.nodeID)?.criterion ?? "Check how your cooking is going."
                    content.sound = .default
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, timer.deadline.timeIntervalSinceNow), repeats: false)
                    let identifier = "oui-chef-\(sessionID)-\(timer.nodeID)-\(timer.deadline.timeIntervalSince1970)"
                    try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: trigger))
                    if Task.isCancelled {
                        center.removePendingNotificationRequests(withIdentifiers: [identifier])
                        return
                    }
                }
            } catch { self?.notificationNotice = "Could not schedule a timer alert: \(error.localizedDescription)" }
        }
    }
}
