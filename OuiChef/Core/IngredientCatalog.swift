import Foundation

struct FoodCategory: Codable, Identifiable {
    var id: String
    var name: String
    var parentID: String?
    var symbol: String
}

struct IngredientLibrary: Codable {
    var schemaVersion: Int
    var categories: [FoodCategory]
    var foods: [Food]

    func validate() throws {
        guard schemaVersion == 1, Set(categories.map(\.id)).count == categories.count,
              Set(foods.map(\.id)).count == foods.count else { throw CookingError.invalid("Invalid ingredient library IDs or version.") }
        let index = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        for category in categories {
            var parent: String? = category.id
            var visited = Set<String>()
            while let id = parent {
                guard visited.insert(id).inserted, let item = index[id] else { throw CookingError.invalid("Unknown or circular ingredient category.") }
                parent = item.parentID
            }
        }
        for food in foods {
            guard !food.name.isEmpty, let category = food.categoryID, index[category] != nil else {
                throw CookingError.invalid("Every catalog ingredient needs a name and category.")
            }
        }
        // Reuse recipe validation for constituent references and composition cycles.
        try RecipeCatalog(schemaVersion: 1, foods: foods, recipes: []).validate()
    }
}

struct IngredientReview {
    var blocking: [String] = []
    var notes: [String] = []
}

struct IngredientGroup: Identifiable {
    var id: String
    var name: String
    var symbol: String
    var ingredients: [Ingredient]
}

extension RecipeCatalog {
    func food(_ id: String) -> Food? { foods.first { $0.id == id } }

    func categoryPath(_ id: String?) -> [FoodCategory] {
        let index = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })
        var path: [FoodCategory] = []
        var next = id
        var visited = Set<String>()
        while let id = next, visited.insert(id).inserted, let category = index[id] {
            path.insert(category, at: 0)
            next = category.parentID
        }
        return path
    }

    func groups(for recipe: Recipe) -> [IngredientGroup] {
        var groups: [IngredientGroup] = []
        for ingredient in recipe.ingredients {
            let category = categoryPath(food(ingredient.foodID)?.categoryID).first
            let id = category?.id ?? "other"
            if let index = groups.firstIndex(where: { $0.id == id }) { groups[index].ingredients.append(ingredient) }
            else { groups.append(IngredientGroup(id: id, name: category?.name ?? "Other ingredients", symbol: category?.symbol ?? "basket", ingredients: [ingredient])) }
        }
        return groups
    }

    // ponytail: in-memory search suits the bundled catalog; index locally when measured size warrants it.
    func searchFoods(_ query: String, categoryID: String? = nil) -> [Food] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return foods.filter { food in
            let path = categoryPath(food.categoryID)
            let inCategory = categoryID == nil || path.contains { $0.id == categoryID }
            let names = [food.name] + (food.aliases ?? []) + path.map(\.name)
            return inCategory && (query.isEmpty || names.contains { $0.localizedStandardContains(query) })
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func review(foodID: String, preferences: ChefPreferences) -> IngredientReview {
        let index = Dictionary(uniqueKeysWithValues: foods.map { ($0.id, $0) })
        var result = IngredientReview()
        var visited = Set<String>()
        func inspect(_ id: String) {
            guard visited.insert(id).inserted, let food = index[id] else {
                if index[id] == nil { result.blocking.append("Unknown ingredient composition") }
                return
            }
            for allergen in preferences.allergies.intersection(food.allergens).sorted() {
                result.blocking.append("\(food.name) contains \(allergen).")
            }
            if !food.compositionKnown && !preferences.allergies.isEmpty {
                result.blocking.append("\(food.name): check the label for your allergies; its composition is not confirmed.")
            }
            for diet in preferences.dietary.sorted() {
                switch diet {
                case "Gluten-free", "Dairy-free":
                    let allergen = diet == "Gluten-free" ? "gluten" : "milk"
                    if food.allergens.contains(allergen) || !food.compositionKnown {
                        result.blocking.append("\(food.name) is not confirmed \(diet.lowercased()).")
                    }
                case "Vegan", "Vegetarian":
                    if !(food.dietaryTags ?? []).contains(diet) {
                        result.blocking.append("\(food.name) is not confirmed \(diet.lowercased()).")
                    }
                default: break
                }
            }
            if preferences.avoidAlcohol && (food.traits ?? []).contains("alcohol") {
                result.blocking.append("\(food.name) contains alcohol, which you avoid.")
            }
            if (preferences.dislikedFoodIDs ?? []).contains(id) { result.notes.append("You prefer to avoid \(food.name.lowercased()).") }
            for child in food.constituents { inspect(child) }
        }
        inspect(foodID)
        result.blocking = Array(Set(result.blocking)).sorted()
        result.notes = Array(Set(result.notes)).sorted()
        return result
    }

    func restriction(for recipe: Recipe, preferences: ChefPreferences) -> String? {
        if preferences.allergyAnswer == "I have allergies" && preferences.allergies.isEmpty {
            return "Select your allergies in preferences before cooking."
        }
        let issues = Set(recipe.ingredients.flatMap { review(foodID: $0.foodID, preferences: preferences).blocking }).sorted()
        return issues.isEmpty ? nil : issues.joined(separator: " ")
    }
}
