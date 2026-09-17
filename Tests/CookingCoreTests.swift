import XCTest
@testable import OuiChefCore

final class CookingCoreTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    func prepared(_ id: String) throws -> CookingSession {
        let catalog = try RecipeCatalog.bundled()
        var session = try CookingSession(recipe: XCTUnwrap(catalog.recipes.first { $0.id == id }))
        session.confirmedIngredients = Set(session.recipe.ingredients.map(\.id))
        session.confirmedTools = Set(session.recipe.tools)
        session.labelsChecked = true
        try session.completePreparation(at: now)
        return session
    }

    func testEveryRecipeTraversesAndInvalidGraphsFail() throws {
        let catalog = try RecipeCatalog.bundled()
        XCTAssertEqual(catalog.recipes.count, 3)
        for recipe in catalog.recipes {
            var session = try prepared(recipe.id)
            while !session.finished {
                let node = try XCTUnwrap(session.eligibleNodes.first)
                try session.begin(node.id, at: now)
                try session.finish(node.id, confirmed: true, at: now)
            }
            XCTAssertTrue(session.timers.isEmpty)
        }
        var bad = catalog
        bad.recipes[0].nodes[0].dependsOn = [bad.recipes[0].nodes[0].id]
        XCTAssertThrowsError(try bad.validate())
        bad = catalog
        bad.recipes[0].nodes[0].inputs = ["missing_state"]
        XCTAssertThrowsError(try bad.validate())
    }

    func testReadinessPrerequisitesAndDuplicateCommands() throws {
        let catalog = try RecipeCatalog.bundled()
        var session = try CookingSession(recipe: catalog.recipes[0])
        XCTAssertThrowsError(try session.begin("prep", at: now))
        session = try prepared("spaghetti")
        XCTAssertThrowsError(try session.begin("combine", at: now))
        try session.begin("prep", at: now)
        let revision = session.revision
        try session.begin("prep", at: now)
        XCTAssertEqual(session.revision, revision)
        XCTAssertThrowsError(try session.finish("prep", confirmed: false, at: now))
        try session.finish("prep", confirmed: true, at: now)
        try session.finish("prep", confirmed: true, at: now)
        XCTAssertEqual(session.completed, ["prep"])
    }

    func testProofingSurvivesPauseRelaunchAndRetry() throws {
        var session = try prepared("bread")
        for id in ["mix", "knead"] {
            try session.begin(id, at: now)
            try session.finish(id, confirmed: true, at: now)
        }
        try session.begin("first_proof", at: now)
        let deadline = try XCTUnwrap(session.timers.first?.deadline)
        session.pause(true, at: now.addingTimeInterval(10))
        XCTAssertEqual(session.timers.first?.deadline, deadline)
        session = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
        XCTAssertEqual(session.timers.first?.deadline, deadline)
        XCTAssertFalse(session.completed.contains("first_proof"))
        XCTAssertNil(session.dueCue(at: deadline, detailed: true))
        session.pause(false, at: deadline)
        XCTAssertTrue(session.resumeMessage(at: deadline).contains("first rise"))
        try session.recheck("first_proof", at: deadline)
        XCTAssertEqual(session.timers.first?.attempt, 2)
        XCTAssertFalse(session.eligibleNodes.contains { $0.id == "shape" })
        try session.finish("first_proof", confirmed: true, at: deadline)
        try session.begin("shape", at: deadline)
        try session.finish("shape", confirmed: true, at: deadline)
        try session.begin("second_proof", at: deadline)
        XCTAssertTrue(session.resumeMessage(at: deadline).contains("second rise"))
    }

    func testCoachingDoesNotRepeatAdvanceOrReplayStaleCues() throws {
        var session = try prepared("margarita")
        try session.begin("measure", at: now)
        try session.finish("measure", confirmed: true, at: now)
        try session.begin("shake", at: now)
        let cue = try XCTUnwrap(session.dueCue(at: now.addingTimeInterval(9), detailed: true))
        session.deliver(cue, at: now.addingTimeInterval(9))
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(10), detailed: true))
        XCTAssertFalse(session.completed.contains("shake"))
        session.pendingQuestionNodeID = nil
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(10), detailed: true))
        try session.finish("shake", confirmed: true, at: now.addingTimeInterval(16))
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(100), detailed: true))
    }

    func testRatioPreviewUsesFixedBaseAndRejectsStaleOrConsumedChanges() throws {
        var session = try prepared("margarita")
        let proposal = try session.proposeRatio("sweetness", value: 0.3)
        XCTAssertEqual(proposal.newAmount, 15)
        try session.apply(proposal, at: now)
        XCTAssertEqual(session.recipe.ingredients.first { $0.id == "tequila" }?.amount, 50)
        XCTAssertFalse(session.confirmedIngredients.contains("liqueur"))
        XCTAssertThrowsError(try session.apply(proposal, at: now))
        XCTAssertThrowsError(try session.proposeRatio("sweetness", value: .nan))
        XCTAssertThrowsError(try session.proposeRatio("sweetness", value: 8))
        try session.confirmIngredient("liqueur", at: now)
        try session.completePreparation(at: now)
        try session.begin("measure", at: now)
        try session.finish("measure", confirmed: true, at: now)
        try session.begin("shake", at: now)
        XCTAssertThrowsError(try session.proposeRatio("sweetness", value: 0.4))
    }

    func testManualPreparationScalingAndArchiveCompatibility() throws {
        let recipe = try XCTUnwrap(RecipeCatalog.bundled().recipes.first { $0.id == "margarita" })
        var session = try CookingSession(recipe: recipe)
        session.confirmAllIngredients(true, at: now)
        XCTAssertEqual(session.confirmedIngredients.count, recipe.ingredients.count)
        XCTAssertFalse(session.labelsChecked)
        XCTAssertTrue(session.confirmedTools.isEmpty)
        XCTAssertThrowsError(try session.completePreparation(at: now))
        session.confirmedTools = Set(recipe.tools)
        session.labelsChecked = true
        XCTAssertTrue(session.checksComplete)
        XCTAssertFalse(session.ready)
        XCTAssertThrowsError(try session.begin("measure", at: now))
        try session.setServings(2, at: now)
        XCTAssertTrue(session.confirmedIngredients.isEmpty)
        XCTAssertEqual(session.recipe.ingredients.first?.amount, 100)
        session.confirmAllIngredients(true, at: now)
        try session.completePreparation(at: now)
        XCTAssertTrue(session.ready)
        session = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
        XCTAssertTrue(session.ready)
        try session.begin("measure", at: now)
        XCTAssertThrowsError(try session.setServings(1, at: now))
        // Saved sessions from before the manual review screen still resume.
        var old = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(session)) as? [String: Any])
        old.removeValue(forKey: "preparationCompletedAt")
        let restored = try JSONDecoder().decode(CookingSession.self, from: JSONSerialization.data(withJSONObject: old))
        XCTAssertTrue(restored.ready)
        XCTAssertEqual(restored.started, ["measure"])
    }

    func testCheckInsContinueWithoutReplyAndNeverCompleteTasks() throws {
        var session = try prepared("margarita")
        try session.begin("measure", at: now)
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(59), detailed: false))
        let first = try XCTUnwrap(session.dueCue(at: now.addingTimeInterval(60), detailed: false))
        session.deliver(first, at: now.addingTimeInterval(60))
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(61), detailed: true))
        let followup = try XCTUnwrap(session.dueCue(at: now.addingTimeInterval(120), detailed: false))
        XCTAssertNotEqual(first.id, followup.id)
        session.deliver(followup, at: now.addingTimeInterval(120))
        XCTAssertTrue(session.completed.isEmpty)
        try session.recheck("measure", at: now.addingTimeInterval(121))
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(180), detailed: false))
        XCTAssertNotNil(session.dueCue(at: now.addingTimeInterval(181), detailed: false))
        try session.finish("measure", confirmed: true, at: now.addingTimeInterval(182))
        try session.begin("shake", at: now.addingTimeInterval(182))
        let tip = try XCTUnwrap(session.dueCue(at: now.addingTimeInterval(190), detailed: true))
        session.deliver(tip, at: now.addingTimeInterval(190))
        // An unanswered halfway cue must not block the actual timer check.
        let due = try XCTUnwrap(session.dueCue(at: now.addingTimeInterval(197), detailed: true))
        XCTAssertEqual(due.id, "due:shake:1")
        session.deliver(due, at: now.addingTimeInterval(197))
        session.record("readiness_asked", nodeID: "shake", at: now.addingTimeInterval(200))
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(205), detailed: true))
        XCTAssertNotNil(session.dueCue(at: now.addingTimeInterval(215), detailed: true))
        session.pause(true, at: now.addingTimeInterval(216))
        XCTAssertNil(session.dueCue(at: now.addingTimeInterval(300), detailed: true))
        XCTAssertEqual(session.completed, ["measure"])
    }

    func testAllergensIncludeCompoundAndUnknownIngredients() throws {
        var catalog = try RecipeCatalog.bundled()
        XCTAssertTrue(catalog.allergyConcerns(for: catalog.recipes[0], avoiding: ["wheat"]).contains { $0.contains("wheat") })
        XCTAssertTrue(catalog.allergyConcerns(for: catalog.recipes[2], avoiding: ["peanut"]).contains { $0.contains("check the label") })
        catalog.foods.append(Food(id: "compound", name: "Sauce", allergens: [], constituents: ["flour"], compositionKnown: true))
        catalog.recipes[0].ingredients[0].foodID = "compound"
        XCTAssertFalse(catalog.allergyConcerns(for: catalog.recipes[0], avoiding: ["wheat"]).isEmpty)
    }

    func testVoiceNegationsAreNotCompletionAndToolsCannotBeDoubleBooked() throws {
        XCTAssertEqual(VoiceCommand.parse("I'm not done"), .unknown)
        XCTAssertEqual(VoiceCommand.parse("not yet"), .notYet)
        XCTAssertEqual(VoiceCommand.parse("done"), .done)
        XCTAssertEqual(VoiceCommand.parse("I'm finished"), .done)
        XCTAssertEqual(VoiceCommand.parse("yes"), .yes)
        XCTAssertEqual(VoiceCommand.parse("stop listening"), .mute)
        XCTAssertEqual(VoiceCommand.parse("find pasta"), .recipe("spaghetti"))
        var session = try prepared("spaghetti")
        session.recipe.nodes[0].tools = ["Large pot"]
        try session.begin("boil", at: now)
        XCTAssertThrowsError(try session.begin("prep", at: now))
        try session.finish("boil", confirmed: true, at: now)
        try session.begin("prep", at: now)
    }

    func testReturnPrioritizesOverdueTaskOverAnEarlierQuestion() throws {
        var session = try prepared("spaghetti")
        try session.begin("prep", at: now)
        try session.finish("prep", confirmed: true, at: now)
        try session.begin("saute", at: now)
        try session.begin("boil", at: now)
        session.pendingQuestionNodeID = "boil"
        let returnTime = now.addingTimeInterval(100)
        XCTAssertEqual(session.focus(at: returnTime)?.id, "saute")
        XCTAssertTrue(session.resumeMessage(at: returnTime).contains("timer finished"))
    }
}
