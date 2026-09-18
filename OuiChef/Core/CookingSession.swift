import Foundation

struct CookingTimer: Codable, Identifiable, Equatable {
    var id: String { nodeID }
    var nodeID: String
    var startedAt: Date
    var deadline: Date
    var attempt: Int = 1
    func remaining(at date: Date) -> TimeInterval { deadline.timeIntervalSince(date) }
}

struct SessionEvent: Codable, Identifiable {
    var id: UUID = UUID()
    var date: Date
    var kind: String
    var nodeID: String?
}

struct RatioProposal: Identifiable {
    var id = UUID()
    var sessionID: UUID
    var revision: Int
    var optionID: String
    var oldAmount: Double
    var newAmount: Double
    var ingredientID: String
}

struct CookingSession: Codable, Identifiable {
    var id = UUID()
    var recipe: Recipe
    var servings: Int
    var revision = 0
    var confirmedIngredients = Set<String>()
    var confirmedTools = Set<String>()
    var ingredientLibrary: IngredientLibrary?
    var labelsChecked = false
    var preparationCompletedAt: Date?
    var started = Set<String>()
    var completed = Set<String>()
    var timers: [CookingTimer] = []
    var startedAt: [String: Date] = [:]
    var deliveredCues = Set<String>()
    var events: [SessionEvent] = []
    var guidancePaused = false
    var pendingQuestionNodeID: String?
    var createdAt = Date()
    var sourceRecipe: Recipe?
    var reportedAmounts: [String: Double]?
    var referenceAmounts: [String: Double]?
    var pendingRecovery: RecoveryPlan?
    var recoveryIngredientsConfirmed: Set<String>?
    var adjustments: [String]?
    var correctionUndo: CookingUndo?
    var completedTimers: [String: CookingTimer]?
    var completedAt: Date?
    var photoInvitationOffered: Bool?


    init(recipe: Recipe, servings: Int? = nil) throws {
        let count = servings ?? recipe.baseServings
        guard count > 0 && count <= recipe.maximumServings else { throw CookingError.invalid("Choose a supported serving size.") }
        self.sourceRecipe = recipe
        self.recipe = recipe
        self.servings = count
        for index in self.recipe.ingredients.indices where self.recipe.ingredients[index].scales {
            self.recipe.ingredients[index].amount *= Double(count) / Double(recipe.baseServings)
        }
    }

    var checksComplete: Bool {
        Set(recipe.ingredients.map(\.id)).isSubset(of: confirmedIngredients)
        && labelsChecked
    }
    // Existing sessions that already started cooking keep their progress on upgrade.
    var ready: Bool { checksComplete && (preparationCompletedAt != nil || !started.isEmpty) }
    var finished: Bool { pendingRecovery == nil && completed.count == recipe.nodes.count }
    var activeNodes: [CookingNode] { recipe.nodes.filter { started.contains($0.id) && !completed.contains($0.id) } }
    var eligibleNodes: [CookingNode] {
        recipe.nodes.filter { !started.contains($0.id) && Set($0.dependsOn).isSubset(of: completed) }
    }
    func focus(at date: Date) -> CookingNode? {
        let due = timers.filter { $0.deadline <= date }.sorted { $0.deadline < $1.deadline }.first
        if let node = due.flatMap({ recipe.node($0.nodeID) }) { return node }
        if let pending = pendingQuestionNodeID, let node = recipe.node(pending), !completed.contains(pending) { return node }
        return activeNodes.first ?? eligibleNodes.first
    }
    mutating func record(_ kind: String, nodeID: String? = nil, at date: Date) {
        revision += 1
        events.append(SessionEvent(date: date, kind: kind, nodeID: nodeID))
    }
    mutating func confirmIngredient(_ id: String, at date: Date) throws {
        guard recipe.ingredients.contains(where: { $0.id == id }) else { throw CookingError.invalid("Unknown ingredient.") }
        guard !confirmedIngredients.contains(id) else { return }
        confirmedIngredients.insert(id)
        record("ingredient_confirmed", at: date)
    }
    mutating func confirmAllIngredients(_ checked: Bool, at date: Date) {
        confirmedIngredients = checked ? Set(recipe.ingredients.map(\.id)) : []
        preparationCompletedAt = nil
        record(checked ? "ingredients_confirmed" : "ingredients_cleared", at: date)
    }
    mutating func setServings(_ count: Int, at date: Date) throws {
        guard started.isEmpty, count > 0, count <= recipe.maximumServings else {
            throw CookingError.invalid("Choose a supported serving size before cooking starts.")
        }
        guard count != servings else { return }
        for index in recipe.ingredients.indices where recipe.ingredients[index].scales {
            recipe.ingredients[index].amount *= Double(count) / Double(servings)
            confirmedIngredients.remove(recipe.ingredients[index].id)
        }
        servings = count
        preparationCompletedAt = nil
        record("servings_adjusted", at: date)
    }
    mutating func completePreparation(at date: Date) throws {
        guard checksComplete else { throw CookingError.invalid("Check your ingredients and product labels before cooking.") }
        preparationCompletedAt = date
        guidancePaused = false
        record("preparation_completed", at: date)
    }
    mutating func begin(_ id: String, at date: Date) throws {
        guard pendingRecovery == nil else { throw CookingError.invalid("Finish or cancel the recovery action first.") }
        guard ready else { throw CookingError.invalid("Let's check the ingredients and product labels first.") }
        guard !guidancePaused else { throw CookingError.invalid("Resume guidance before starting a task.") }
        guard !started.contains(id) else { return }
        guard let node = eligibleNodes.first(where: { $0.id == id }) else { throw CookingError.invalid("Finish this task's prerequisites first.") }
        let occupiedTools = Set(activeNodes.flatMap(\.tools))
        guard occupiedTools.isDisjoint(with: node.tools) else { throw CookingError.invalid("One of this task's tools is still in use. Finish that task first.") }
        let usedInputs = Set(recipe.nodes.filter { started.contains($0.id) }.flatMap(\.inputs))
        guard usedInputs.isDisjoint(with: node.inputs) else { throw CookingError.invalid("An input for this task has already been used.") }
        correctionUndo = nil
        started.insert(id)
        startedAt[id] = date
        if let duration = node.durationSeconds { timers.append(CookingTimer(nodeID: id, startedAt: date, deadline: date.addingTimeInterval(duration))) }
        record("node_started", nodeID: id, at: date)
    }
    mutating func finish(_ id: String, confirmed: Bool, at date: Date) throws {
        guard !completed.contains(id) else { return }
        guard !guidancePaused, started.contains(id), confirmed else { throw CookingError.invalid("Start the task and confirm its readiness before continuing.") }
        guard pendingRecovery == nil else { throw CookingError.invalid("Finish or cancel the recovery action first.") }
        correctionUndo = nil
        if let timer = timers.first(where: { $0.nodeID == id }) {
            if completedTimers == nil { completedTimers = [:] }
            completedTimers?[id] = timer
        }
        completed.insert(id)
        timers.removeAll { $0.nodeID == id }
        if pendingQuestionNodeID == id { pendingQuestionNodeID = nil }
        record("node_completed", nodeID: id, at: date)
        if finished { completedAt = date }
    }
    mutating func recheck(_ id: String, at date: Date) throws {
        guard !guidancePaused, started.contains(id), !completed.contains(id), let node = recipe.node(id) else {
            throw CookingError.invalid("Choose an active task to check again.")
        }
        let duration = node.recheckSeconds ?? node.checkAfterSeconds ?? 60
        let attempt = (timers.first { $0.nodeID == id }?.attempt ?? 0) + 1
        timers.removeAll { $0.nodeID == id }
        timers.append(CookingTimer(nodeID: id, startedAt: date, deadline: date.addingTimeInterval(duration), attempt: attempt))
        pendingQuestionNodeID = nil
        record("checkpoint_recheck", nodeID: id, at: date)
    }
    mutating func pause(_ paused: Bool, at date: Date) {
        guard guidancePaused != paused else { return }
        guidancePaused = paused
        record(paused ? "guidance_paused" : "guidance_resumed", at: date)
    }
    func resumeMessage(at date: Date) -> String {
        if finished { return "Welcome back! You've finished \(recipe.title.lowercased()). How did it turn out?" }
        if !ready { return "Welcome back! How's the prep going? Finish the ingredient checklist on screen, then we'll cook together." }
        guard let node = focus(at: date) else { return "Welcome back! How's the cooking going?" }
        if timers.contains(where: { $0.nodeID == node.id && $0.deadline <= date }) {
            return "Welcome back! The \(node.title.lowercased()) timer finished while we were away. \(node.criterion)"
        }
        if started.contains(node.id) { return "Hey, welcome back! How's \(node.title.lowercased()) going? \(node.criterion)" }
        return "Welcome back! Next is \(node.title.lowercased()). Have you started that yet?"
    }

    struct Cue: Identifiable {
        var id: String
        var nodeID: String
        var text: String
    }
    func dueCue(at date: Date, detailed: Bool) -> Cue? {
        guard ready, !guidancePaused else { return nil }
        let lastQuestion = events.last { $0.kind == "coaching_offered" || $0.kind == "readiness_asked" }
        if let lastQuestion, date.timeIntervalSince(lastQuestion.date) < 5 { return nil }
        func checkTime(_ node: CookingNode) -> Date {
            timers.first { $0.nodeID == node.id }?.deadline
                ?? (startedAt[node.id] ?? date).addingTimeInterval(node.checkAfterSeconds ?? 60)
        }
        for node in activeNodes.sorted(by: { checkTime($0) < checkTime($1) }) {
            let timer = timers.first { $0.nodeID == node.id }
            let due = checkTime(node)
            guard date >= due else { continue }
            let lastCheck = events.last { $0.nodeID == node.id && ($0.kind == "coaching_offered" || $0.kind == "readiness_asked") }?.date
            let interval = max(15, node.recheckSeconds ?? 60)
            if let lastCheck, lastCheck >= due, date.timeIntervalSince(lastCheck) < interval { continue }
            let key = "due:\(node.id):\(timer?.attempt ?? 0)"
            if !deliveredCues.contains(key) {
                return Cue(id: key, nodeID: node.id, text: "Let's check \(node.title.lowercased()). \(node.criterion)")
            }
            // Keep unanswered check-ins gentle, even for a five-second cocktail recheck.
            if date.timeIntervalSince(lastCheck ?? due) >= interval {
                return Cue(id: "followup:\(node.id):\(revision)", nodeID: node.id, text: "How's \(node.title.lowercased()) going? \(node.criterion) Say done when it's ready, or not yet if it needs more time.")
            }
        }
        guard detailed else { return nil }
        for node in activeNodes {
            guard let start = startedAt[node.id] else { continue }
            if let timer = timers.first(where: { $0.nodeID == node.id }), timer.attempt > 1 || date >= timer.deadline { continue }
            // ponytail: only the latest relevant cue is offered; no replay queue for three recipes.
            if let cue = node.coachingCues.last(where: { date.timeIntervalSince(start) >= $0.afterSeconds && date.timeIntervalSince(start) <= $0.afterSeconds + 45 }) {
                let key = "\(node.id):\(cue.id)"
                if !deliveredCues.contains(key) { return Cue(id: key, nodeID: node.id, text: cue.text) }
            }
        }
        return nil
    }
    mutating func deliver(_ cue: Cue, at date: Date) {
        guard !completed.contains(cue.nodeID), !deliveredCues.contains(cue.id) else { return }
        deliveredCues.insert(cue.id)
        pendingQuestionNodeID = cue.nodeID
        record("coaching_offered", nodeID: cue.nodeID, at: date)
    }
    func proposeRatio(_ optionID: String, value: Double) throws -> RatioProposal {
        guard let option = recipe.ratios.first(where: { $0.id == optionID }), value.isFinite,
              (option.minimum...option.maximum).contains(value),
              let ingredient = recipe.ingredients.first(where: { $0.id == option.ingredientID }),
              let base = recipe.ingredients.first(where: { $0.id == option.baseIngredientID }) else { throw CookingError.invalid("Choose a ratio within this recipe's supported range.") }
        let consumed = recipe.nodes.filter { started.contains($0.id) }.flatMap(\.inputs)
        guard !consumed.contains(option.ingredientID), !consumed.contains(option.baseIngredientID) else {
            throw CookingError.invalid("Those ingredients have already been used. Keep this batch as it is; adjust the ratio before mixing a new batch.")
        }
        return RatioProposal(sessionID: id, revision: revision, optionID: optionID, oldAmount: ingredient.amount, newAmount: base.amount * value, ingredientID: ingredient.id)
    }
    mutating func apply(_ proposal: RatioProposal, at date: Date) throws {
        guard proposal.sessionID == id, proposal.revision == revision, let index = recipe.ingredients.firstIndex(where: { $0.id == proposal.ingredientID }), let option = recipe.ratios.first(where: { $0.id == proposal.optionID }), let base = recipe.ingredients.first(where: { $0.id == option.baseIngredientID }) else { throw CookingError.invalid("The recipe changed. Please preview the adjustment again.") }
        let validated = try proposeRatio(proposal.optionID, value: proposal.newAmount / base.amount)
        guard validated.ingredientID == proposal.ingredientID else { throw CookingError.invalid("Invalid adjustment.") }
        saveCorrectionUndo()
        recipe.ingredients[index].amount = validated.newAmount
        confirmedIngredients.remove(proposal.ingredientID)
        preparationCompletedAt = nil
        record("ratio_adjusted", at: date)
    }

    mutating func selectAlternative(_ foodID: String, for ingredientID: String, at date: Date) throws {
        guard started.isEmpty, let index = recipe.ingredients.firstIndex(where: { $0.id == ingredientID }),
              let option = recipe.ingredients[index].alternatives?.first(where: { $0.foodID == foodID }) else {
            throw CookingError.invalid("Choose a supported alternative before cooking starts.")
        }
        guard recipe.ingredients[index].foodID != foodID else { return }
        recipe.ingredients[index].foodID = option.foodID
        recipe.ingredients[index].name = option.name
        for index in recipe.nodes.indices {
            if let instruction = option.instructions[recipe.nodes[index].id] { recipe.nodes[index].instruction = instruction }
        }
        confirmedIngredients.remove(ingredientID)
        labelsChecked = false
        preparationCompletedAt = nil
        record("ingredient_replaced", at: date)
    }
}
