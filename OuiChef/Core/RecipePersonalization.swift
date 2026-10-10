import Foundation

struct CookingPreparation: Codable, Equatable {
    var ingredientIDs: [String] = []
    var equipment: [String] = []
    var reviewedVersion: Int?
    var readyAt: Double?
}

struct RecipePortions: Codable, Equatable {
    var servings: Int
    var ingredients: [RecipeIngredient]
    var steps: [RecipeStep]
}

struct OriginalRecipeSource: Codable, Equatable {
    struct Ingredient: Codable, Equatable { var id: String; var name: String; var quantity: String; var sourceDetail: String; var amount: Double?; var unit: String? }
    struct Action: Codable, Equatable { var id: String; var instruction: String; var sourceDetail: String; var durationSeconds: Double? }
    var ingredients: [Ingredient]
    var actions: [Action]
    var servings: Int?
}

extension CompanionRecipe {
    func prepared(for profile: CookProfile) throws -> Self {
        var result = self
        let previous = personalizationProfile
        if previous?.servings != profile.servings, servings != nil, servings != profile.servings {
            result = try result.scaled(to: profile.servings)
        }
        if let previous, previous.diet != profile.diet || previous.allergyIDs != profile.allergyIDs || previous.customAllergies != profile.customAllergies || previous.restrictionIDs != profile.restrictionIDs || previous.customRestrictions != profile.customRestrictions || previous.dislikedFoodIDs != profile.dislikedFoodIDs || previous.salt != profile.salt || previous.spice != profile.spice || previous.equipmentIDs != profile.equipmentIDs || previous.units != profile.units {
            let note = "Your kitchen preferences have changed since this recipe was prepared. Its ingredients and directions are unchanged; review them with your chef or import again for new adaptations."
            if !result.warnings.contains(note) { result.warnings.append(note) }
            result.version += 1; result.reviewed = false
        }
        result.personalizationProfile = profile
        return result
    }
    func restoringSource() throws -> Self {
        guard let source = originalSource, Set(source.ingredients.map(\.id)) == Set(ingredients.map(\.id)), source.actions.map(\.id) == steps.map(\.id) else {
            throw CookingError.invalid("The original recipe is unavailable for this import. Open the source to review it.")
        }
        var result = self
        result.ingredients = source.ingredients.map { item in
            var ingredient = ingredients.first { $0.id == item.id }!
            ingredient.name = item.name; ingredient.quantity = item.quantity; ingredient.amount = item.amount; ingredient.unit = item.unit; ingredient.substitution = nil; ingredient.origin = "source"
            return ingredient
        }
        for index in result.steps.indices {
            result.steps[index].instruction = source.actions[index].instruction
            result.steps[index].durationSeconds = source.actions[index].durationSeconds
            result.steps[index].timingEstimated = false
            // The source record has no per-step allocations; do not retain personalized ones.
            result.steps[index].ingredients = []
        }
        result.preparation = []; result.equipment = []; result.notes = []
        for index in result.steps.indices {
            result.steps[index].visualCue = nil; result.steps[index].temperature = nil; result.steps[index].reminder = nil
        }
        result.warnings.append("The original ingredients and instructions are restored. Check the source for preparation, equipment, temperatures, and doneness cues before cooking.")
        result.servings = source.servings; result.portionBaseline = nil; result.adaptations = []; result.reviewed = false; result.version += 1
        try result.validate(); return result
    }
    var adjustmentSummary: String {
        ([servings.map { "\($0) servings" }] + adaptations.prefix(1).map(Optional.some)).compactMap { $0 }.joined(separator: " · ")
    }
    var reviewNotes: [String] {
        var notes = warnings
        if let profile = personalizationProfile {
            let allergies = PreferenceSection.allergies.names(profile.allergyIDs) + (profile.customAllergies.isEmpty ? [] : [profile.customAllergies])
            if !allergies.isEmpty { notes.append("Your allergies: " + allergies.joined(separator: ", ") + ". Review every ingredient and its packaging. Recipe adaptations do not confirm allergy safety.") }
        }
        if let base = portionBaseline, base.servings != servings {
            notes.append("Quantities with known amounts are adjusted to \(servings ?? base.servings) servings. Original directions are for \(base.servings) servings; use the adjusted ingredient amounts. Times and temperatures stay the same.")
            let unknown = ingredients.filter { $0.amount == nil }.map(\.name)
            if !unknown.isEmpty { notes.append("Check the source amounts for: " + unknown.joined(separator: ", ") + ". These could not be scaled automatically.") }
            let uncertainSteps = base.steps.filter { step in step.ingredients.contains { item in item.amount == nil && !base.ingredients.contains { $0.id == item.ingredientID && $0.amount != nil && $0.quantity == item.quantity } } }.map(\.title)
            if !uncertainSteps.isEmpty { notes.append("Some step amounts remain as written in the source: " + uncertainSteps.joined(separator: ", ") + ". Review these allocations for your portions.") }
        }
        return notes
    }
    func scaled(to count: Int) throws -> Self {
        guard (1...20).contains(count), let yield = servings, yield > 0 else { throw CookingError.invalid("A known recipe yield is needed to adjust servings.") }
        let base = portionBaseline ?? RecipePortions(servings: yield, ingredients: ingredients, steps: steps)
        guard base.servings > 0 else { throw CookingError.invalid("This recipe's original yield needs review.") }
        var result = self
        result.servings = count
        result.ingredients = base.ingredients
        result.steps = base.steps
        result.portionBaseline = count == base.servings ? nil : base
        result.reviewed = false
        result.version += 1
        let factor = Double(count) / Double(base.servings)
        for index in result.ingredients.indices {
            guard let amount = base.ingredients[index].amount else { continue }
            result.ingredients[index].amount = amount * factor
            result.ingredients[index].quantity = Self.quantity(amount * factor, unit: base.ingredients[index].unit)
        }
        for step in result.steps.indices {
            for index in result.steps[step].ingredients.indices {
                let item = base.steps[step].ingredients[index]
                if let amount = item.amount {
                    result.steps[step].ingredients[index].amount = amount * factor
                    result.steps[step].ingredients[index].quantity = Self.quantity(amount * factor, unit: item.unit)
                } else if let original = base.ingredients.first(where: { $0.id == item.ingredientID }), item.quantity == original.quantity,
                          let adjusted = result.ingredients.first(where: { $0.id == item.ingredientID }), adjusted.amount != nil {
                    result.steps[step].ingredients[index].quantity = adjusted.quantity
                }
            }
        }
        // Preserve exact source wording when resetting; do not round-trip free-text quantities.
        if count == base.servings { result.ingredients = base.ingredients; result.steps = base.steps }
        try result.validate()
        return result
    }
    static func quantity(_ amount: Double, unit: String?) -> String {
        [amount.formatted(.number.precision(.fractionLength(0...2))), unit ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
    }
}

enum CookingVoiceState: Equatable {
    case inactive, connecting, listening, processing, speaking, muted, error(String)
    var label: String {
        switch self {
        case .inactive: "Tap to talk"
        case .connecting: "Connecting…"
        case .listening: "Listening…"
        case .processing: "Thinking…"
        case .speaking: "Your chef is speaking"
        case .muted: "Microphone off"
        case .error: "Voice unavailable"
        }
    }
}
