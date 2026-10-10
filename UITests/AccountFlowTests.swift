import XCTest

final class AccountFlowTests: XCTestCase {
    func testWelcomeAndEmailEntry() {
        let app = preview("--companion-welcome")
        let email = app.buttons["Continue with email"]
        XCTAssertTrue(email.waitForExistence(timeout: 10)); capture("01 Welcome", app); reveal(email, in: app); email.tap()
        XCTAssertTrue(app.textFields["Email address"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["email-submit"].isEnabled)
        app.buttons["Create account"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Use at least 8 characters."].exists)
        capture("Email registration", app)
    }
}
