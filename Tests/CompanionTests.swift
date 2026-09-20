import XCTest
@testable import OuiChefCore

final class CompanionTests: XCTestCase {
    func recipe() -> CompanionRecipe {
        CompanionRecipe(id: "bread", title: "Bread", sourceURL: "https://example.com/bread", sourceName: "Website",
            ingredients: [RecipeIngredient(id: "flour", name: "Flour", quantity: "Amount not specified")],
            steps: [RecipeStep(id: "proof1", title: "First proof", instruction: "Rest until doubled.", stage: "First proof", durationSeconds: 60), RecipeStep(id: "proof2", title: "Second proof", instruction: "Rest until puffy.", stage: "Second proof")])
    }
    func testMinimalRecipeAcceptsUnknownEquipmentAmountsAndTiming() throws {
        let recipe = recipe(); try recipe.validate()
        XCTAssertTrue(recipe.equipment.isEmpty)
        XCTAssertNil(recipe.ingredients[0].amount)
        XCTAssertNil(recipe.steps[1].durationSeconds)
        let decoded = try CompanionJSON.decode(CompanionRecipe.self, CompanionJSON.encode(recipe))
        XCTAssertEqual(decoded, recipe)
        var bad = recipe; bad.steps[0].ingredients = [StepIngredient(ingredientID: "missing", quantity: "1 cup")]
        XCTAssertThrowsError(try bad.validate())
    }
    func testTimersRecoveryIdempotencyAndProofHistory() throws {
        var cook = CookAttempt(recipe: recipe())
        let action = CookAction(operation: "start_timer", sessionID: cook.id, revision: 0, target: "proof1", seconds: 60)
        try cook.apply(action, at: 1000)
        try cook.apply(action, at: 2000)
        XCTAssertEqual(cook.timers.count, 1)
        XCTAssertTrue(cook.timers[0].expired(at: 61000))
        XCTAssertTrue(cook.completed.isEmpty, "Timer expiry must not complete a proof.")
        cook.deliveredReminders.append(action.id)
        try cook.apply(CookAction(operation: "extend_timer", sessionID: cook.id, revision: cook.revision, target: action.id, seconds: 180), at: 61000)
        XCTAssertEqual(cook.timers[0].deadline, 241000)
        XCTAssertFalse(cook.deliveredReminders.contains(action.id), "An extended timer must be eligible to alert again.")
        try cook.apply(CookAction(operation: "pause_timer", sessionID: cook.id, revision: cook.revision, target: action.id), at: 62000)
        let restored = try CompanionJSON.decode(CookAttempt.self, CompanionJSON.encode(cook))
        XCTAssertEqual(restored.timers[0].remaining(at: 9999999), 179)
        try cook.apply(CookAction(operation: "complete_step", sessionID: cook.id, revision: cook.revision, target: "proof1"), at: 65000)
        XCTAssertEqual(cook.count("complete_step", stepID: "proof1"), 1)
        XCTAssertEqual(cook.count("complete_step", stepID: "proof2"), 0)
        try cook.apply(CookAction(operation: "focus_step", sessionID: cook.id, revision: cook.revision, target: "proof1"), at: 66000)
        XCTAssertTrue(cook.completed.contains("proof1"), "Browsing does not undo completion.")
        XCTAssertThrowsError(try cook.apply(CookAction(operation: "skip_step", sessionID: cook.id, revision: 0), at: 67000))
        try cook.apply(CookAction(operation: "reopen_step", sessionID: cook.id, revision: cook.revision, target: "proof1"), at: 67100)
        try cook.apply(CookAction(operation: "complete_step", sessionID: cook.id, revision: cook.revision, target: "proof1"), at: 67200)
        XCTAssertEqual(cook.count("complete_step", stepID: "proof1"), 2)
        XCTAssertEqual(cook.count("complete_step", stepID: "proof2"), 0)
        try cook.apply(CookAction(operation: "complete_step", sessionID: cook.id, revision: cook.revision, target: "proof2"), at: 68000)
        XCTAssertNil(cook.finishedAt, "User explicitly finishes before active timers are dismissed.")
        try cook.apply(CookAction(operation: "finish", sessionID: cook.id, revision: cook.revision), at: 69000)
        XCTAssertEqual(cook.finishedAt, 69000)
        XCTAssertTrue(cook.timers.allSatisfy(\.acknowledged))
    }
}
