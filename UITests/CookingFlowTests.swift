import XCTest

final class CookingFlowTests: XCTestCase {
    func testReadinessTimerPauseAndRelaunch() {
        let app = XCUIApplication()
        app.launchArguments = ["--auth-emulator"]
        app.launch()
        continueAfterFailure = false
        if app.buttons["Get started"].waitForExistence(timeout: 3) {
            app.buttons["Get started"].tap()
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
            for page in ["Dietary preferences", "Allergy preferences", "Taste preferences", "Ingredient dislikes"] {
                if page == "Allergy preferences" {
                    app.buttons["allergy-answer"].tap()
                    app.buttons["I have allergies"].tap()
                    expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["Shellfish"])
                    waitForExpectations(timeout: 5)
                    XCTAssertTrue(app.buttons["Shellfish"].isHittable)
                    XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.buttons["Shellfish"].frame))
                }
                if page == "Ingredient dislikes" {
                    XCTAssertTrue(app.buttons["Choose ingredients"].isHittable)
                    XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.buttons["Choose ingredients"].frame))
                }
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = page
                screenshot.lifetime = .keepAlways
                add(screenshot)
                if page == "Allergy preferences" {
                    app.buttons["allergy-answer"].tap()
                    app.buttons["None"].tap()
                }
                app.buttons["Continue"].tap()
            }
            app.buttons["Let's cook together"].tap()
        }
        let home = XCTAttachment(screenshot: app.screenshot())
        home.name = "Recipe library"
        home.lifetime = .keepAlways
        add(home)

        // A prior failed run may have preserved a session, just as a real relaunch should.
        if app.buttons["End cooking session"].exists {
            tap(app.buttons["End cooking session"], in: app, direction: .down)
            app.buttons["End session and cancel its reminders"].tap()
        }
        // Editing preferences exercises the catalog picker even on a simulator with a saved profile.
        tap(app.buttons["Cooking preferences"], in: app, direction: .down)
        XCTAssertTrue(app.staticTexts["YOUR PREFERENCES  ·  1 / 6"].waitForExistence(timeout: 5))
        app.buttons["Get started"].tap()
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
        for _ in 0..<3 { app.buttons["Continue"].tap() }
        tap(app.buttons["Choose ingredients"], in: app)
        let ingredientSearch = app.textFields["Search all ingredients"]
        XCTAssertTrue(ingredientSearch.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Beet"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Beet"].isHittable)
        let ingredientGrid = XCTAttachment(screenshot: app.screenshot())
        ingredientGrid.name = "Ingredient library without scrolling"; ingredientGrid.lifetime = .keepAlways; add(ingredientGrid)
        ingredientSearch.tap()
        ingredientSearch.typeText("garlic\n")
        let garlic = app.buttons["Garlic"]
        XCTAssertTrue(garlic.waitForExistence(timeout: 10))
        if garlic.value as? String != "Avoid" { garlic.tap() }
        XCTAssertEqual(garlic.value as? String, "Avoid")
        let picker = XCTAttachment(screenshot: app.screenshot())
        picker.name = "Reusable ingredient picker"; picker.lifetime = .keepAlways; add(picker)
        app.buttons["Done"].tap()
        app.buttons["Continue"].tap()
        app.buttons["Let's cook together"].tap()
        tap(app.buttons["View Sunday Spaghetti"], in: app)
        tap(app.buttons["Start prep flow"], in: app)
        let preferences = XCTAttachment(screenshot: app.screenshot())
        preferences.name = "Ingredient preferences"; preferences.lifetime = .keepAlways; add(preferences)
        tap(app.buttons["Review ingredients"], in: app)
        tap(app.buttons["Review details"], in: app)
        tap(app.buttons["Use Rice spaghetti"], in: app, direction: .down)
        XCTAssertEqual(app.buttons["Rice spaghetti"].value as? String, "Not checked")
        tap(app.buttons["Use Dried spaghetti"], in: app)
        XCTAssertEqual(app.buttons["Dried spaghetti"].value as? String, "Not checked")
        XCTAssertTrue(app.staticTexts["You prefer to avoid garlic."].exists)
        tap(app.buttons["End cooking session"], in: app, direction: .down)
        app.buttons["End session and cancel its reminders"].tap()
        tap(app.buttons["View The Classic Margarita"], in: app)
        tap(app.buttons["Start prep flow"], in: app)
        tap(app.buttons["Review ingredients"], in: app)
        XCTAssertFalse(app.buttons["check-continue"].isEnabled)
        tap(app.buttons["I have the basics"], in: app)
        XCTAssertFalse(app.buttons["check-continue"].isEnabled)
        tap(app.buttons["Clear"], in: app)
        XCTAssertTrue(app.staticTexts["0 of 4 ingredients selected"].exists)
        tap(app.buttons["I have the basics"], in: app)
        XCTAssertFalse(app.buttons["I have these tools"].exists)
        tap(app.buttons["I've checked product labels"], in: app)
        XCTAssertTrue(app.buttons["check-continue"].isEnabled)
        app.swipeDown()
        let check = XCTAttachment(screenshot: app.screenshot())
        check.name = "Manual ingredient checklist"; check.lifetime = .keepAlways; add(check)
        tap(app.buttons["check-continue"], in: app)
        tap(app.buttons["Increase Fresh lime juice"], in: app)
        XCTAssertTrue(app.staticTexts["17.5 mL"].waitForExistence(timeout: 2))
        let amounts = XCTAttachment(screenshot: app.screenshot())
        amounts.name = "Adjust amounts"; amounts.lifetime = .keepAlways; add(amounts)
        tap(app.buttons["amounts-continue"], in: app)
        XCTAssertTrue(app.staticTexts["Ready to cook"].exists)
        let ready = XCTAttachment(screenshot: app.screenshot())
        ready.name = "Ready summary"; ready.lifetime = .keepAlways; add(ready)
        tap(app.buttons["Cook without voice"], in: app)
        tap(app.buttons["I've started"].firstMatch, in: app, direction: .down)
        tap(app.buttons["complete-measure"], in: app)
        XCTAssertEqual(app.alerts.count, 0)
        tap(app.buttons["I've started"].firstMatch, in: app, direction: .down)

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.alerts.buttons["Allow"].waitForExistence(timeout: 3) { springboard.alerts.buttons["Allow"].tap() }
        XCTAssertTrue(app.staticTexts["Shake with ice"].exists)
        tap(app.buttons["Pause guidance"], in: app)
        XCTAssertTrue(app.buttons["Resume cooking"].exists)
        app.terminate()
        app.launch()
        XCTAssertTrue(app.buttons["Resume cooking"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Shake with ice"].exists)
        XCTAssertFalse(app.staticTexts["You made it."].exists)
        let cooking = XCTAttachment(screenshot: app.screenshot())
        cooking.name = "Paused timer restored after relaunch"
        cooking.lifetime = .keepAlways
        add(cooking)
        tap(app.buttons["Resume cooking"], in: app, direction: .down)
        tap(app.buttons["Type a cooking command"], in: app)
        let command = app.textFields["e.g. repeat or where are we"]
        tap(command, in: app)
        command.typeText("done\n")
        XCTAssertEqual(app.alerts.count, 0)
        XCTAssertTrue(app.staticTexts["Pour and enjoy"].exists)
        XCTAssertFalse(app.buttons["complete-shake"].exists)
        tap(app.buttons["Let's check"], in: app)
        tap(app.buttons["complete-strain"], in: app)
        XCTAssertTrue(app.staticTexts["You made it."].exists)
        tap(app.buttons["Take photo"], in: app, direction: .down)
        XCTAssertTrue(app.staticTexts["Made by you."].waitForExistence(timeout: 3))
        tap(app.buttons["Choose a photo"], in: app)
        let photo = app.images.matching(NSPredicate(format: "label BEGINSWITH 'Photo,'")).firstMatch
        XCTAssertTrue(photo.waitForExistence(timeout: 5), app.debugDescription)
        photo.tap()
        XCTAssertTrue(app.buttons["Save dish photo"].waitForExistence(timeout: 5), app.debugDescription)
        app.buttons["Save dish photo"].tap()
        tap(app.buttons["Save this cooking session"], in: app)
        tap(app.buttons["Profile"], in: app)
        XCTAssertTrue(app.staticTexts["Completed recipes"].waitForExistence(timeout: 5), app.debugDescription)
        let dishShot = XCTAttachment(screenshot: app.screenshot()); dishShot.name = "Completed recipe with private photo"; dishShot.lifetime = .keepAlways; add(dishShot)
        tap(app.buttons["Replace photo"].firstMatch, in: app)
        XCTAssertTrue(app.staticTexts["Made by you."].waitForExistence(timeout: 3))
        app.buttons["Close"].tap()
        tap(app.buttons["account-button"], in: app, direction: .down)
        app.buttons["Continue with email"].tap()
        app.buttons["Create account"].firstMatch.tap()
        app.textFields["Email address"].tap()
        app.textFields["Email address"].typeText("dish-\(UUID().uuidString.lowercased())@example.com")
        app.secureTextFields.firstMatch.tap()
        app.secureTextFields.firstMatch.typeText("CookingTest123!")
        app.buttons["email-submit"].tap()
        XCTAssertTrue(app.buttons["Sign out"].waitForExistence(timeout: 20), app.debugDescription)
        app.buttons["Close"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Waiting to sync"].firstMatch)
        waitForExpectations(timeout: 25)
        XCTAssertFalse(app.buttons["Retry sync"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["Replace photo"].firstMatch.exists, app.debugDescription)
        tap(app.buttons["account-button"], in: app, direction: .down)
        app.buttons["Delete account"].tap()
        app.alerts.buttons["Continue"].tap()
        app.buttons["Continue with email"].tap()
        app.secureTextFields.firstMatch.tap()
        app.secureTextFields.firstMatch.typeText("CookingTest123!")
        app.buttons["Verify and delete account"].tap()
        XCTAssertTrue(app.buttons["Get started"].waitForExistence(timeout: 20), app.debugDescription)
    }

    private enum Direction { case up, down }
    private func tap(_ element: XCUIElement, in app: XCUIApplication, direction: Direction = .up, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<9 {
            if element.exists && element.isHittable {
                let inScroll = app.scrollViews.firstMatch.descendants(matching: element.elementType)
                    .matching(NSPredicate(format: "label == %@", element.label)).firstMatch.exists
                let footer = app.otherElements["preparation-footer"]
                let bottom = footer.exists ? footer.frame.minY : app.frame.maxY - 34
                let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : app.frame.minY
                if !inScroll || (element.frame.midY >= top + 12 && element.frame.midY <= bottom - 12) { element.tap(); return }
            }
            let aboveViewport = element.exists && element.frame.midY < app.frame.midY
            if aboveViewport || (!element.exists && direction == .down) { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("Control was not reachable: \(element)\n\(app.debugDescription)", file: file, line: line)
    }
}
