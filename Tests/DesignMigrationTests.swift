import XCTest
@testable import OuiChefCore

final class DesignMigrationTests: XCTestCase {
    private func recipe() -> CompanionRecipe {
        CompanionRecipe(id: "pasta", title: "Pasta", sourceURL: "https://example.com/pasta", sourceName: "Website", servings: 2,
            ingredients: [RecipeIngredient(id: "pasta", name: "Pasta", quantity: "200 g", amount: 200, unit: "g"), RecipeIngredient(id: "salt", name: "Salt", quantity: "To taste", pantry: true)],
            steps: [RecipeStep(id: "boil", title: "Boil pasta", instruction: "Boil the pasta until tender, about 10 minutes.", stage: "Cook", ingredients: [StepIngredient(ingredientID: "pasta", quantity: "200 g", amount: 200, unit: "g")], durationSeconds: 600)])
    }
    func testPreparationPersistsChecksAndEnforcesReviewAtTransition() throws {
        var source = recipe(); source.warnings = ["Check the ingredient label for your allergy."]
        var cook = CookAttempt(recipe: source); cook.preparation = CookingPreparation()
        try cook.apply(CookAction(operation: "check_ingredient", sessionID: cook.id, revision: 0, target: "pasta"), at: 0)
        cook = try CompanionJSON.decode(CookAttempt.self, CompanionJSON.encode(cook))
        XCTAssertTrue(cook.isPreparing)
        XCTAssertEqual(cook.preparation?.ingredientIDs, ["pasta"])
        XCTAssertThrowsError(try cook.apply(CookAction(operation: "begin_cooking", sessionID: cook.id, revision: cook.revision), at: 1))
        XCTAssertThrowsError(try cook.apply(CookAction(operation: "complete_step", sessionID: cook.id, revision: cook.revision), at: 1))
        try cook.apply(CookAction(operation: "review_recipe", sessionID: cook.id, revision: cook.revision, text: "accepted"), at: 2)
        try cook.apply(CookAction(operation: "begin_cooking", sessionID: cook.id, revision: cook.revision), at: 5000)
        XCTAssertFalse(cook.isPreparing)
        XCTAssertEqual(cook.cookingStartedAt, 5000)
        XCTAssertTrue(cook.completed.isEmpty)
    }
    func testOldSessionWithoutNewFieldsKeepsCookingAndTimerDeadline() throws {
        var cook = CookAttempt(recipe: recipe())
        try cook.apply(CookAction(operation: "start_timer", sessionID: cook.id, revision: 0, seconds: 60), at: 0)
        let decoded = try CompanionJSON.decode(CookAttempt.self, CompanionJSON.encode(cook))
        XCTAssertNil(decoded.preparation); XCTAssertFalse(decoded.isPreparing)
        XCTAssertEqual(decoded.timers.first?.deadline, 60000)
        XCTAssertNil(decoded.profileSnapshot)
    }
    func testServingChangesUseBaselineAndResetWithoutRoundingOrChangingTiming() throws {
        let original = recipe()
        let doubled = try original.scaled(to: 4)
        XCTAssertEqual(doubled.ingredients[0].quantity, "400 g")
        XCTAssertEqual(doubled.steps[0].ingredients[0].quantity, "400 g")
        XCTAssertEqual(doubled.steps[0].instruction, original.steps[0].instruction)
        XCTAssertEqual(doubled.steps[0].durationSeconds, 600)
        XCTAssertEqual(doubled.ingredients[1].quantity, "To taste")
        XCTAssertTrue(doubled.reviewNotes.contains { $0.contains("Salt") })
        let six = try doubled.scaled(to: 6)
        XCTAssertEqual(six.ingredients[0].amount, 600)
        let restored = try six.scaled(to: 2)
        XCTAssertEqual(restored.ingredients, original.ingredients)
        XCTAssertEqual(restored.steps, original.steps)
        XCTAssertNil(restored.portionBaseline)
        XCTAssertTrue(restored.reviewNotes.isEmpty)
    }
    func testUnknownYieldAndInvalidServingsCannotPretendToScale() throws {
        var source = recipe(); source.servings = nil
        XCTAssertThrowsError(try source.scaled(to: 4))
        XCTAssertThrowsError(try recipe().scaled(to: 0))
        XCTAssertThrowsError(try recipe().scaled(to: 21))
    }
    func testRestoringSourceDoesNotKeepAdaptedStepQuantities() throws {
        var source = recipe()
        source.originalSource = OriginalRecipeSource(ingredients: [.init(id: "pasta", name: "Pasta", quantity: "100 g", sourceDetail: "Recipe text", amount: 100, unit: "g"), .init(id: "salt", name: "Salt", quantity: "To taste", sourceDetail: "Recipe text")], actions: [.init(id: "boil", instruction: "Cook 100 g of pasta.", sourceDetail: "Recipe text", durationSeconds: 600)], servings: 1)
        source.adaptations = ["Scaled to 2 servings"]
        let restored = try source.restoringSource()
        XCTAssertEqual(restored.ingredients[0].amount, 100)
        XCTAssertEqual(restored.servings, 1)
        XCTAssertEqual(restored.steps[0].instruction, "Cook 100 g of pasta.")
        XCTAssertTrue(restored.steps[0].ingredients.isEmpty)
        XCTAssertTrue(restored.adaptations.isEmpty)
        XCTAssertThrowsError(try recipe().restoringSource())
    }
    func testTimerRenamePreservesDeadlineAndRejectsBlankName() throws {
        var cook = CookAttempt(recipe: recipe())
        try cook.apply(CookAction(operation: "start_timer", sessionID: cook.id, revision: 0, seconds: 60), at: 0)
        let timer = try XCTUnwrap(cook.timers.first)
        try cook.apply(CookAction(operation: "rename_timer", sessionID: cook.id, revision: cook.revision, target: timer.id, text: "Pasta"), at: 10000)
        XCTAssertEqual(cook.timers[0].label, "Pasta")
        XCTAssertEqual(cook.timers[0].deadline, timer.deadline)
        XCTAssertThrowsError(try cook.apply(CookAction(operation: "rename_timer", sessionID: cook.id, revision: cook.revision, target: timer.id, text: "  "), at: 20000))
    }
    func testOnboardingDraftAndCustomAllergyRoundTrip() throws {
        var profile = CookProfile(); profile.onboardingStep = 1; profile.salt = "Higher"; profile.customAllergies = "Kiwi"; profile.allergyStatus = .selected; profile.spokenAnswers = false
        let decoded = try CompanionJSON.decode(CookProfile.self, CompanionJSON.encode(profile))
        XCTAssertFalse(decoded.onboardingComplete); XCTAssertEqual(decoded.onboardingStep, 1)
        XCTAssertEqual(decoded.customAllergies, "Kiwi"); XCTAssertEqual(decoded.allergyStatus, .selected)
        XCTAssertFalse(decoded.spokenAnswers)
        var none = decoded; none.setNoKnownAllergies(); XCTAssertTrue(none.customAllergies.isEmpty)
        XCTAssertEqual(try CompanionJSON.decode(CookProfile.self, "{}").onboardingStep, 0)
    }
    func testFuturePreparationUsesNewDefaultsWithoutMutatingEarlierCook() throws {
        var old = CookProfile(); old.onboardingComplete = true
        var source = recipe(); source.personalizationProfile = old
        let previousCook = CookAttempt(recipe: source, profileSnapshot: old)
        var next = old; next.servings = 4; next.allergyIDs = ["allergen.milk"]; next.salt = "Lower"
        let prepared = try source.prepared(for: next)
        XCTAssertEqual(prepared.ingredients[0].amount, 400)
        XCTAssertTrue(prepared.reviewNotes.contains { $0.contains("Milk / dairy") })
        XCTAssertTrue(prepared.reviewNotes.contains { $0.contains("preferences have changed") })
        XCTAssertEqual(previousCook.recipe.ingredients[0].amount, 200)
        XCTAssertEqual(previousCook.profileSnapshot?.salt, "Balanced")
        XCTAssertEqual(try prepared.prepared(for: next), prepared)
    }
    func testUnscalableStepAllocationRemainsExplicit() throws {
        var source = recipe(); source.steps[0].ingredients = [StepIngredient(ingredientID: "pasta", quantity: "Half the pasta")]
        let adjusted = try source.scaled(to: 4)
        XCTAssertEqual(adjusted.steps[0].ingredients[0].quantity, "Half the pasta")
        XCTAssertTrue(adjusted.reviewNotes.contains { $0.contains("Boil pasta") && $0.contains("step amounts") })
        var profile = CookProfile(); profile.customAllergies = "Kiwi"; profile.select([], for: .allergies)
        XCTAssertEqual(profile.allergyStatus, .selected)
    }
    func testRecipeWithOversizedSourceCannotEnterTheOutbox() {
        var source = recipe(); source.notes = [String(repeating: "x", count: 180001)]
        XCTAssertThrowsError(try source.validate())
    }
    func testStructuredStepQuantityMustBeFiniteAndPositive() {
        var source = recipe(); source.steps[0].ingredients[0].amount = .infinity
        XCTAssertThrowsError(try source.validate())
        source.steps[0].ingredients[0].amount = -1
        XCTAssertThrowsError(try source.validate())
    }
}
