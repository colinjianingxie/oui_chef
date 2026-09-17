import XCTest

final class VoiceFlowTests: XCTestCase {
    func testPermissionFailureStaysVisibleAndCloses() throws {
        #if !targetEnvironment(simulator)
        throw XCTSkip("Permission-denied check runs on an isolated simulator.")
        #endif
        let app = openVoice()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let deny = springboard.alerts.buttons.matching(NSPredicate(format: "label BEGINSWITH[c] 'Don'")).firstMatch
        if deny.waitForExistence(timeout: 2) { deny.tap() }
        XCTAssertTrue(app.staticTexts["Allow microphone access in Settings to use voice."].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Open Settings"].exists)
        XCTAssertEqual(app.descendants(matching: .any)["microphone-state"].label, "Microphone off")
        capture(app, name: "Voice permission error stays visible")
        app.buttons["Close voice"].tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["Close voice"])
        waitForExpectations(timeout: 5)
        XCTAssertTrue(app.buttons["Start voice commands"].exists || app.buttons["Start voice guidance"].exists)
        XCTAssertFalse(app.buttons["Close voice"].exists)
        if app.buttons["End cooking session"].exists {
            app.buttons["End cooking session"].tap()
            app.buttons["End session and cancel its reminders"].tap()
        }
        XCTAssertTrue(app.buttons["Start voice commands"].waitForExistence(timeout: 5))
        capture(app, name: "Bottom navigation after closing voice")
    }

    func testLiveVoiceOnDevice() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["OUI_CHEF_LIVE_VOICE_TEST"] == "1", "Opt-in paid device voice check.")
        let app = openVoice()
        let indicator = app.descendants(matching: .any)["microphone-state"]
        let connected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == 'Microphone on'"), object: indicator)
        let result = XCTWaiter.wait(for: [connected], timeout: 25)
        capture(app, name: "Device voice connection")
        if app.buttons["Development tester ID"].exists {
            app.buttons["Development tester ID"].tap()
            let id = app.staticTexts["development-tester-id"].label
            let attachment = XCTAttachment(string: id)
            attachment.name = "Voice tester ID"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let status = app.staticTexts["voice-status"].label
        app.buttons["Close voice"].tap()
        XCTAssertEqual(result, .completed, status)
    }

    private func openVoice() -> XCUIApplication {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launch()
        if app.buttons["Get started"].waitForExistence(timeout: 3) {
            app.buttons["Get started"].tap()
            for _ in 0..<4 { app.buttons["Continue"].tap() }
            app.buttons["Let's cook together"].tap()
        }
        let button = app.buttons["Start voice commands"].exists ? app.buttons["Start voice commands"] : app.buttons["Start voice guidance"]
        for _ in 0..<8 {
            if button.isHittable { break }
            app.swipeUp()
        }
        button.tap()
        XCTAssertTrue(app.buttons["Close voice"].waitForExistence(timeout: 5))
        return app
    }

    private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
