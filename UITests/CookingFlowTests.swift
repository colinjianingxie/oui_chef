import XCTest

final class CookingFlowTests: XCTestCase {
    func testChecklistSurvivesLeavingAndResuming() {
        let app = preview(); openPasta(app); app.buttons["start-recipe"].tap()
        let all = app.buttons["select-all-ingredients"]; XCTAssertTrue(all.waitForExistence(timeout: 5)); capture("10 Preparation", app); all.tap()
        XCTAssertEqual(app.buttons["ingredient-check-pasta"].value as? String, "Selected")
        app.buttons["ingredient-check-garlic"].tap(); app.buttons["Save and leave cooking"].tap()
        let resume = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cook-'")).firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 5)); capture("Home resume preparation", app); resume.tap()
        XCTAssertTrue(all.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["ingredient-check-pasta"].value as? String, "Selected")
        XCTAssertEqual(app.buttons["ingredient-check-garlic"].value as? String, "Not selected")
    }
    func testTimersProgressAndOptionalMemory() {
        let app = preview(); beginPasta(app); capture("11 Active cooking", app)
        XCTAssertFalse(app.buttons["tab-Home"].isHittable)
        app.buttons["complete-step"].tap()
        let start = app.buttons["start-step-timer"]; reveal(start, in: app); start.tap()
        let pause = app.buttons["Pause Sauté the garlic"]; XCTAssertTrue(pause.waitForExistence(timeout: 5)); pause.tap()
        XCTAssertTrue(app.buttons["Resume Sauté the garlic"].exists); capture("Cooking with a timer", app)
        app.buttons["Save and leave cooking"].tap()
        let resume = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'cook-'")).firstMatch; XCTAssertTrue(resume.waitForExistence(timeout: 5)); resume.tap()
        XCTAssertTrue(app.buttons["Resume Sauté the garlic"].waitForExistence(timeout: 5))
        app.buttons["Previous step"].tap(); XCTAssertEqual(app.staticTexts["current-step-title"].label, "Get the pasta going")
        app.buttons["complete-step"].tap(); app.buttons["complete-step"].tap(); app.buttons["complete-step"].tap()
        XCTAssertEqual(app.buttons["complete-step"].label, "Finish cooking"); app.buttons["complete-step"].tap()
        XCTAssertTrue(app.staticTexts["You did it."].waitForExistence(timeout: 5)); capture("14 Completion", app)
        let memory = app.buttons["Add a photo, note, or rating"]; reveal(memory, in: app); memory.tap()
        let note = app.textFields["cooking-note"]; reveal(note, in: app); note.tap(); note.typeText("Try this again next week."); dismissKeyboard(app)
        reveal(app.buttons["Rate 4 stars"], in: app); app.buttons["Rate 4 stars"].tap()
        reveal(app.buttons["Save memory"], in: app); app.buttons["Save memory"].tap()
        XCTAssertTrue(app.staticTexts["memory-saved"].exists)
        reveal(app.buttons["Back to my cookbook"], in: app); app.buttons["Back to my cookbook"].tap(); app.buttons["tab-Album"].tap()
        XCTAssertTrue(app.staticTexts["Try this again next week."].waitForExistence(timeout: 5)); capture("15 Cooking album", app)
    }
    func testCompletionSavesWithoutPhotoOrRating() {
        let app = preview(); beginPasta(app)
        for _ in 0..<4 { app.buttons["complete-step"].tap() }
        XCTAssertTrue(app.staticTexts["You did it."].waitForExistence(timeout: 5))
        reveal(app.buttons["Back to my cookbook"], in: app); app.buttons["Back to my cookbook"].tap(); app.buttons["tab-Album"].tap()
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Creamy garlic pasta").firstMatch.waitForExistence(timeout: 5))
        app.buttons.containing(.staticText, identifier: "Creamy garlic pasta").firstMatch.tap()
        let again = app.buttons["Cook this again →"]; reveal(again, in: app); again.tap()
        XCTAssertTrue(app.buttons["start-recipe"].waitForExistence(timeout: 5)); app.buttons["start-recipe"].tap()
        XCTAssertTrue(app.buttons["begin-cooking"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons["ingredient-check-pasta"].value as? String, "Not selected")
    }
}
