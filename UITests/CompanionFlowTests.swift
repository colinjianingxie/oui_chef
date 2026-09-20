import XCTest

final class CompanionFlowTests: XCTestCase {
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    func testPreferencesDoNotRequireEquipment() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--companion-preview", "--companion-onboarding"]; app.launch()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 10)); capture("01 Dietary preferences", app)
        app.buttons["Next"].tap(); capture("02 Cooking preferences", app)
        app.buttons["Next"].tap(); capture("03 Your kitchen", app)
        for _ in 0..<3 where !app.buttons["Open my kitchen"].isHittable { app.swipeUp() }
        app.buttons["Open my kitchen"].tap()
        XCTAssertTrue(app.buttons["import-recipe"].waitForExistence(timeout: 5))
    }
    func testCookWithTimerRepeatStepAndSaveMemory() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--companion-preview"]; app.launch()
        XCTAssertTrue(app.buttons["recipe-preview-pasta"].waitForExistence(timeout: 10)); capture("04 Cookbook", app)
        app.buttons["import-recipe"].tap(); capture("05 Import a recipe", app); app.buttons["Close"].tap()
        app.buttons["recipe-preview-pasta"].tap()
        XCTAssertTrue(app.buttons["Start cooking"].waitForExistence(timeout: 5)); capture("06 Recipe", app)
        app.buttons["Start cooking"].tap(); capture("07 Ingredient preparation", app)
        app.buttons["Let’s cook"].tap()
        let done = app.buttons["complete-step"]
        XCTAssertTrue(done.waitForExistence(timeout: 5)); capture("08 Current step", app)
        done.tap()
        let timer = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Start 1m 30s timer")).firstMatch
        for _ in 0..<3 where !timer.isHittable { app.swipeUp() }
        XCTAssertTrue(timer.exists); timer.tap()
        XCTAssertTrue(app.buttons["Pause Sauté the garlic"].waitForExistence(timeout: 5)); capture("09 Cooking timer", app)
        app.buttons["Pause Sauté the garlic"].tap()
        XCTAssertTrue(app.buttons["Resume Sauté the garlic"].exists)
        app.buttons["Previous step"].tap()
        XCTAssertEqual(done.label, "Next unfinished step")
        done.tap(); done.tap(); done.tap()
        XCTAssertEqual(done.label, "Finish cooking"); done.tap()
        XCTAssertTrue(app.staticTexts["You did it!"].waitForExistence(timeout: 5)); capture("10 Finished cooking", app)
        app.buttons["Save photo"].tap(); capture("11 Dish photo", app); app.buttons["Skip for now"].tap()
        for _ in 0..<3 where !app.buttons["Back to my cookbook"].isHittable { app.swipeUp() }
        app.buttons["Back to my cookbook"].tap(); app.buttons["tab-Album"].tap()
        XCTAssertTrue(app.staticTexts["Made by you."].waitForExistence(timeout: 5)); capture("12 Cooking album", app)
        XCTAssertTrue(app.buttons.containing(.staticText,identifier:"Creamy garlic pasta").firstMatch.exists)
    }
}
