import XCTest

final class CookingFlowTests: XCTestCase {
    func testReadinessTimerPauseAndRelaunch() {
        let app = XCUIApplication()
        app.launch()
        continueAfterFailure = false
        if app.buttons["Get started"].waitForExistence(timeout: 3) {
            app.buttons["Get started"].tap()
            XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 5))
            for page in ["Dietary preferences", "Allergy preferences", "Taste preferences", "Equipment preferences"] {
                if page == "Allergy preferences" {
                    app.buttons["allergy-answer"].tap()
                    app.buttons["I have allergies"].tap()
                    expectation(for: NSPredicate(format: "isHittable == true"), evaluatedWith: app.buttons["Shellfish"])
                    waitForExpectations(timeout: 5)
                    XCTAssertTrue(app.buttons["Shellfish"].isHittable)
                    XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.buttons["Shellfish"].frame))
                }
                if page == "Equipment preferences" {
                    XCTAssertTrue(app.buttons["Cocktail shaker"].isHittable)
                    XCTAssertTrue(app.scrollViews.firstMatch.frame.contains(app.buttons["Cocktail shaker"].frame))
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
        tap(app.buttons["View The Classic Margarita"], in: app)
        tap(app.buttons["Check all ingredients"], in: app)
        XCTAssertFalse(app.buttons["check-continue"].isEnabled)
        tap(app.buttons["Select all I have"], in: app)
        XCTAssertFalse(app.buttons["check-continue"].isEnabled)
        tap(app.buttons["Clear"], in: app)
        XCTAssertEqual(app.buttons["Blanco tequila"].value as? String, "Not checked")
        tap(app.buttons["Select all I have"], in: app)
        app.swipeUp() // Bring equipment above the fixed Continue footer before tapping.
        tap(app.buttons["I have these tools"], in: app)
        XCTAssertEqual(app.buttons["I have these tools"].value as? String, "Checked")
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
        XCTAssertTrue(app.staticTexts["Ingredient check complete"].exists)
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
                if !inScroll || (element.frame.minY >= top && element.frame.maxY <= bottom) { element.tap(); return }
            }
            let aboveViewport = element.exists && element.frame.midY < app.frame.midY
            if aboveViewport || (!element.exists && direction == .down) { app.swipeDown() } else { app.swipeUp() }
        }
        XCTFail("Control was not reachable: \(element)\n\(app.debugDescription)", file: file, line: line)
    }
}
