import XCTest

extension XCTestCase {
    func preview(_ flags: String...) -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--companion-preview"] + flags; app.launch(); return app
    }
    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    func capture(_ name: String, _ app: XCUIApplication) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }
    func openPasta(_ app: XCUIApplication) {
        let tile = app.buttons["recipe-preview-pasta"]
        XCTAssertTrue(app.buttons["tab-Cookbook"].waitForExistence(timeout: 10)); reveal(tile, in: app); tile.tap()
        XCTAssertTrue(app.buttons["start-recipe"].waitForExistence(timeout: 5))
    }
    func beginPasta(_ app: XCUIApplication) {
        openPasta(app); app.buttons["start-recipe"].tap()
        XCTAssertTrue(app.buttons["begin-cooking"].waitForExistence(timeout: 5)); app.buttons["begin-cooking"].tap()
        XCTAssertTrue(app.buttons["complete-step"].waitForExistence(timeout: 5))
    }
    func dismissKeyboard(_ app: XCUIApplication) {
        if app.buttons["keyboard-done"].waitForExistence(timeout: 2) { app.buttons["keyboard-done"].tap() }
    }
}

final class CompanionFlowTests: XCTestCase {
    func testHomeNavigationAndImportModes() {
        let app = preview()
        XCTAssertTrue(app.buttons["import-recipe"].waitForExistence(timeout: 10)); capture("05 Home", app)
        app.buttons["import-recipe"].tap()
        let make = app.buttons["make-recipe"]
        XCTAssertTrue(make.waitForExistence(timeout: 5)); XCTAssertFalse(make.isEnabled)
        XCTAssertGreaterThanOrEqual(make.frame.height, 44); capture("07 Import", app)
        let url = app.textFields["recipe-url"]; url.tap(); url.typeText("https://example.com/recipe"); dismissKeyboard(app)
        XCTAssertTrue(make.isEnabled)
        let mode = app.buttons["toggle-import-mode"]; reveal(mode, in: app); mode.tap()
        XCTAssertFalse(make.isEnabled)
        let text = app.textViews["recipe-text"]; reveal(text, in: app); text.tap(); text.typeText("Toast: one slice of bread. Toast until golden."); dismissKeyboard(app)
        XCTAssertTrue(make.isEnabled); app.buttons["Close"].tap()
        app.buttons["tab-Cookbook"].tap(); XCTAssertTrue(app.buttons["recipe-preview-pasta"].waitForExistence(timeout: 5)); capture("06 Cookbook", app)
        app.buttons["tab-Album"].tap(); capture("15 Empty album", app)
        app.buttons["tab-Kitchen"].tap(); capture("16 Your kitchen", app)
        app.buttons["Kitchen defaults"].tap(); XCTAssertTrue(app.buttons["Save preferences"].waitForExistence(timeout: 5))
    }
    func testHomeChefQuestionNeedsNoRecipe() {
        let app = preview("--companion-answer-preview")
        let chef = app.buttons["home-chef"]; XCTAssertTrue(chef.waitForExistence(timeout: 10)); reveal(chef, in: app); chef.tap()
        let input = app.textFields["recipe-question"]; XCTAssertTrue(input.waitForExistence(timeout: 5)); input.tap(); input.typeText("Which pan should I use?"); dismissKeyboard(app)
        app.buttons["ask-chef"].tap()
        XCTAssertTrue(app.staticTexts["Use a wide pan so the garlic cooks evenly. Keep the heat medium-low and stir until lightly golden."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["complete-step"].exists)
    }
    func testThreeOnboardingPagesAndSavedAllergies() {
        let app = preview("--companion-onboarding")
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10)); capture("02 Dietary preferences", app)
        let allergies = app.buttons["preferences-allergies"]; reveal(allergies, in: app); allergies.tap()
        let search = app.textFields["preference-search"]; XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("soya"); dismissKeyboard(app)
        app.buttons["option-allergen.soy"].tap(); app.buttons["close-preference-picker"].tap()
        app.buttons["Next"].tap(); capture("03 Tastes and experience", app)
        app.buttons["Next"].tap(); capture("04 Kitchen defaults", app)
        app.buttons["Open my kitchen"].tap(); XCTAssertTrue(app.buttons["tab-Kitchen"].waitForExistence(timeout: 5))
        app.buttons["tab-Kitchen"].tap(); app.buttons["Cooking preferences"].tap()
        XCTAssertTrue(app.buttons["preferences-allergies"].waitForExistence(timeout: 5)); reveal(app.buttons["preferences-allergies"], in: app); app.buttons["preferences-allergies"].tap()
        XCTAssertEqual(app.buttons["option-allergen.soy"].value as? String, "Selected")
    }
    func testImportProgressCanBeClosedAndReopenedWithoutDiagnostics() {
        let app = preview("--companion-import-progress")
        let tile = app.buttons["import-tile-preview-import"]; XCTAssertTrue(tile.waitForExistence(timeout: 10)); reveal(tile, in: app); tile.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5)); capture("08 Extraction", app)
        XCTAssertFalse(app.staticTexts["Import debug details"].exists); XCTAssertFalse(app.buttons["make-recipe"].exists)
        app.buttons["Close"].tap(); reveal(tile, in: app); tile.tap(); XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 5))
    }
    func testReadyImportRequiresOverviewAndPreparation() {
        let app = preview("--companion-import-ready")
        let review = app.buttons["review-imported-recipe"]; XCTAssertTrue(review.waitForExistence(timeout: 10)); review.tap()
        XCTAssertTrue(app.buttons["start-recipe"].waitForExistence(timeout: 5)); capture("09 Recipe overview", app)
        XCTAssertFalse(app.buttons["complete-step"].exists)
        app.buttons["start-recipe"].tap(); XCTAssertTrue(app.buttons["begin-cooking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Start listening"].exists); XCTAssertFalse(app.staticTexts["Listening…"].exists)
    }
    func testServingAdjustmentRequiresReviewAndCanBeCancelled() {
        let app = preview(); openPasta(app)
        app.buttons["recipe-adjustments"].tap(); XCTAssertTrue(app.steppers.firstMatch.waitForExistence(timeout: 5))
        app.steppers.buttons["Increment"].tap(); app.buttons["Close"].tap()
        app.buttons["recipe-adjustments"].tap(); XCTAssertTrue(app.staticTexts["2 servings"].waitForExistence(timeout: 5))
        app.steppers.buttons["Increment"].tap()
        let use = app.buttons["Use these adjustments"]; reveal(use, in: app); use.tap()
        app.buttons["start-recipe"].tap(); XCTAssertTrue(app.buttons["begin-cooking"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["begin-cooking"].isEnabled)
        let review = app.switches["review-preparation"]; reveal(review, in: app); review.tap()
        XCTAssertTrue(app.buttons["begin-cooking"].isEnabled)
    }
    func testRecipeArchiveRestoresAndDeletionKeepsCook() {
        let app = preview(); beginPasta(app); app.buttons["Save and leave cooking"].tap()
        openPasta(app); app.buttons["Recipe options"].tap(); app.buttons["Archive recipe"].tap()
        app.buttons["tab-Cookbook"].tap(); XCTAssertFalse(app.buttons["recipe-preview-pasta"].exists)
        app.buttons["Filter recipes"].tap(); app.buttons["Show archived"].tap()
        let tile = app.buttons["recipe-preview-pasta"]; XCTAssertTrue(tile.waitForExistence(timeout: 5)); tile.tap()
        app.buttons["Recipe options"].tap(); app.buttons["Restore to cookbook"].tap()
        app.buttons["tab-Home"].tap(); openPasta(app)
        app.buttons["Recipe options"].tap(); app.buttons["delete-recipe"].tap()
        XCTAssertTrue(app.alerts.buttons["Cancel"].waitForExistence(timeout: 5)); app.alerts.buttons["Delete recipe"].tap()
        XCTAssertTrue(tile.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cook-'")).firstMatch.exists)
    }
    func testSharedRecipePreservesReviewAndNativeSharing() {
        let app = preview("--companion-share-preview", "--companion-shared-recipe")
        XCTAssertTrue(app.buttons["start-recipe"].waitForExistence(timeout: 10))
        app.buttons["Recipe options"].tap(); app.buttons["share-recipe"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5)); capture("Native recipe sharing", app)
    }
}
