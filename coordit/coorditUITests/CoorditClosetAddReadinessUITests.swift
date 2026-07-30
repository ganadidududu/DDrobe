#if canImport(XCTest)
import XCTest

final class CoorditClosetAddReadinessUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testPhotoInputSubmitEnablesWithNameAndInjectedSizeChart() throws {
        let app = launchApp(
            at: "closet-add-photo",
            additionalArguments: ["--coordit-test-valid-size-chart"]
        )
        assertScreen("closet-add-photo", in: app)

        let sizeChart = element("closet-size-chart-photo", in: app)
        XCTAssertTrue(sizeChart.waitForExistence(timeout: 5))
        XCTAssertEqual(sizeChart.value as? String, "selected")

        let submit = app.buttons["closet-add-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "A size chart without a garment name must remain disabled.")

        let name = app.textFields["closet-garment-name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        focusAndType("Ready Shirt", into: name, in: app)
        app.swipeDown()

        XCTAssertTrue(
            submit.isEnabled,
            "A nonempty name plus the injected valid size chart must enable photo submission without a garment photo."
        )
    }

    func testPhotoOCRCropsChartAndRequiresChoosingOnePreservedSizeLabel() throws {
        let app = launchApp(
            at: "closet-add-photo",
            additionalArguments: ["--coordit-test-ocr-crop-and-rows"]
        )
        assertScreen("closet-add-photo", in: app)

        let cropper = element("size-chart-cropper", in: app)
        XCTAssertTrue(cropper.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["사이즈표 부분만 맞춰주세요"].exists)
        cropper.swipeRight(velocity: .slow)
        cropper.swipeLeft(velocity: .slow)
        let cropAttachment = XCTAttachment(screenshot: app.screenshot())
        cropAttachment.name = "closet-ocr-crop-adjusted"
        cropAttachment.lifetime = .keepAlways
        add(cropAttachment)
        app.buttons["표 영역 사용"].tap()

        XCTAssertTrue(element("closet-ocr-size-row-W32", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("closet-ocr-size-row-FREE", in: app).exists)
        XCTAssertFalse(app.buttons["closet-add-submit"].isEnabled)

        element("closet-ocr-size-row-W32", in: app).tap()
        XCTAssertEqual(element("closet-selected-size-label", in: app).label, "W32")
        XCTAssertTrue(app.buttons["closet-add-submit"].isEnabled)
        element("closet-ocr-size-row-FREE", in: app).tap()
        XCTAssertEqual(element("closet-selected-size-label", in: app).label, "FREE")
        element("closet-ocr-size-row-W32", in: app).tap()
        XCTAssertEqual(element("closet-selected-size-label", in: app).label, "W32")
        for _ in 0..<2 { app.swipeUp() }
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "closet-ocr-size-row-selection"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testLinkExtractionFailureOffersPhotoOCRAndManualFallback() throws {
        let app = launchApp(
            at: "closet-add-link",
            additionalArguments: ["--coordit-test-link-extraction-failure"]
        )
        assertScreen("closet-add-link", in: app)
        app.buttons["closet-add-submit"].tap()

        XCTAssertTrue(element("closet-link-extraction-error", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["사진 OCR로 입력"].exists)
        XCTAssertTrue(app.buttons["직접 입력"].exists)
        app.buttons["사진 OCR로 입력"].tap()
        assertScreen("closet-add-photo", in: app)
    }

    func testLinkImportFailureDoesNotPretendTheClosetSaveSucceeded() throws {
        let app = launchApp(
            at: "closet-add-link",
            additionalArguments: ["--coordit-fitlab-fixture", "url-default"]
        )
        assertScreen("closet-add-link", in: app)

        XCTAssertFalse(app.textFields["closet-garment-name"].exists)
        attachScreenshot(named: "closet-link-before-import", from: app)
        typeText("https://shop.example/products/linen-shirt", into: "closet-product-link", in: app)
        app.swipeDown()
        app.buttons["closet-add-submit"].tap()

        XCTAssertTrue(element("closet-link-product-name", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("closet-link-product-name", in: app).label, "리넨 셔츠")
        XCTAssertTrue(element("closet-link-size-row-M", in: app).exists)
        XCTAssertTrue(element("closet-link-size-row-L", in: app).exists)
        XCTAssertFalse(app.buttons["closet-add-submit"].isEnabled)

        element("closet-link-size-row-L", in: app).tap()
        XCTAssertEqual(element("closet-selected-size-label", in: app).label, "L")
        XCTAssertTrue(app.buttons["closet-add-submit"].isEnabled)
        attachScreenshot(named: "closet-link-owned-size-selected", from: app)

        app.swipeUp()
        app.buttons["closet-add-submit"].tap()
        assertScreen("closet-add-loading", in: app)
        XCTAssertTrue(app.staticTexts["저장하지 못했어요"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("coordit-closet-save-retry", in: app).exists)
        XCTAssertFalse(app.staticTexts["새 의류의 핏 스코어 계산 중 . . ."].exists)
        XCTAssertFalse(element("coordit-screen-closet-add-result", in: app).exists)
    }

    func testEmptyBottomGarmentsUsePantsArtworkInsteadOfTopArtwork() throws {
        let app = launchApp(at: "closet-overview")
        assertScreen("closet-overview", in: app)
        app.buttons["closet-category-bottom"].tap()
        let pantsArtwork = element("closet-placeholder-bottom", in: app)
        XCTAssertTrue(pantsArtwork.waitForExistence(timeout: 5))
        XCTAssertEqual(pantsArtwork.label, "하의 사진 없음")
    }

    func testClosetBestFitMetricsUseEngineProfilesForUpperAndLowerReferences() throws {
        let app = launchApp(
            at: "closet-overview",
            additionalArguments: ["--coordit-test-reference-fit-profiles"]
        )
        assertScreen("closet-overview", in: app)

        XCTAssertEqual(element("closet-best-fit-shoulder_width", in: app).label, "어깨, 46.25 cm")
        XCTAssertEqual(element("closet-best-fit-chest_width", in: app).label, "가슴단면, 54 cm")
        XCTAssertEqual(element("closet-best-fit-total_length", in: app).label, "총장, 70.5 cm")
        XCTAssertEqual(element("closet-best-fit-sleeve_length", in: app).label, "소매, 62 cm")

        app.buttons["closet-category-bottom"].tap()

        XCTAssertEqual(element("closet-best-fit-waist_width", in: app).label, "허리단면, 39 cm")
        XCTAssertEqual(element("closet-best-fit-hip_width", in: app).label, "엉덩이단면, 51.25 cm")
        XCTAssertEqual(element("closet-best-fit-rise", in: app).label, "밑위, 29.5 cm")
        XCTAssertEqual(element("closet-best-fit-outseam", in: app).label, "총장, 102 cm")
    }

    func testManualInputRequiresNameAndAllFourMeasurementsWithoutPhoto() throws {
        let app = launchApp(at: "closet-add-manual")
        assertScreen("closet-add-manual", in: app)

        let submit = app.buttons["closet-add-submit"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(submit.isEnabled, "An empty manual form must remain disabled.")

        typeText("Ready Pants", into: "closet-garment-name", in: app)
        dismissKeyboard(in: app)
        XCTAssertFalse(submit.isEnabled, "A garment name without measurements must remain disabled.")

        for index in 0..<4 {
            let field = app.textFields["closet-manual-measurement-\(index)"]
            for _ in 0..<3 where !field.exists {
                app.swipeUp()
            }
            XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing measurement field \(index).")
            for _ in 0..<3 where !field.isHittable {
                if field.frame.midY < app.frame.midY {
                    app.swipeDown()
                } else {
                    app.swipeUp()
                }
            }
            focusAndType("\(index + 1)", into: field, in: app)
            dismissKeyboard(in: app)

            let completedCount = index + 1
            XCTAssertEqual(
                submit.isEnabled,
                completedCount == 4,
                "A name plus \(completedCount) measurements has the wrong readiness state."
            )
        }
    }

    private func launchApp(
        at route: String,
        additionalArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-start-route",
            route,
        ] + additionalArguments
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
            element("coordit-screen-\(route)", in: app).waitForExistence(timeout: 5),
            "Missing route: \(route)",
            file: file,
            line: line
        )
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func typeText(_ text: String, into identifier: String, in app: XCUIApplication) {
        let field = element(identifier, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing field: \(identifier)")
        XCTAssertTrue(field.isHittable, "Field is not hittable: \(identifier)")
        focusAndType(text, into: field, in: app)
    }

    private func focusAndType(_ text: String, into field: XCUIElement, in app: XCUIApplication) {
        if field.isHittable {
            field.tap()
        } else {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        if !app.keyboards.firstMatch.waitForExistence(timeout: 2) {
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(
            app.keyboards.firstMatch.waitForExistence(timeout: 5),
            "The field must gain keyboard focus before typing."
        )
        field.typeText(text)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        let done = app.buttons["closet-keyboard-done"]
        if done.waitForExistence(timeout: 1) {
            done.tap()
        } else {
            let returnKey = app.keyboards.buttons["return"].firstMatch
            if returnKey.exists {
                returnKey.tap()
            } else {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15)).tap()
            }
        }
        let keyboardDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: app.keyboards.firstMatch
        )
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardDismissed], timeout: 2), .completed)
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
#endif
