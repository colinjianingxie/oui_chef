import Foundation

enum ChefStyle: String, Codable, CaseIterable {
    case pasta, bread, tequila

    var name: String {
        switch self {
        case .pasta: "Pasta Chef"
        case .bread: "Bread Baker"
        case .tequila: "Tequila & Cocktails"
        }
    }
    var symbol: String {
        switch self {
        case .pasta: "fork.knife"
        case .bread: "oven"
        case .tequila: "wineglass"
        }
    }
}

struct Food: Codable, Identifiable {
    var id: String
    var name: String
    var allergens: [String]
    var constituents: [String]
    var compositionKnown: Bool
    var categoryID: String?
    var aliases: [String]?
    var dietaryTags: [String]?
    var traits: [String]?
    var spriteAsset: String?
}

struct IngredientAlternative: Codable, Identifiable {
    var id: String { foodID }
    var foodID: String
    var name: String
    var note: String
    var instructions: [String: String]
}

struct Ingredient: Codable, Identifiable {
    var id: String
    var foodID: String
    var name: String
    var amount: Double
    var unit: String
    var scales: Bool
    var alternatives: [IngredientAlternative]?

    var quantity: String { "\(amount.formatted(.number.precision(.fractionLength(0...1)))) \(unit)" }
}

struct CookingNode: Codable, Identifiable {
    enum Kind: String, Codable { case action, wait, checkpoint }
    var id: String
    var kind: Kind
    var title: String
    var instruction: String
    var dependsOn: [String]
    var inputs: [String]
    var outputs: [String]
    var tools: [String]
    var criterion: String
    var durationSeconds: Double?
    var recheckSeconds: Double?
    var coachingCues: [CoachingCue]
    var checkAfterSeconds: Double?
}

struct CoachingCue: Codable, Identifiable {
    var id: String
    var afterSeconds: Double
    var text: String
}

struct RatioOption: Codable, Identifiable {
    var id: String
    var title: String
    var ingredientID: String
    var baseIngredientID: String
    var minimum: Double
    var maximum: Double
    var step: Double
    var explanation: String
    var preference: String?

    func preferredValue(_ preferences: ChefPreferences, defaultValue: Double) -> Double? {
        let value: Double
        switch preference {
        case "salt": value = preferences.salt
        case "sweetness": value = preferences.sweetness
        case "spice": value = preferences.spice
        default: return nil
        }
        guard value.isFinite, (0...1).contains(value), abs(value - 0.5) > 0.01 else { return nil }
        let ratio = value < 0.5 ? minimum + (defaultValue - minimum) * value * 2
            : defaultValue + (maximum - defaultValue) * (value - 0.5) * 2
        return min(maximum, max(minimum, (ratio / step).rounded() * step))
    }
}

struct Recipe: Codable, Identifiable {
    var id: String
    var version: Int
    var title: String
    var subtitle: String
    var style: ChefStyle
    var tags: [String]
    var minutes: String
    var activeMinutes: Int
    var baseServings: Int
    var maximumServings: Int
    var yieldLabel: String
    var ingredients: [Ingredient]
    var tools: [String]
    var nodes: [CookingNode]
    var ratios: [RatioOption]
    var source: String
    var chefID: String?
    var chefName: String?
    var recipeSetID: String?
    var recoveryOptions: [RecoveryOption]?
    var totalMinutes: Int?
    var maximumMinutes: Int?

    func node(_ id: String) -> CookingNode? { nodes.first { $0.id == id } }
}

struct RecipeCatalog: Codable {
    var schemaVersion: Int
    var foods: [Food]
    var recipes: [Recipe]
    var categories: [FoodCategory] = []

    static func bundled() throws -> Self {
        #if SWIFT_PACKAGE
        let bundle = Bundle.module
        #else
        let bundle = Bundle.main
        #endif
        guard let url = bundle.url(forResource: "recipes", withExtension: "json") else {
            throw CookingError.invalid("The recipe library is missing.")
        }
        struct Recipes: Decodable { var schemaVersion: Int; var recipes: [Recipe] }
        let recipes = try JSONDecoder().decode(Recipes.self, from: Data(contentsOf: url))
        let library = try IngredientLibrary.bundled()
        try library.validate()
        let catalog = Self(schemaVersion: recipes.schemaVersion, foods: library.foods, recipes: recipes.recipes, categories: library.categories)
        try catalog.validate()
        return catalog
    }

    func validate() throws {
        func require(_ valid: Bool, _ message: String) throws {
            if !valid { throw CookingError.invalid(message) }
        }
        try require(schemaVersion == 1, "Unsupported recipe format.")
        try require(Set(foods.map(\.id)).count == foods.count, "Duplicate food IDs.")
        try require(Set(recipes.map(\.id)).count == recipes.count, "Duplicate recipe IDs.")
        let foodIDs = Set(foods.map(\.id))
        for food in foods { try require(Set(food.constituents).isSubset(of: foodIDs), "Unknown food constituent.") }
        func visitFood(_ id: String, path: Set<String>) throws {
            try require(!path.contains(id), "Circular food composition.")
            for child in foods.first(where: { $0.id == id })!.constituents {
                try visitFood(child, path: path.union([id]))
            }
        }
        for food in foods { try visitFood(food.id, path: []) }
        for recipe in recipes {
            if let minutes = recipe.totalMinutes {
                try require(minutes > 0 && (recipe.maximumMinutes ?? minutes) >= minutes, "Invalid time estimate.")
            }
            let ids = Set(recipe.nodes.map(\.id))
            let ingredients = Set(recipe.ingredients.map(\.id))
            try require(!recipe.nodes.isEmpty && ids.count == recipe.nodes.count, "Invalid node IDs.")
            try require(ingredients.count == recipe.ingredients.count, "Duplicate ingredient IDs.")
            try require(recipe.baseServings > 0 && recipe.maximumServings >= recipe.baseServings, "Invalid yield.")
            for ingredient in recipe.ingredients {
                try require(foodIDs.contains(ingredient.foodID) && ingredient.amount.isFinite && ingredient.amount > 0, "Invalid ingredient.")
                let alternatives = ingredient.alternatives ?? []
                try require(Set(alternatives.map(\.foodID)).count == alternatives.count, "Duplicate ingredient alternatives.")
                if !alternatives.isEmpty {
                    let overriddenNodes = Set(alternatives.flatMap { $0.instructions.keys })
                    try require(alternatives.contains { $0.foodID == ingredient.foodID }, "Alternatives need a way to restore the original ingredient.")
                    try require(alternatives.allSatisfy { Set($0.instructions.keys) == overriddenNodes }, "Alternatives must define every changed instruction.")
                }
                for option in alternatives {
                    try require(!option.name.isEmpty && !option.note.isEmpty, "Alternative instructions need a name and explanation.")
                    try require(foodIDs.contains(option.foodID) && Set(option.instructions.keys).isSubset(of: ids), "Invalid ingredient alternative.")
                }
            }
            let outputs = recipe.nodes.flatMap(\.outputs)
            try require(Set(outputs).count == outputs.count && Set(outputs).isDisjoint(with: ingredients), "Duplicate output states.")
            var completed = Set<String>()
            while completed.count < recipe.nodes.count {
                let eligible = recipe.nodes.filter { !completed.contains($0.id) && Set($0.dependsOn).isSubset(of: completed) }
                try require(!eligible.isEmpty, "Graph has a cycle or unknown dependency.")
                for node in eligible {
                    // Inputs must be produced by an ancestor, not an unrelated parallel task.
                    func ancestors(_ id: String) -> Set<String> {
                        guard let n = recipe.node(id) else { return [] }
                        return n.dependsOn.reduce(Set(n.dependsOn)) { $0.union(ancestors($1)) }
                    }
                    let allowed = ingredients.union(recipe.nodes.filter { ancestors(node.id).contains($0.id) }.flatMap(\.outputs))
                    try require(Set(node.inputs).isSubset(of: allowed), "Input state lacks a dependency.")
                    try require(!node.criterion.isEmpty && Set(node.tools).isSubset(of: Set(recipe.tools)), "Missing criterion or tool.")
                    if let duration = node.durationSeconds { try require(duration.isFinite && duration > 0, "Invalid timer.") }
                    if node.kind == .wait { try require(node.durationSeconds != nil, "Wait needs a timer.") }
                    if let duration = node.recheckSeconds { try require(duration.isFinite && duration > 0, "Invalid recheck.") }
                    if let duration = node.checkAfterSeconds { try require(duration.isFinite && duration > 0, "Invalid check-in time.") }
                    try require(Set(node.coachingCues.map(\.id)).count == node.coachingCues.count, "Duplicate cues.")
                    for cue in node.coachingCues { try require(cue.afterSeconds.isFinite && cue.afterSeconds >= 0, "Invalid coaching time.") }
                    completed.insert(node.id)
                }
            }
            try recipe.validateRecoveryOptions()
            for ratio in recipe.ratios {
                try require(ratio.preference == nil || ["salt", "sweetness", "spice"].contains(ratio.preference!), "Unknown taste preference.")
                try require(ingredients.contains(ratio.ingredientID) && ingredients.contains(ratio.baseIngredientID), "Unknown ratio ingredient.")
                let target = recipe.ingredients.first { $0.id == ratio.ingredientID }!
                let base = recipe.ingredients.first { $0.id == ratio.baseIngredientID }!
                try require(target.unit == base.unit && ratio.minimum.isFinite && ratio.maximum.isFinite && ratio.minimum > 0 && ratio.maximum >= ratio.minimum && ratio.step.isFinite && ratio.step > 0, "Invalid ratio bounds or units.")
            }
        }
    }

    func allergyConcerns(for recipe: Recipe, avoiding allergens: Set<String>) -> [String] {
        func inspect(_ id: String, visited: Set<String>) -> [String] {
            guard !visited.contains(id), let food = foods.first(where: { $0.id == id }) else { return ["Unknown ingredient composition"] }
            var issues = food.allergens.filter { allergens.contains($0) }.map { "\(food.name): contains \($0)" }
            if !food.compositionKnown && !allergens.isEmpty { issues.append("\(food.name): check the label for your allergies") }
            for child in food.constituents { issues += inspect(child, visited: visited.union([id])) }
            return issues
        }
        return Array(Set(recipe.ingredients.flatMap { inspect($0.foodID, visited: []) })).sorted()
    }
}

enum CookingError: LocalizedError, Equatable {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let message) = self { message } else { nil } }
}
