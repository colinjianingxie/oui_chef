import XCTest
@testable import OuiChefCore

final class IngredientCatalogTests: XCTestCase {
    func testCatalogCategoriesSearchAndCompositionValidation() throws {
        let catalog = try RecipeCatalog.bundled()
        XCTAssertGreaterThan(catalog.foods.count, 50)
        XCTAssertEqual(catalog.categoryPath(catalog.food("garlic")?.categoryID).map(\.id), ["produce", "vegetables", "alliums"])
        XCTAssertTrue(catalog.searchFoods("alliums", categoryID: "produce").contains { $0.id == "garlic" })
        XCTAssertTrue(catalog.searchFoods("scallion").contains { $0.id == "scallion" })
        XCTAssertFalse(catalog.searchFoods("garlic", categoryID: "dairy").contains { $0.id == "garlic" })
        var library = IngredientLibrary(schemaVersion: 1, categories: catalog.categories, foods: catalog.foods)
        library.categories[0].parentID = library.categories[0].id
        XCTAssertThrowsError(try library.validate())
        library.categories = catalog.categories
        library.foods[0].categoryID = "missing"
        XCTAssertThrowsError(try library.validate())
        library.foods = catalog.foods
        library.foods[0].constituents = [library.foods[0].id]
        XCTAssertThrowsError(try library.validate())
        var invalidRecipe = catalog
        invalidRecipe.recipes[0].ingredients[0].alternatives?[1].instructions = [:]
        XCTAssertThrowsError(try invalidRecipe.validate())
        invalidRecipe = catalog
        invalidRecipe.recipes[0].ingredients[0].alternatives?[1].foodID = "missing"
        XCTAssertThrowsError(try invalidRecipe.validate())
    }

    func testPreferencesFollowIngredientsAndCompoundsRatherThanRecipeTags() throws {
        var catalog = try RecipeCatalog.bundled()
        var preferences = ChefPreferences()
        preferences.dietary = ["Vegan"]
        var recipe = catalog.recipes[0]
        recipe.tags = []
        XCTAssertNil(catalog.restriction(for: recipe, preferences: preferences))
        recipe.ingredients[0].foodID = "milk"
        recipe.tags = ["Vegan"]
        XCTAssertNotNil(catalog.restriction(for: recipe, preferences: preferences))
        preferences.dietary = []
        preferences.allergies = ["wheat"]
        catalog.foods.append(Food(id: "compound", name: "Mix", allergens: [], constituents: ["flour"], compositionKnown: true))
        XCTAssertFalse(catalog.review(foodID: "compound", preferences: preferences).blocking.isEmpty)
        XCTAssertFalse(catalog.review(foodID: "liqueur", preferences: preferences).blocking.isEmpty)
        XCTAssertFalse(catalog.review(foodID: "missing", preferences: preferences).blocking.isEmpty)
        preferences.allergies = []
        preferences.dislikedFoodIDs = ["flour"]
        XCTAssertTrue(catalog.review(foodID: "compound", preferences: preferences).blocking.isEmpty)
        XCTAssertFalse(catalog.review(foodID: "compound", preferences: preferences).notes.isEmpty)
        preferences.avoidAlcohol = true
        catalog.foods[catalog.foods.count - 1].constituents = ["tequila"]
        XCTAssertFalse(catalog.review(foodID: "compound", preferences: preferences).blocking.isEmpty)
    }

    func testAlternativeUpdatesInstructionsRechecksAndRestoresWithoutChangingQuantity() throws {
        let catalog = try RecipeCatalog.bundled()
        var session = try CookingSession(recipe: catalog.recipes[0])
        let now = Date()
        let original = session.recipe.node("cook_pasta")?.instruction
        session.confirmAllIngredients(true, at: now)
        session.labelsChecked = true
        try session.completePreparation(at: now)
        var preferences = ChefPreferences()
        preferences.allergies = ["wheat"]
        XCTAssertNotNil(catalog.restriction(for: session.recipe, preferences: preferences))
        try session.selectAlternative("rice_spaghetti", for: "pasta", at: now)
        XCTAssertNil(catalog.restriction(for: session.recipe, preferences: preferences))
        XCTAssertEqual(session.recipe.ingredients[0].amount, 200)
        XCTAssertFalse(session.confirmedIngredients.contains("pasta"))
        XCTAssertFalse(session.labelsChecked)
        XCTAssertFalse(session.ready)
        XCTAssertTrue(session.recipe.node("cook_pasta")!.instruction.contains("package"))
        XCTAssertNotEqual(session.recipe.node("cook_pasta")?.instruction, original)
        session = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(session.recipe.ingredients[0].foodID, "rice_spaghetti")
        try session.selectAlternative("pasta", for: "pasta", at: now)
        XCTAssertEqual(session.recipe.node("cook_pasta")?.instruction, original)
        XCTAssertThrowsError(try session.selectAlternative("milk", for: "pasta", at: now))
        session.confirmAllIngredients(true, at: now)
        session.labelsChecked = true
        try session.completePreparation(at: now)
        XCTAssertTrue(session.confirmedTools.isEmpty)
        try session.begin("prep", at: now)
        XCTAssertThrowsError(try session.selectAlternative("rice_spaghetti", for: "pasta", at: now))
    }

    func testTasteSuggestionsAreBoundedAndOldPreferencesStillDecode() throws {
        let catalog = try RecipeCatalog.bundled()
        let option = try XCTUnwrap(catalog.recipes.last?.ratios.first)
        var preferences = ChefPreferences()
        XCTAssertNil(option.preferredValue(preferences, defaultValue: 0.4))
        preferences.sweetness = 0
        XCTAssertEqual(option.preferredValue(preferences, defaultValue: 0.4), 0.2)
        preferences.sweetness = 1
        XCTAssertEqual(try XCTUnwrap(option.preferredValue(preferences, defaultValue: 0.4)), 0.6, accuracy: 0.0001)
        preferences.sweetness = .nan
        XCTAssertNil(option.preferredValue(preferences, defaultValue: 0.4))
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(ChefPreferences())) as? [String: Any])
        legacy.removeValue(forKey: "dislikedFoodIDs")
        let restored = try JSONDecoder().decode(ChefPreferences.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(restored.dislikedFoodIDs)
    }

    func testPreparationAppliesSupportedPreferencesAndKeepsConflictsVisible() throws {
        let catalog = try RecipeCatalog.bundled()
        let now = Date()
        var preferences = ChefPreferences()
        preferences.allergies = ["wheat"]
        preferences.salt = 0
        var pasta = try CookingSession(recipe: catalog.recipes[0], servings: 4)
        try pasta.applySavedPreferences(preferences, catalog: catalog, at: now)
        XCTAssertEqual(pasta.recipe.ingredients[0].foodID, "rice_spaghetti")
        XCTAssertEqual(pasta.recipe.ingredients.first { $0.id == "sauce_salt" }?.amount, 2)
        XCTAssertEqual(pasta.sourceRecipe?.ingredients[0].foodID, "pasta")
        XCTAssertNil(catalog.restriction(for: pasta.recipe, preferences: preferences))
        XCTAssertFalse(pasta.checksComplete)
        XCTAssertFalse(pasta.labelsChecked)
        let revision = pasta.revision
        try pasta.applySavedPreferences(preferences, catalog: catalog, at: now)
        XCTAssertEqual(pasta.revision, revision, "Reapplying settings must not compound amounts")

        var bread = try CookingSession(recipe: catalog.recipes[1])
        try bread.applySavedPreferences(preferences, catalog: catalog, at: now)
        XCTAssertNotNil(catalog.restriction(for: bread.recipe, preferences: preferences), "No invented flour substitution")

        var drink = try CookingSession(recipe: catalog.recipes[2], servings: 2)
        preferences.allergies = []; preferences.sweetness = 0
        try drink.applySavedPreferences(preferences, catalog: catalog, at: now)
        XCTAssertEqual(drink.recipe.ingredients.first { $0.id == "liqueur" }?.amount, 20)
        drink.confirmAllIngredients(true, at: now); drink.labelsChecked = true
        try drink.completePreparation(at: now); try drink.begin("measure", at: now)
        preferences.sweetness = 1
        try drink.applySavedPreferences(preferences, catalog: catalog, at: now)
        XCTAssertEqual(drink.recipe.ingredients.first { $0.id == "liqueur" }?.amount, 20, "Never change an in-progress batch from settings")

        let salt = pasta.recipe.ingredients.first { $0.foodID == "salt" }!
        XCTAssertTrue(catalog.isPantryBasic(salt, preferences: preferences))
        preferences.dislikedFoodIDs = ["salt"]
        XCTAssertFalse(catalog.isPantryBasic(salt, preferences: preferences), "A flagged basic stays in the main list")
        XCTAssertFalse(catalog.isPantryBasic(pasta.recipe.ingredients[0], preferences: preferences))
        preferences.equipment = ["Pots & pans", "Everyday utensils"]
        XCTAssertEqual(preferences.toolsToMention(for: pasta.recipe), [])
        preferences.equipment.formUnion(["Cocktail shaker", "Measuring jigger"])
        XCTAssertEqual(preferences.toolsToMention(for: drink.recipe), ["Cocktail shaker", "Measuring jigger", "Strainer"])
    }
}
