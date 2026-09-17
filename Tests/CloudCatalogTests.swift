import XCTest
@testable import OuiChefCore

final class CloudCatalogTests: XCTestCase {
    func testRemoteIngredientSnapshotRestoresOfflineAndRejectsBrokenReferences() throws {
        var catalog = try RecipeCatalog.bundled()
        var recipe = catalog.recipes.first { $0.id == "spaghetti" }!
        let original = recipe.ingredients[0].foodID
        var food = catalog.food(original)!
        food.id = "remote_only_ingredient"
        catalog.foods.append(food)
        recipe.ingredients[0].foodID = food.id
        recipe.ingredients[0].alternatives = nil
        var session = try CookingSession(recipe: recipe)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let storage = KitchenStorage(folder: folder)
        session.ingredientLibrary = IngredientLibrary(schemaVersion: 1, categories: catalog.categories, foods: catalog.foods)
        var archive = AppArchive(); archive.session = session
        try storage.save(archive, accountID: "cloud-cook")
        let restored = try storage.load(accountID: "cloud-cook", catalog: RecipeCatalog.bundled())
        XCTAssertEqual(restored.session?.recipe.ingredients[0].foodID, food.id)
        XCTAssertEqual(restored.session?.recipe.chefName, "Chef Margarita")
        archive.session?.ingredientLibrary?.foods.removeAll { $0.id == food.id }
        try storage.save(archive, accountID: "cloud-cook")
        XCTAssertThrowsError(try storage.load(accountID: "cloud-cook", catalog: RecipeCatalog.bundled()))
    }
    func testSubscriptionPriceAndReadOnlyVoiceSearch() throws {
        try RecipeSetPrice(kind: .subscription, amountMinor: 499, currency: "USD", interval: "month", productID: "chef.pack").validate()
        XCTAssertThrowsError(try RecipeSetPrice(kind: .free, amountMinor: 499, currency: "USD").validate())
        XCTAssertThrowsError(try RecipeSetPrice(kind: .subscription, amountMinor: 0, currency: "USD", interval: "month").validate())
        try VoiceRequest(operation: .find_recipes, sessionID: "none", revision: 0, target: "pasta").validate(session: nil)
    }
}
