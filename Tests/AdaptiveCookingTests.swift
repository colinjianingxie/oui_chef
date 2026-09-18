import XCTest
@testable import OuiChefCore

final class AdaptiveCookingTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func prepared(_ id: String) throws -> CookingSession {
        let recipe = try XCTUnwrap(RecipeCatalog.bundled().recipes.first { $0.id == id })
        var session = try CookingSession(recipe: recipe)
        session.confirmAllIngredients(true, at: now); session.labelsChecked = true
        try session.completePreparation(at: now)
        return session
    }
    func testReportedExcessRecoveryIsSeparateFromPhysicalAdditionAndSurvivesRelaunch() throws {
        var session = try prepared("margarita")
        try session.begin("measure", at: now); try session.finish("measure", confirmed: true, at: now)
        try session.begin("shake", at: now)
        let deadline = session.timers.first!.deadline
        try session.reportAmount("lime", amount: 30, unit: "mL", at: now)
        XCTAssertThrowsError(try session.reportAmount("lime", amount: 2, unit: "tbsp", at: now))
        let plan = try session.proposeRecovery("restore_balance", value: 1, nodeID: "shake")
        XCTAssertEqual(plan.additions, ["tequila": 50, "liqueur": 20])
        try session.acceptRecovery(plan, at: now)
        XCTAssertEqual(session.recipe.ingredients.first { $0.id == "tequila" }!.amount, 50)
        XCTAssertThrowsError(try session.completeRecovery(at: now))
        XCTAssertThrowsError(try session.finish("shake", confirmed: true, at: now))
        for id in plan.additions.keys { try session.confirmRecoveryIngredient(id, checked: true, at: now) }
        session.labelsChecked = false
        XCTAssertThrowsError(try session.completeRecovery(at: now))
        session.labelsChecked = true
        session = try JSONDecoder().decode(CookingSession.self, from: JSONEncoder().encode(session))
        try session.completeRecovery(at: now)
        XCTAssertEqual(session.reportedAmounts?["tequila"], 100)
        XCTAssertEqual(session.timers.first?.deadline, deadline)
        XCTAssertFalse(session.completed.contains("shake"))
        XCTAssertEqual(session.sourceRecipe?.ingredients.first?.amount, 50)
        XCTAssertThrowsError(try session.acceptRecovery(plan, at: now))
        XCTAssertThrowsError(try session.undoCorrection(at: now))
        try session.reportAmount("lime", amount: 1000, unit: "mL", at: now)
        XCTAssertEqual(session.reportedAmounts?["lime"], 1000)
        XCTAssertThrowsError(try session.proposeRecovery("restore_balance", value: 1, nodeID: "shake"))
    }
    func testUndoProgressPreservesTimerAndRejectsStartedDescendants() throws {
        var session = try prepared("bread")
        try session.begin("mix", at: now); try session.finish("mix", confirmed: true, at: now)
        try session.begin("knead", at: now)
        let deadline = session.timers.first!.deadline
        try session.finish("knead", confirmed: true, at: now.addingTimeInterval(100))
        try session.reopen("knead", at: now.addingTimeInterval(200))
        XCTAssertEqual(session.timers.first!.deadline, deadline)
        try session.finish("knead", confirmed: true, at: now)
        try session.begin("first_proof", at: now)
        XCTAssertThrowsError(try session.reopen("knead", at: now))
        try session.reportAmount("water", amount: 240, unit: "g", at: now)
        try session.undoCorrection(at: now)
        XCTAssertNil(session.reportedAmounts)
    }
    func testBreadRecoveryBoundsAndCancelledPlanDoNotAddIngredients() throws {
        var session = try prepared("bread")
        try session.begin("mix", at: now); try session.finish("mix", confirmed: true, at: now)
        try session.begin("knead", at: now)
        let plan = try session.proposeRecovery("moisten_dough", value: 5, nodeID: "knead")
        try session.acceptRecovery(plan, at: now); session.cancelRecovery(at: now)
        XCTAssertNil(session.reportedAmounts)
        try session.reportAmount("water", amount: 237, unit: "g", at: now)
        XCTAssertThrowsError(try session.proposeRecovery("moisten_dough", value: 5, nodeID: "knead"))
        XCTAssertThrowsError(try session.proposeRecovery("moisten_dough", value: .nan, nodeID: "knead"))
    }
    func testSwitchAndResumeKeepEachRecipeProgressAndTimerDeadline() throws {
        var first = try prepared("margarita")
        try first.begin("measure", at: now); try first.finish("measure", confirmed: true, at: now)
        try first.begin("shake", at: now)
        let second = try prepared("bread")
        var archive = AppArchive(); archive.session = first
        archive.activate(second)
        XCTAssertEqual(archive.session?.id, second.id)
        XCTAssertEqual(archive.history.first?.timers, first.timers)
        XCTAssertEqual(archive.history.first?.completed, first.completed)
        XCTAssertEqual(archive.history.first?.guidancePaused, true)
        archive = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
        archive.activate(try XCTUnwrap(archive.history.first))
        XCTAssertEqual(archive.session?.id, first.id)
        XCTAssertEqual(archive.session?.timers, first.timers)
        XCTAssertEqual(archive.history.map(\.id), [second.id])
        XCTAssertTrue(archive.dishes.isEmpty)
    }

    func testCompletionIsIdempotentAndRepeatedCooksHaveSeparateRecords() throws {
        var session = try prepared("margarita")
        for id in ["measure", "shake", "strain"] { try session.begin(id, at: now); try session.finish(id, confirmed: true, at: now) }
        var archive = AppArchive()
        archive.reconcileCompletion(session); archive.reconcileCompletion(session)
        XCTAssertEqual(archive.dishes.count, 1)
        XCTAssertEqual(archive.dishes[0].completedAt, now)
        archive.completedDishes?[0].photoFile = "preserved.jpg"
        try session.reopen("strain", at: now)
        archive.reconcileCompletion(session)
        XCTAssertTrue(archive.dishes.isEmpty)
        try session.finish("strain", confirmed: true, at: now)
        archive.reconcileCompletion(session)
        XCTAssertEqual(archive.dishes.count, 1)
        XCTAssertEqual(archive.dishes[0].photoFile, "preserved.jpg")
        var another = session; another.id = UUID()
        archive.reconcileCompletion(another)
        XCTAssertEqual(archive.dishes.count, 2)
        archive = try JSONDecoder().decode(AppArchive.self, from: JSONEncoder().encode(archive))
        XCTAssertEqual(archive.dishes.count, 2)
    }
}
