import XCTest

final class VoiceFlowTests: XCTestCase {
    func testInlineListeningPreservesStepAndExplicitMute() {
        let app = preview(); beginPasta(app)
        app.buttons["Start listening"].tap()
        XCTAssertTrue(app.staticTexts["Listening…"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["current-step-instruction"].isHittable)
        XCTAssertTrue(app.buttons["complete-step"].isHittable)
        XCTAssertFalse(app.staticTexts["· Microphone on"].exists, "Preview never captures real microphone audio.")
        capture("12 Inline voice listening", app)
        app.buttons["Stop listening"].tap(); XCTAssertTrue(app.staticTexts["Microphone off"].exists)
        app.buttons["complete-step"].tap(); XCTAssertEqual(app.staticTexts["current-step-title"].label, "Sauté the garlic")
    }
    func testChefReplyStaysInsideCooking() {
        let app = preview("--companion-answer-preview"); beginPasta(app)
        let question = app.buttons["Ask a question or show an ingredient"]; reveal(question, in: app); question.tap()
        let input = app.textFields["recipe-question"]; reveal(input, in: app); input.tap(); input.typeText("Which pan should I use?"); dismissKeyboard(app)
        let send = app.buttons["ask-chef"]; reveal(send, in: app); send.tap()
        XCTAssertTrue(app.buttons["compact-chef-answer"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["complete-step"].isHittable)
        for _ in 0..<3 { app.swipeDown() }; capture("13 Contextual chef reply", app)
        XCTAssertEqual(app.staticTexts["current-step-title"].label, "Get the pasta going")
        app.buttons["compact-chef-answer"].tap(); XCTAssertTrue(app.buttons["Back to cooking"].waitForExistence(timeout: 5)); app.buttons["Back to cooking"].tap()
        XCTAssertTrue(app.buttons["complete-step"].exists)
    }
    func testLargeTextKeepsCookingControlsReachable() {
        let app = preview("-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL")
        beginPasta(app)
        XCTAssertTrue(app.buttons["complete-step"].isHittable)
        XCTAssertTrue(app.buttons["Start listening"].isHittable)
        let next = app.buttons["complete-step"]
        let label = next.staticTexts["Next"]
        XCTAssertTrue(label.exists)
        XCTAssertTrue(next.frame.contains(label.frame), "The Next label must stay inside its touch target.")
        capture("Cooking with accessibility text", app)
    }
    func testVoiceErrorKeepsManualCookingUsable() {
        let app = preview("--companion-voice-error"); beginPasta(app); app.buttons["Start listening"].tap()
        XCTAssertTrue(app.staticTexts["Voice unavailable"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["complete-step"].isEnabled); app.buttons["complete-step"].tap()
        XCTAssertEqual(app.staticTexts["current-step-title"].label, "Sauté the garlic")
        let retry = app.buttons["Try voice again"]; reveal(retry, in: app); capture("Voice manual fallback", app)
    }
}
