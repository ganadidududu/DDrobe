#if canImport(XCTest)
import XCTest

final class CoorditClosetDetailPhotoUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFitDetailExposesGarmentPhotoControlOnEveryClosetDetailRoute() throws {
        for route in ["closet-detail-top", "closet-detail-bottom", "closet-add-result"] {
            let app = launchApp(at: route)
            assertScreen(route, in: app)

            let photo = element("closet-detail-garment-photo", in: app)
            XCTAssertTrue(photo.waitForExistence(timeout: 5), "Missing detail photo control on \(route).")
            XCTAssertEqual(photo.value as? String, "empty")
            app.terminate()
        }
    }

    func testDetailPhotoScenarioUpdatesDisplayedItemAndPersistsAcrossReopen() throws {
        let app = launchApp(
            at: "closet-detail-bottom",
            scenario: "displayed-item-persistence"
        )
        assertScreen("closet-detail-bottom", in: app)

        let photo = element("closet-detail-garment-photo", in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        waitForTestState("denim-valid-b", in: app)
        XCTAssertEqual(photo.value as? String, "selected")
        XCTAssertEqual(testState(in: app), "denim-valid-b")
        app.buttons["FIT DETAIL"].tap()
        assertScreen("closet-overview", in: app)
        app.buttons["closet-category-bottom"].tap()
        app.buttons["Wide Denim"].tap()
        assertScreen("closet-detail-bottom", in: app)
        XCTAssertEqual(element("closet-detail-garment-photo", in: app).value as? String, "selected")
        XCTAssertEqual(testState(in: app), "denim-valid-b")
        let settled = expectation(description: "detail view finished rendering")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
        let photoCapture = XCTAttachment(screenshot: app.screenshot())
        photoCapture.name = "closet-detail-photo-clipping"
        photoCapture.lifetime = .keepAlways
        add(photoCapture)
    }

    func testDetailPhotoScenarioPreservesLatestValidImageAgainstCorruptAndStaleLoads() throws {
        let app = launchApp(
            at: "closet-detail-top",
            scenario: "corrupt-and-stale"
        )
        assertScreen("closet-detail-top", in: app)

        let photo = element("closet-detail-garment-photo", in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        waitForTestState("oxford-valid-a-delayed-pending", in: app)
        XCTAssertEqual(photo.value as? String, "selected")

        app.buttons["FIT DETAIL"].tap()
        assertScreen("closet-overview", in: app)
        app.buttons["Oxford Shirt"].tap()
        assertScreen("closet-detail-top", in: app)
        waitForTestState("oxford-valid-b", in: app)
        waitForTestRejection("oxford-stale-a-rejected", in: app)
        XCTAssertEqual(photo.value as? String, "selected")
        XCTAssertEqual(
            testState(in: app),
            "oxford-valid-b",
            "Delayed A must reach its stale-generation rejection after B without replacing B."
        )
    }

    func testDetailPhotoScenarioUpdatesDraftPreviewFallback() throws {
        let app = launchApp(
            at: "closet-add-result",
            scenario: "draft-preview-fallback"
        )
        assertScreen("closet-add-result", in: app)

        let photo = element("closet-detail-garment-photo", in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        waitForTestState("closet-draft-preview-valid-b", in: app)
        XCTAssertEqual(photo.value as? String, "selected")
        XCTAssertEqual(testState(in: app), "closet-draft-preview-valid-b")
    }

    func testDetailPhotoScenarioUpdatesRealLinkAddResultItem() throws {
        let app = launchApp(
            at: "closet-overview",
            scenario: "real-link-add-result-item"
        )

        app.buttons["closet-add-garment"].tap()
        assertScreen("closet-add-method", in: app)
        let linkMethod = app.buttons["closet-add-method-link"]
        XCTAssertTrue(linkMethod.waitForExistence(timeout: 5))
        linkMethod.tap()
        assertScreen("closet-add-link", in: app)

        let linkField = app.textFields["closet-product-link"]
        linkField.tap()
        linkField.typeText("https://coordit.test/verifier-item")
        app.swipeDown()

        let submit = app.buttons["closet-add-submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(element("closet-link-size-row-M", in: app).waitForExistence(timeout: 5))
        element("closet-link-size-row-M", in: app).tap()
        submit.tap()
        assertScreen("closet-add-loading", in: app)
        assertScreen("closet-add-result", in: app)
        XCTAssertTrue(element("리넨 셔츠", in: app).waitForExistence(timeout: 5))

        let photo = element("closet-detail-garment-photo", in: app)
        XCTAssertTrue(photo.waitForExistence(timeout: 5))
        waitForTestState(suffix: "-real-link-valid-b", in: app)
        XCTAssertEqual(photo.value as? String, "selected")
        XCTAssertTrue(testState(in: app)?.hasSuffix("-real-link-valid-b") == true)
    }

    private func launchApp(at route: String, scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-start-route",
            route,
        ]
        if let scenario {
            app.launchArguments += [
                "--coordit-test-detail-photo-scenario",
                scenario,
            ]
        }
        app.launch()
        return app
    }

    private func assertScreen(
        _ route: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            element("coordit-screen-\(route)", in: app).waitForExistence(timeout: 10),
            "Missing route: \(route)",
            file: file,
            line: line
        )
    }

    private func testState(in app: XCUIApplication) -> String? {
        element("closet-detail-photo-test-state", in: app).value as? String
    }

    private func waitForTestState(
        _ expectedState: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let state = element("closet-detail-photo-test-state", in: app)
        XCTAssertTrue(state.waitForExistence(timeout: 5), file: file, line: line)
        let predicate = NSPredicate(format: "value == %@", expectedState)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func waitForTestState(
        suffix: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let state = element("closet-detail-photo-test-state", in: app)
        XCTAssertTrue(state.waitForExistence(timeout: 5), file: file, line: line)
        let predicate = NSPredicate(format: "value ENDSWITH %@", suffix)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: state)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed, file: file, line: line)
    }

    private func waitForTestRejection(
        _ expectedRejection: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rejection = element("closet-detail-photo-test-rejection", in: app)
        XCTAssertTrue(rejection.waitForExistence(timeout: 5), file: file, line: line)
        let predicate = NSPredicate(format: "value == %@", expectedRejection)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: rejection)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15), .completed, file: file, line: line)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
#endif
