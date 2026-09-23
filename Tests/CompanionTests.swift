import XCTest
@testable import OuiChefCore

final class CompanionTests: XCTestCase {
    func testPreferenceSearchSelectionsAndAgentPayload() throws {
        XCTAssertFalse(PreferenceSection.foods.isEmpty)
        for section in PreferenceSection.allCases {
            XCTAssertEqual(Set(section.options.map(\.id)).count, section.options.count)
        }
        XCTAssertTrue(PreferenceSection.allergies.options.contains { $0.id == "allergen.soy" && $0.matches("  SOYA ") })
        XCTAssertTrue(PreferenceSection.dislikes.options.contains { $0.matches("courgette") })
        var profile = CookProfile()
        XCTAssertEqual(profile.allergyStatus, .unspecified)
        profile.setNoKnownAllergies()
        XCTAssertEqual(profile.allergyStatus, .noneKnown)
        profile.select(["allergen.peanuts"], for: .allergies)
        XCTAssertEqual(profile.allergyStatus, .selected)
        profile.voiceLanguage = "Mandarin"
        profile.select(["gluten_free"], for: .restrictions)
        profile.select(["air_fryer"], for: .equipment)
        let encoded = try CompanionJSON.encode(profile)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        XCTAssertEqual(payload["voiceLanguage"] as? String, "Mandarin")
        XCTAssertEqual(payload["allergies"] as? [String], ["Peanuts"])
        XCTAssertEqual(payload["restrictions"] as? [String], ["Gluten-free"])
        XCTAssertEqual(payload["equipment"] as? [String], ["Air fryer"])
        XCTAssertEqual(try CompanionJSON.decode(CookProfile.self, encoded), profile)
        profile.select([], for: .allergies)
        XCTAssertEqual(profile.allergyStatus, .unspecified, "Clearing a checklist must not imply no allergies.")
        profile.setNoKnownAllergies()
        XCTAssertTrue(profile.allergyIDs.isEmpty)
    }

    func testOldPreferencesRemainExplicitUntilReviewed() throws {
        let old = #"{"onboardingComplete":true,"allergies":"peanuts and an unusual allergy","dislikes":"cilantro","equipment":"no oven","diet":"Other"}"#
        let migrated = try CompanionJSON.decode(CookProfile.self, old)
        XCTAssertEqual(migrated.voiceLanguage, "English")
        XCTAssertTrue(migrated.onboardingComplete)
        XCTAssertTrue(migrated.needsPreferenceReview)
        XCTAssertEqual(migrated.allergyStatus, .unspecified)
        XCTAssertTrue(migrated.allergyIDs.isEmpty, "Do not guess structured allergies from earlier prose.")
        XCTAssertEqual(migrated.previousPreferencesPendingReview["allergies"], "peanuts and an unusual allergy")
        XCTAssertEqual(try CompanionJSON.decode(CookProfile.self, CompanionJSON.encode(migrated)), migrated)
        var reviewed = migrated
        reviewed.select(["allergen.peanuts"], for: .allergies)
        reviewed.previousPreferencesPendingReview = [:]
        XCTAssertFalse(try CompanionJSON.decode(CookProfile.self, CompanionJSON.encode(reviewed)).needsPreferenceReview)
    }

    func testImportProgressDecodesOldJobsAndNewPreviews() throws {
        let old = #"{"id":"job","url":"https://youtu.be/W_-D8PZwtSY","status":"transcribing","message":"Reading captions","createdAt":0,"source":"YouTube"}"#
        var item = try CompanionJSON.decode(RecipeImport.self, old)
        XCTAssertTrue(item.running)
        XCTAssertEqual(item.progressStage, 2)
        item.status = "checking"; item.stage = 4; item.attempt = 2
        item.previewTitle = "Matcha bread"; item.previewIngredients = ["415 g bread flour"]
        item.sourceTitle = "Chinese beef stew"; item.recipeTitle = "Red-braised beef"
        item.originalTranscript = "[88.51s] 冷水下锅。"; item.transcriptLanguage = "zh-CN"
        item.translatedTranscript = "[88.51s] Put it in cold water."; item.frameSeconds = [10, 30]
        item.videoObservations = "[10s] Beef is cut into cubes."
        item.failurePoint = "Written source"
        let saved = try CompanionJSON.decode(RecipeImport.self, CompanionJSON.encode(item))
        XCTAssertEqual(saved.progressStage, 4)
        XCTAssertEqual(saved.attempt, 2)
        XCTAssertEqual(saved.previewIngredients, ["415 g bread flour"])
        XCTAssertEqual(saved.originalTranscript, "[88.51s] 冷水下锅。")
        XCTAssertEqual(saved.translatedTranscript, "[88.51s] Put it in cold water.")
        XCTAssertEqual(saved.frameSeconds, [10, 30])
        XCTAssertEqual(saved.videoObservations, "[10s] Beef is cut into cubes.")
        XCTAssertTrue(saved.hasImportEvidence)
        item.status = "skipped"
        XCTAssertFalse(item.running)
    }

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
