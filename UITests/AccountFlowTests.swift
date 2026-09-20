import XCTest

final class AccountFlowTests: XCTestCase {
    func testEmailAccountLifecycleAndGuestRecipes() {
        let app = XCUIApplication()
        app.launchArguments = ["--auth-emulator"]
        app.launch()
        continueAfterFailure = false
        let welcome = app.buttons["Sign in or create an account"]
        if !welcome.waitForExistence(timeout: 5) {
            app.buttons["Profile"].tap()
            app.buttons["account-button"].tap()
        } else { welcome.tap() }
        XCTAssertTrue(app.buttons["Continue with email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Continue with Google"].exists)
        app.buttons["Continue with email"].tap()
        app.buttons["Create account"].firstMatch.tap()
        let email = "cook-\(UUID().uuidString.lowercased())@example.com"
        app.textFields["Email address"].tap()
        app.textFields["Email address"].typeText(email)
        app.secureTextFields.firstMatch.tap()
        for character in "CookingTest123!" { app.secureTextFields.firstMatch.typeText(String(character)) }
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(app.staticTexts[email].exists)
        app.buttons["Sign out"].tap()
        XCTAssertTrue(app.buttons["Continue with email"].waitForExistence(timeout: 10))
        app.buttons["Continue with email"].tap()
        app.textFields["Email address"].tap()
        app.textFields["Email address"].typeText(email)
        app.secureTextFields.firstMatch.tap()
        for character in "CookingTest123!" { app.secureTextFields.firstMatch.typeText(String(character)) }
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.buttons["Delete account"].waitForExistence(timeout: 15))
        app.buttons["Delete account"].tap()
        app.alerts.buttons["Continue"].tap()
        app.buttons["Continue with email"].tap()
        app.secureTextFields.firstMatch.tap()
        for character in "CookingTest123!" { app.secureTextFields.firstMatch.typeText(String(character)) }
        app.buttons["Verify and delete account"].tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 15), app.debugDescription)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "Optional account sign-in"; shot.lifetime = .keepAlways; add(shot)
        if app.buttons["Close"].exists { app.buttons["Close"].tap() }
        if app.buttons["Get started"].exists {
            app.buttons["Get started"].tap()
            for _ in 0..<4 { app.buttons["Continue"].tap() }
            XCTAssertTrue(app.buttons["Measuring jigger"].isHittable)
            XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.buttons["Measuring jigger"].frame))
            let equipment = XCTAttachment(screenshot: app.screenshot())
            equipment.name = "Kitchen equipment without scrolling"; equipment.lifetime = .keepAlways; add(equipment)
            app.buttons["Continue"].tap()
            app.buttons["Let's cook together"].tap()
        }
        XCTAssertTrue(app.staticTexts["Recipe sets"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Chef Margarita · Free"].firstMatch.exists)
    }
}
