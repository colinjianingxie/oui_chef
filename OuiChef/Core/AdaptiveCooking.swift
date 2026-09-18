import Foundation

struct RecoveryOption: Codable, Identifiable {
    enum Kind: String, Codable { case addition, balance }
    var id: String
    var title: String
    var kind: Kind
    var ingredientIDs: [String]
    var minimum: Double
    var maximum: Double
    var maximumTotal: Double
    var nodeIDs: [String]
    var instruction: String
    var criterion: String
}

struct RecoveryPlan: Codable, Identifiable {
    var id = UUID()
    var sessionID: UUID
    var revision: Int
    var optionID: String
    var nodeID: String
    var value: Double
    var additions: [String: Double]
    var instruction: String
    var criterion: String
}

// One reversible record correction; physical additions are never undone this way.
struct CookingUndo: Codable {
    var revision: Int
    var recipe: Recipe
    var reportedAmounts: [String: Double]?
    var referenceAmounts: [String: Double]?
    var confirmedIngredients: Set<String>
    var preparationCompletedAt: Date?
}

extension Recipe {
    func validateRecoveryOptions() throws {
        let options = recoveryOptions ?? []
        guard options.count <= 12, Set(options.map(\.id)).count == options.count else { throw CookingError.invalid("Invalid recovery options.") }
        for option in options {
            guard !option.id.isEmpty, !option.title.isEmpty, !option.instruction.isEmpty, !option.criterion.isEmpty,
                  !option.ingredientIDs.isEmpty, Set(option.ingredientIDs).count == option.ingredientIDs.count,
                  option.ingredientIDs.allSatisfy({ id in ingredients.contains { $0.id == id } }),
                  !option.nodeIDs.isEmpty, option.nodeIDs.allSatisfy({ node($0) != nil }),
                  option.minimum.isFinite, option.maximum.isFinite, option.maximumTotal.isFinite,
                  option.minimum > 0, option.maximum >= option.minimum, option.maximumTotal >= option.maximum,
                  option.kind != .addition || option.ingredientIDs.count == 1 else {
                throw CookingError.invalid("Invalid recovery option references or bounds.")
            }
        }
    }
}

extension CookingSession {
    var adjustmentSummary: [String] { adjustments ?? [] }

    mutating func saveCorrectionUndo() {
        correctionUndo = CookingUndo(revision: revision + 1, recipe: recipe, reportedAmounts: reportedAmounts,
            referenceAmounts: referenceAmounts, confirmedIngredients: confirmedIngredients, preparationCompletedAt: preparationCompletedAt)
    }

    mutating func reportAmount(_ ingredientID: String, amount: Double, unit: String, at date: Date) throws {
        guard pendingRecovery == nil, amount.isFinite, (0...1_000_000).contains(amount),
              let ingredient = recipe.ingredients.first(where: { $0.id == ingredientID }), ingredient.unit == unit else {
            throw CookingError.invalid("Report the actual total in the ingredient's displayed unit. Resolve the pending recovery first.")
        }
        saveCorrectionUndo()
        if referenceAmounts == nil { referenceAmounts = Dictionary(uniqueKeysWithValues: recipe.ingredients.map { ($0.id, $0.amount) }) }
        if reportedAmounts == nil { reportedAmounts = [:] }
        reportedAmounts?[ingredientID] = amount
        addAdjustment("Reported \(ingredient.name): \(amount.formatted()) \(unit).")
        record("amount_reported", at: date)
    }

    mutating func undoCorrection(at date: Date) throws {
        guard pendingRecovery == nil, let undo = correctionUndo, undo.revision == revision else {
            throw CookingError.invalid("That change can no longer be undone. Tell me what actually happened so we can correct the record.")
        }
        recipe = undo.recipe; reportedAmounts = undo.reportedAmounts; referenceAmounts = undo.referenceAmounts
        confirmedIngredients = undo.confirmedIngredients; preparationCompletedAt = undo.preparationCompletedAt
        correctionUndo = nil
        addAdjustment("Corrected the previous quantity report or unapplied ratio edit.")
        record("correction_undone", at: date)
    }

    func hasStartedDescendant(of id: String) -> Bool {
        var descendants = Set([id])
        var changed = true
        while changed {
            changed = false
            for node in recipe.nodes where !descendants.contains(node.id) && !descendants.isDisjoint(with: node.dependsOn) {
                descendants.insert(node.id); changed = true
            }
        }
        descendants.remove(id)
        return !started.isDisjoint(with: descendants)
    }

    mutating func reopen(_ id: String, at date: Date) throws {
        guard pendingRecovery == nil, completed.contains(id), !hasStartedDescendant(of: id) else {
            throw CookingError.invalid("Later work has already started, or this step is not completed. Clarify that work before correcting progress.")
        }
        completed.remove(id); completedAt = nil; pendingQuestionNodeID = id; correctionUndo = nil
        if let timer = completedTimers?[id], !timers.contains(where: { $0.nodeID == id }) { timers.append(timer) }
        record("completion_corrected", nodeID: id, at: date)
    }

    func proposeRecovery(_ optionID: String, value: Double, nodeID: String) throws -> RecoveryPlan {
        guard pendingRecovery == nil, ready, !guidancePaused,
              let option = recipe.recoveryOptions?.first(where: { $0.id == optionID }),
              option.nodeIDs.contains(nodeID), started.contains(nodeID), !hasStartedDescendant(of: nodeID),
              value.isFinite else { throw CookingError.invalid("This recovery isn't supported at the current stage. Describe what has happened so far.") }
        let factor = Double(servings) / Double(recipe.baseServings)
        var additions: [String: Double] = [:]
        if option.kind == .addition {
            guard (option.minimum * factor...option.maximum * factor).contains(value),
                  let ingredient = recipe.ingredients.first(where: { $0.id == option.ingredientIDs[0] }) else {
                throw CookingError.invalid("Choose an addition within the displayed recovery range.")
            }
            let base = referenceAmounts?[ingredient.id] ?? ingredient.amount
            let current = reportedAmounts?[ingredient.id] ?? ingredient.amount
            guard current + value <= base + option.maximumTotal * factor else { throw CookingError.invalid("This batch has reached its supported recovery limit.") }
            for ratio in recipe.ratios where ratio.ingredientID == ingredient.id {
                if let baseIngredient = recipe.ingredients.first(where: { $0.id == ratio.baseIngredientID }) {
                    let baseAmount = reportedAmounts?[baseIngredient.id] ?? baseIngredient.amount
                    guard baseAmount > 0, (current + value) / baseAmount <= ratio.maximum else {
                        throw CookingError.invalid("This addition would exceed the recipe's structural ratio limit.")
                    }
                }
            }
            additions[ingredient.id] = value
        } else {
            let items = recipe.ingredients.filter { option.ingredientIDs.contains($0.id) }
            let scale = items.reduce(1.0) { largest, item in
                max(largest, (reportedAmounts?[item.id] ?? item.amount) / (referenceAmounts?[item.id] ?? item.amount))
            }
            guard scale.isFinite, scale > 1, scale <= option.maximum,
                  Double(servings) * scale <= Double(recipe.maximumServings) else {
                throw CookingError.invalid("Restoring this ratio would exceed the supported batch size, or no excess amount has been reported.")
            }
            for item in items {
                let amount = (referenceAmounts?[item.id] ?? item.amount) * scale - (reportedAmounts?[item.id] ?? item.amount)
                if amount > 0.0001 { additions[item.id] = amount }
            }
        }
        guard !additions.isEmpty else { throw CookingError.invalid("No addition is needed.") }
        return RecoveryPlan(sessionID: id, revision: revision, optionID: optionID, nodeID: nodeID,
            value: value, additions: additions, instruction: option.instruction, criterion: option.criterion)
    }

    mutating func acceptRecovery(_ plan: RecoveryPlan, at date: Date) throws {
        guard plan.sessionID == id, plan.revision == revision else { throw CookingError.invalid("Cooking state changed. Preview the recovery again.") }
        let checked = try proposeRecovery(plan.optionID, value: plan.value, nodeID: plan.nodeID)
        guard checked.additions == plan.additions else { throw CookingError.invalid("Recovery amounts changed.") }
        pendingRecovery = plan; recoveryIngredientsConfirmed = []; correctionUndo = nil
        completedAt = nil
        record("recovery_planned", nodeID: plan.nodeID, at: date)
    }

    mutating func confirmRecoveryIngredient(_ id: String, checked: Bool, at date: Date) throws {
        guard pendingRecovery?.additions[id] != nil else { throw CookingError.invalid("Unknown recovery ingredient.") }
        if recoveryIngredientsConfirmed == nil { recoveryIngredientsConfirmed = [] }
        if checked { recoveryIngredientsConfirmed?.insert(id) } else { recoveryIngredientsConfirmed?.remove(id) }
        record("recovery_ingredient_checked", at: date)
    }

    mutating func completeRecovery(at date: Date) throws {
        guard let plan = pendingRecovery, ready, !guidancePaused,
              Set(plan.additions.keys).isSubset(of: recoveryIngredientsConfirmed ?? []) else {
            throw CookingError.invalid("Check the extra ingredients on screen, then report when you've actually added them.")
        }
        if referenceAmounts == nil { referenceAmounts = Dictionary(uniqueKeysWithValues: recipe.ingredients.map { ($0.id, $0.amount) }) }
        if reportedAmounts == nil { reportedAmounts = [:] }
        for index in recipe.ingredients.indices {
            let item = recipe.ingredients[index]
            if let extra = plan.additions[item.id] {
                let total = (reportedAmounts?[item.id] ?? item.amount) + extra
                reportedAmounts?[item.id] = total; recipe.ingredients[index].amount = total
                addAdjustment("Added \(extra.formatted()) \(item.unit) \(item.name); total \(total.formatted()) \(item.unit).")
            }
        }
        pendingRecovery = nil; recoveryIngredientsConfirmed = nil; correctionUndo = nil
        if completed.contains(plan.nodeID) { try reopen(plan.nodeID, at: date) }
        pendingQuestionNodeID = plan.nodeID
        record("recovery_performed", nodeID: plan.nodeID, at: date)
    }

    mutating func cancelRecovery(at date: Date) {
        guard pendingRecovery != nil else { return }
        pendingRecovery = nil; recoveryIngredientsConfirmed = nil
        record("recovery_cancelled_before_adding", at: date)
        if finished { completedAt = date }
    }

    private mutating func addAdjustment(_ text: String) {
        adjustments = Array(((adjustments ?? []) + [text]).suffix(40))
    }
}
