import XCTest

final class CompanionFlowTests: XCTestCase {
    private func capture(_ name: String, _ app: XCUIApplication) {
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = name; image.lifetime = .keepAlways; add(image)
    }
    private func dismissKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["keyboard-done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 3))
    }
    func testImportModesAndButtonLayout() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--companion-preview"]; app.launch()
        XCTAssertTrue(app.buttons["import-recipe"].waitForExistence(timeout: 10)); app.buttons["import-recipe"].tap()
        let make = app.buttons["make-recipe"]
        XCTAssertTrue(make.waitForExistence(timeout: 5)); XCTAssertFalse(make.isEnabled)
        XCTAssertGreaterThanOrEqual(make.frame.height, 44)
        XCTAssertFalse(app.staticTexts["Good recipes travel far."].exists)
        XCTAssertFalse(app.staticTexts["YouTube"].exists)
        capture("Import link mode — empty", app)
        let url = app.textFields["recipe-url"]
        url.tap(); url.typeText("https://youtu.be/cooking"); dismissKeyboard(app)
        XCTAssertTrue(make.isEnabled)
        capture("Import link mode — ready", app)
        let toggle = app.buttons["toggle-import-mode"]
        toggle.tap()
        XCTAssertFalse(make.isEnabled)
        let text = app.textViews["recipe-text"]
        XCTAssertTrue(text.waitForExistence(timeout: 3)); text.tap(); text.typeText("Toast: one slice of bread. Toast until golden."); dismissKeyboard(app)
        XCTAssertTrue(make.isEnabled)
        capture("Import pasted text mode", app)
        for _ in 0..<3 where !toggle.isHittable { app.swipeUp() }
        toggle.tap()
        XCTAssertEqual(url.value as? String, "https://youtu.be/cooking")
        XCTAssertTrue(app.staticTexts["Coming soon"].exists)
        XCTAssertFalse(app.buttons["Upload a photo"].exists)
    }
    func testEmailSignInGoesStraightToPreferences() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--auth-emulator"]; app.launch()
        let emailButton = app.buttons["Sign up or sign in with email"]
        XCTAssertTrue(emailButton.waitForExistence(timeout: 10)); emailButton.tap()
        XCTAssertTrue(app.textFields["Email address"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Continue with Google"].isHittable)
        XCTAssertFalse(app.buttons["Add a sign-in method"].exists)
        app.buttons["Create account"].firstMatch.tap()
        app.textFields["Email address"].tap()
        app.textFields["Email address"].typeText("preferences-\(UUID().uuidString.lowercased())@example.invalid")
        dismissKeyboard(app)
        let password = app.secureTextFields.firstMatch
        password.tap(); password.typeText("CookingTest123!"); dismissKeyboard(app)
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.buttons["Next"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["Delete account"].exists)
        XCTAssertFalse(app.buttons["Add a sign-in method"].exists)
        XCTAssertFalse(app.buttons["email-submit"].exists)
        capture("Sign-in opens preferences directly", app)
    }

    func testSearchablePreferencesAndKeyboardDone() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--companion-preview", "--companion-onboarding"]; app.launch()
        let allergies = app.buttons["preferences-allergies"]
        XCTAssertTrue(allergies.waitForExistence(timeout: 10))
        for _ in 0..<3 where !allergies.isHittable { app.swipeUp() }
        allergies.tap()
        let search = app.textFields["preference-search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5)); search.tap(); search.typeText("soya")
        let soy = app.buttons["option-allergen.soy"]
        XCTAssertTrue(soy.waitForExistence(timeout: 3)); soy.tap()
        dismissKeyboard(app)
        XCTAssertEqual(search.value as? String, "soya")
        app.buttons["Clear search"].tap()
        XCTAssertEqual(soy.value as? String, "Selected")
        app.buttons["allergy-none"].tap()
        XCTAssertEqual(app.buttons["allergy-none"].value as? String, "Selected")
        XCTAssertTrue(app.staticTexts["0 selected"].exists)
        app.buttons["option-allergen.peanuts"].tap()
        capture("Searchable allergy checklist", app)
        app.buttons["close-preference-picker"].tap()
        app.buttons["preferences-allergies"].tap()
        XCTAssertEqual(app.buttons["option-allergen.peanuts"].value as? String, "Selected")
        app.buttons["close-preference-picker"].tap()
        app.buttons["Next"].tap()
        app.buttons["preferences-dislikes"].tap()
        search.tap(); search.typeText("courgette"); dismissKeyboard(app)
        let zucchini = app.buttons.containing(.staticText, identifier: "Zucchini").firstMatch
        XCTAssertTrue(zucchini.exists); zucchini.tap()
        app.buttons["close-preference-picker"].tap()
        app.buttons["Next"].tap(); app.buttons["Open my kitchen"].tap()
        XCTAssertTrue(app.buttons["import-recipe"].waitForExistence(timeout: 5))
        app.textFields["Search your recipes…"].tap(); app.textFields["Search your recipes…"].typeText("pasta"); dismissKeyboard(app)
        app.buttons["Import recipe"].tap()
        let url = app.textFields["recipe-url"]; XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.tap(); url.typeText("https://example.com/recipe"); dismissKeyboard(app)
        XCTAssertEqual(url.value as? String, "https://example.com/recipe")
        app.buttons["Close"].tap(); app.buttons["tab-Profile"].tap()
        XCTAssertFalse(app.buttons["Delete account"].exists)
        XCTAssertFalse(app.buttons["Add a sign-in method"].exists)
        app.buttons["Cooking preferences"].firstMatch.tap()
        let saved = app.buttons["preferences-allergies"]
        for _ in 0..<3 where !saved.isHittable { app.swipeUp() }
        saved.tap()
        XCTAssertEqual(app.buttons["option-allergen.peanuts"].value as? String, "Selected")
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
        let addTimer = app.buttons["Add timer"]
        for _ in 0..<3 where !addTimer.isHittable { app.swipeUp() }
        addTimer.tap()
        let numeric = app.textFields["cooking-entry"]
        XCTAssertTrue(numeric.waitForExistence(timeout: 3)); numeric.tap(); numeric.typeText("5")
        dismissKeyboard(app)
        XCTAssertEqual(numeric.value as? String, "105")
        XCTAssertTrue(app.buttons["Start timer"].exists)
        app.buttons["Cancel"].tap()
        app.buttons["Ask a question or show an ingredient"].tap()
        let question = app.descendants(matching: .any)["recipe-question"]
        XCTAssertTrue(question.waitForExistence(timeout: 3)); question.tap(); question.typeText("Can I use a small pan?")
        dismissKeyboard(app)
        XCTAssertEqual(question.value as? String, "Can I use a small pan?")
        app.buttons["Close"].tap()
        app.buttons["Cooking options"].tap(); app.buttons["Record a substitution or change"].tap()
        let change = app.textFields["cooking-entry"]
        XCTAssertTrue(change.waitForExistence(timeout: 3)); change.tap(); change.typeText("Used a smaller pan")
        dismissKeyboard(app); app.buttons["Save change"].tap()
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
        app.buttons["Add a note"].tap()
        let note = app.descendants(matching: .any)["cooking-note"]
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        for _ in 0..<3 where !note.isHittable { app.swipeUp() }
        note.tap(); note.typeText("Try this again next week."); dismissKeyboard(app)
        XCTAssertEqual(note.value as? String, "Try this again next week.")
        for _ in 0..<4 where !app.buttons["Save memory"].isHittable { app.swipeUp() }
        app.buttons["Save memory"].tap()
        for _ in 0..<3 where !app.buttons["Back to my cookbook"].isHittable { app.swipeUp() }
        app.buttons["Back to my cookbook"].tap(); app.buttons["tab-Album"].tap()
        XCTAssertTrue(app.staticTexts["Made by you."].waitForExistence(timeout: 5)); capture("12 Cooking album", app)
        XCTAssertTrue(app.buttons.containing(.staticText,identifier:"Creamy garlic pasta").firstMatch.exists)
    }
}
