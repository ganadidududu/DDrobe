#if canImport(XCTest)
import XCTest

final class CoorditFeatureFlowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreshInstallSplashPresentsSocialAuthenticationSheet() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: ["--coordit-welcome-state", "fresh"]
        )
        assertScreen("splash", in: app)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "fresh-install-welcome"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let signupEntry = app.buttons["splash-signup-entry"]
        XCTAssertTrue(signupEntry.waitForExistence(timeout: 5), "Missing splash signup entry")
        XCTAssertEqual(signupEntry.label, "로그인/회원가입")
        XCTAssertGreaterThanOrEqual(signupEntry.frame.height, 44)
        XCTAssertFalse(app.buttons["splash-guest-entry"].exists)
        XCTAssertFalse(element("coordit-splash-tap-hint", in: app).exists)
        signupEntry.tap()

        XCTAssertTrue(element("coordit-splash-auth-sheet", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["splash-auth-google"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["splash-auth-apple"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["splash-auth-guest"].waitForExistence(timeout: 3))
        XCTAssertFalse(element("coordit-screen-mypage-account", in: app).exists)
    }

    func testFreshInstallCanEnterWithoutSocialLogin() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: [
                "--coordit-welcome-state", "fresh",
                "--coordit-test-guest-bootstrap",
                "--coordit-devicecheck-fixture",
            ]
        )

        let signupEntry = app.buttons["splash-signup-entry"]
        XCTAssertTrue(signupEntry.waitForExistence(timeout: 5))
        signupEntry.tap()

        let guestEntry = app.buttons["splash-auth-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 5))
        guestEntry.tap()

        assertScreen("main04", in: app)
    }

    func testGuestBootstrapFailureStaysRetryableOnSplash() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: [
                "--coordit-welcome-state", "fresh",
                "--coordit-test-guest-bootstrap-failure",
            ]
        )

        let signupEntry = app.buttons["splash-signup-entry"]
        XCTAssertTrue(signupEntry.waitForExistence(timeout: 5))
        signupEntry.tap()

        let guestEntry = app.buttons["splash-auth-guest"]
        XCTAssertTrue(guestEntry.waitForExistence(timeout: 5))
        guestEntry.tap()

        XCTAssertTrue(element("splash-auth-error", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(guestEntry.isEnabled)
        XCTAssertTrue(element("coordit-splash-auth-sheet", in: app).exists)
    }

    func testAppleLoginClosesAuthenticationSheetWhenAccountHydrationFails() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: [
                "--coordit-welcome-state", "fresh",
                "--coordit-test-apple-auth-success-hydration-failure",
            ]
        )

        let signupEntry = app.buttons["splash-signup-entry"]
        XCTAssertTrue(signupEntry.waitForExistence(timeout: 5))
        signupEntry.tap()

        let authenticationSheet = element("coordit-splash-auth-sheet", in: app)
        waitForDisappearance(authenticationSheet)
        XCTAssertFalse(
            authenticationSheet.exists,
            "A valid Apple session must leave the login sheet even when profile hydration fails."
        )
        assertScreen("main04", in: app)
    }

    func testReturningAuthenticatedSplashRestoresTapHint() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: [
                "--coordit-welcome-state", "returning",
                "--coordit-ui-testing-authenticated",
            ]
        )

        assertScreen("splash", in: app)
        XCTAssertTrue(element("coordit-splash-tap-hint", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["splash-signup-entry"].exists)
        element("coordit-screen-splash", in: app).tap()
        assertScreen("main04", in: app)
    }

    func testSplashLogoIsHorizontallyCentered() throws {
        let app = launchApp(at: "splash")
        assertScreen("splash", in: app)

        let screenshot = app.screenshot().image
        let logoCenter = try whiteLogoCenter(in: screenshot)
        let screenCenter = CGFloat(screenshot.cgImage!.width) / 2

        XCTAssertEqual(logoCenter, screenCenter, accuracy: 6)
    }

    func testMyPageAccountShowsGoogleAndAppleLogin() throws {
        let app = launchApp(at: "mypage-account")
        assertScreen("mypage-account", in: app)

        XCTAssertTrue(app.buttons["mypage-backend-apple-login"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["mypage-backend-google-login"].waitForExistence(timeout: 5))
    }

    func testFitLabInputSourcesAndHistoryFlow() throws {
        var app = launchApp(at: "fitlab-input")
        assertScreen("fitlab-input", in: app)
        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        app.terminate()

        let historyNamespace = "feature-flow-\(UUID().uuidString)"
        app = launchApp(
            at: "fitlab-result-bottom",
            fixture: "history-persistence",
            extraArguments: [
                "--coordit-fitlab-history-namespace", historyNamespace,
                "--coordit-fitlab-history-reset",
            ]
        )
        assertScreen("fitlab-result-bottom", in: app)
        let addToHistory = app.buttons["히스토리에 추가"]
        XCTAssertTrue(addToHistory.waitForExistence(timeout: 5))
        addToHistory.tap()
        assertScreen("fitlab-input", in: app)
        XCTAssertEqual(
            element("fitlab-draft-isolation-probe", in: app).label,
            "source=manual|category=tshirt|product=|url=nil"
        )
        let historyCard = element("fitlab-history-card-analysis-fixture-lower", in: app)
        XCTAssertTrue(historyCard.waitForExistence(timeout: 5))
        let savedReturnCapture = XCTAttachment(screenshot: app.screenshot())
        savedReturnCapture.name = "fitlab-save-returned-to-input"
        savedReturnCapture.lifetime = .keepAlways
        add(savedReturnCapture)
        historyCard.tap()
        assertScreen("fitlab-history-detail", in: app)
        XCTAssertEqual(element("fitlab-history-detail-analysis", in: app).label, "analysis-fixture-lower")
    }

    func testPrimaryNavigationKeepsSharedBackgroundMounted() throws {
        let app = launchApp(at: "main04")
        let sharedBackground = element("coordit-shared-app-background", in: app)

        assertScreen("main04", in: app)
        XCTAssertTrue(sharedBackground.waitForExistence(timeout: 5))

        app.buttons["FIT LAB"].tap()

        assertScreen("fitlab-input", in: app)
        XCTAssertTrue(sharedBackground.exists)
    }

    func testFitLabReferenceRowsDoNotShowPreferenceCopy() throws {
        let app = launchApp(at: "fitlab-input", fixture: "submission-success")
        let reference = element("fitlab-reference-reference-fixture-hoodie", in: app)

        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        XCTAssertFalse(reference.label.contains("선호도"))
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "선호도")).firstMatch.exists)
    }

    func testFitAnalysisNoticesSwipeAwayAndCompletionReturns() throws {
        let app = launchApp(
            at: "main04",
            extraArguments: ["--coordit-test-analysis-running-then-completed"]
        )
        let runningNotice = element("global-fit-analysis-running", in: app)

        XCTAssertTrue(runningNotice.waitForExistence(timeout: 5))
        runningNotice.swipeUp()
        waitForDisappearance(runningNotice)

        let completedNotice = element("global-fit-analysis-completed", in: app)
        XCTAssertTrue(completedNotice.waitForExistence(timeout: 8))
        completedNotice.swipeUp()
        waitForDisappearance(completedNotice)
    }

    func testHomeOpensFitLabLoadingWhileReportIsStillGenerating() throws {
        let app = launchApp(
            at: "main04",
            extraArguments: ["--coordit-test-analysis-running"]
        )

        app.buttons["새로운 옷 찾기"].tap()

        assertScreen("fitlab-loading", in: app)
        XCTAssertTrue(element("global-fit-analysis-running", in: app).exists)
        XCTAssertTrue(app.staticTexts["핏 리포트를 만들고 있어요"].exists)
        XCTAssertFalse(app.alerts["핏 리포트를 만들고 있어요"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "fitlab-running-fullscreen"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testEmptyClosetFixtureHasNoStarterGarments() throws {
        let app = launchApp(
            at: "closet-overview",
            extraArguments: ["--coordit-empty-closet"]
        )

        assertScreen("closet-overview", in: app)
        XCTAssertFalse(app.buttons["Oxford Shirt"].exists)
        XCTAssertFalse(app.buttons["Relaxed Knit"].exists)
        app.buttons["closet-category-bottom"].tap()
        XCTAssertFalse(app.buttons["Wide Denim"].exists)
        XCTAssertFalse(app.buttons["Black Slacks"].exists)
        XCTAssertTrue(app.buttons["closet-add-garment"].isHittable)
    }

    func testFitLabInputMethodsUseTheSharedTitleBackButton() throws {
        let app = launchApp(at: "fitlab-input")
        assertScreen("fitlab-input", in: app)

        for (method, captureName) in [
            ("직접 입력하기", "fitlab-manual-shared-back"),
            ("사진으로 첨부하기", "fitlab-ocr-shared-back"),
            ("링크로 불러오기", "fitlab-url-shared-back"),
        ] {
            let methodButton = app.buttons[method]
            XCTAssertTrue(methodButton.waitForExistence(timeout: 5))
            methodButton.tap()

            XCTAssertFalse(app.buttons["입력 방법 다시 선택"].exists)
            let titleBack = app.buttons["FIT LAB 뒤로가기"]
            XCTAssertTrue(titleBack.waitForExistence(timeout: 5))
            let settled = expectation(description: "\(method) 화면 렌더 완료")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
            wait(for: [settled], timeout: 2)
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = captureName
            capture.lifetime = .keepAlways
            add(capture)
            titleBack.tap()

            XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        }
    }

    func testFitLabConfirmExplainsThatReportWillNotBeSaved() throws {
        let historyNamespace = "feature-confirm-\(UUID().uuidString)"
        var app = launchApp(
            at: "fitlab-result-top",
            fixture: "history-persistence",
            extraArguments: [
                "--coordit-fitlab-history-namespace", historyNamespace,
                "--coordit-fitlab-history-reset",
            ]
        )

        let guide = element("fitlab-confirm-report-guide", in: app)
        XCTAssertTrue(guide.waitForExistence(timeout: 5))
        XCTAssertTrue(guide.label.contains("저장되지 않고"))
        element("fitlab-confirm-report", in: app).tap()
        assertScreen("fitlab-input", in: app)
        XCTAssertEqual(
            element("fitlab-draft-isolation-probe", in: app).label,
            "source=manual|category=tshirt|product=|url=nil"
        )
        XCTAssertTrue(element("fitlab-history-empty", in: app).waitForExistence(timeout: 5))
        let transitionSettled = expectation(description: "FIT LAB input transition settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { transitionSettled.fulfill() }
        wait(for: [transitionSettled], timeout: 2)
        let confirmedReturnCapture = XCTAttachment(screenshot: app.screenshot())
        confirmedReturnCapture.name = "fitlab-confirm-returned-to-input"
        confirmedReturnCapture.lifetime = .keepAlways
        add(confirmedReturnCapture)
        app.terminate()

        app = launchApp(
            at: "main04",
            fixture: "history-persistence",
            extraArguments: ["--coordit-fitlab-history-namespace", historyNamespace]
        )
        XCTAssertTrue(app.staticTexts["저장한 핏 리포트가 아직 없어요"].waitForExistence(timeout: 5))
    }

    func testHomeShowsTwoSavedFitReportsAndOpensExactDetail() throws {
        let historyNamespace = "feature-home-history-\(UUID().uuidString)"
        let historyArguments = ["--coordit-fitlab-history-namespace", historyNamespace]

        var app = launchApp(
            at: "fitlab-result-top",
            fixture: "history-persistence",
            extraArguments: historyArguments + ["--coordit-fitlab-history-reset"]
        )
        element("fitlab-add-history", in: app).tap()
        assertScreen("fitlab-input", in: app)
        app.terminate()

        app = launchApp(
            at: "fitlab-result-bottom",
            fixture: "history-persistence",
            extraArguments: historyArguments
        )
        element("fitlab-add-history", in: app).tap()
        assertScreen("fitlab-input", in: app)
        app.terminate()

        app = launchApp(
            at: "main04",
            fixture: "history-persistence",
            extraArguments: historyArguments
        )
        assertScreen("main04", in: app)

        let latestCard = element("coordit-main04-history-card-analysis-fixture-lower", in: app)
        let previousCard = element("coordit-main04-history-card-analysis-fixture-upper", in: app)
        XCTAssertTrue(latestCard.waitForExistence(timeout: 5))
        XCTAssertTrue(previousCard.waitForExistence(timeout: 5))
        XCTAssertLessThan(latestCard.frame.minX, previousCard.frame.minX)

        latestCard.tap()
        assertScreen("fitlab-history-detail", in: app)
        XCTAssertEqual(element("fitlab-history-detail-analysis", in: app).label, "analysis-fixture-lower")
    }

    func testHomeReferenceSelectorChoosesExistingClosetItem() throws {
        let app = launchApp(at: "main04")
        assertScreen("main04", in: app)

        app.buttons["옷장에서 선택"].tap()
        let oxford = app.buttons["home-reference-item-oxford"]
        XCTAssertTrue(oxford.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-reference-item-denim"].exists)
        let sheetCapture = XCTAttachment(screenshot: app.screenshot())
        sheetCapture.name = "home-reference-selection-sheet"
        sheetCapture.lifetime = .keepAlways
        add(sheetCapture)
        oxford.tap()
        app.buttons["home-reference-done"].tap()

        XCTAssertTrue(app.buttons["다시 선택"].waitForExistence(timeout: 5))
    }

    func testMyPageRowsOpenTheirFinalScreens() throws {
        let destinations = [
            ("계정", "mypage-account"),
            ("내 신체 정보", "mypage-body"),
            ("알림", "mypage-notifications"),
            ("개인정보/보안", "mypage-privacy"),
            ("앱 설정", "mypage-app-settings"),
        ]

        for (label, route) in destinations {
            let app = launchApp(at: "mypage")
            assertScreen("mypage", in: app)
            let row = app.buttons[label]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing My Page row: \(label)")
            row.tap()
            assertScreen(route, in: app)
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
    }

    func testClosetOverviewOpensWideDenimDetail() throws {
        let app = launchApp(at: "closet-overview")
        assertScreen("closet-overview", in: app)

        let bottomCategory = app.buttons["closet-category-bottom"]
        XCTAssertTrue(bottomCategory.waitForExistence(timeout: 5))
        bottomCategory.tap()
        let wideDenim = app.buttons["Wide Denim"]
        XCTAssertTrue(wideDenim.waitForExistence(timeout: 5))
        let lowerFilterCapture = XCTAttachment(screenshot: app.screenshot())
        lowerFilterCapture.name = "closet-lower-category-filter"
        lowerFilterCapture.lifetime = .keepAlways
        add(lowerFilterCapture)
        wideDenim.tap()

        assertScreen("closet-detail-bottom", in: app)
        XCTAssertTrue(element("Wide Denim", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("closet-mannequin-bottom", in: app).exists)
        XCTAssertFalse(element("closet-mannequin-top", in: app).exists)
    }

    func testClosetDetailShowsTheRegisteredLowerGarmentSizeChart() throws {
        let app = launchApp(at: "closet-detail-bottom")
        assertScreen("closet-detail-bottom", in: app)

        let sizeChart = element("closet-detail-size-chart", in: app)
        XCTAssertTrue(sizeChart.waitForExistence(timeout: 5))
        XCTAssertEqual(element("closet-detail-size-label", in: app).label, "M")
        XCTAssertEqual(element("closet-detail-measurement-waist-width", in: app).label, "40 cm")
        XCTAssertEqual(element("closet-detail-measurement-outseam", in: app).label, "101 cm")
    }

    func testClosetDeleteRemovesTheSelectedGarmentAndReturnsToOverview() throws {
        let app = launchApp(at: "closet-detail-bottom")
        assertScreen("closet-detail-bottom", in: app)

        let deleteButton = app.buttons["closet-detail-delete"]
        XCTAssertTrue(deleteButton.waitForExistence(timeout: 5))
        deleteButton.tap()
        app.buttons["삭제"].tap()

        assertScreen("closet-overview", in: app)
        app.buttons["closet-category-bottom"].tap()
        XCTAssertFalse(app.buttons["Wide Denim"].exists)
    }

    func testClosetReassessmentUpdatesOnlySelectedItemWithNeutralStatus() throws {
        let app = launchApp(at: "closet-detail-bottom")
        assertScreen("closet-detail-bottom", in: app)

        let reassess = app.buttons["closet-reevaluate"]
        for _ in 0..<3 where !reassess.exists { app.swipeUp() }
        XCTAssertTrue(reassess.waitForExistence(timeout: 5))
        reassess.tap()

        let status = element("closet-reassessment-status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "선택한 의류의 핏 스코어를 다시 계산했어요.")
        XCTAssertTrue(app.buttons["총점 | 92.0"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("Wide Denim", in: app).exists)
        let reassessmentCapture = XCTAttachment(screenshot: app.screenshot())
        reassessmentCapture.name = "closet-reassessment-complete"
        reassessmentCapture.lifetime = .keepAlways
        add(reassessmentCapture)
    }

    func testClosetDetailAutomaticallyLoadsEngineScoreForUpperAndLower() throws {
        for (route, expectedScore, tightOverlay, otherOverlay, otherDirection) in [
            ("closet-detail-top", "총점 | 89.0", "closet-overlay-chest_width", "closet-overlay-shoulder_width", "여유"),
            ("closet-detail-bottom", "총점 | 92.0", "closet-overlay-hip_width", "closet-overlay-waist_width", "비슷"),
        ] {
            let app = launchApp(at: route)
            assertScreen(route, in: app)

            let totalScore = element("closet-detail-total-score", in: app)
            XCTAssertTrue(totalScore.waitForExistence(timeout: 5))
            let loaded = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@", expectedScore),
                object: totalScore
            )
            XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
            XCTAssertTrue(element(tightOverlay, in: app).label.contains("타이트"))
            XCTAssertTrue(element(otherOverlay, in: app).label.contains(otherDirection))
            let mannequin = element(
                route == "closet-detail-top" ? "closet-mannequin-top" : "closet-mannequin-bottom",
                in: app
            )
            let visibleBottom = app.windows.firstMatch.frame.maxY - 145
            for _ in 0..<5 where mannequin.frame.maxY > visibleBottom {
                app.swipeUp()
            }
            let capture = XCTAttachment(screenshot: app.screenshot())
            capture.name = "\(route)-silhouette-overlay"
            capture.lifetime = .keepAlways
            add(capture)
            app.terminate()
        }
    }

    func testClosetAddInputsMatchRelocatedPhotoRequirements() throws {
        var app = launchApp(at: "closet-add-method")
        assertScreen("closet-add-method", in: app)

        app.terminate()
        app = launchApp(at: "closet-add-photo")
        XCTAssertTrue(element("closet-size-chart-photo", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(
            element("closet-garment-photo", in: app).exists,
            "Photo input must reserve garment photos for FIT DETAIL."
        )

        app.terminate()
        app = launchApp(at: "closet-add-manual")
        XCTAssertFalse(
            element("closet-manual-garment-photo", in: app).exists,
            "Manual input must reserve garment photos for FIT DETAIL."
        )
        for index in 0..<4 {
            XCTAssertTrue(
                app.textFields["closet-manual-measurement-\(index)"].waitForExistence(timeout: 5),
                "Manual input must retain measurement field \(index)."
            )
        }
    }

    func testClosetLinkAddShowsResultAndPersistsInOverview() throws {
        let app = launchApp(at: "closet-overview")
        assertScreen("closet-overview", in: app)

        app.buttons["closet-add-garment"].tap()
        app.buttons["closet-add-method-link"].tap()
        assertScreen("closet-add-link", in: app)

        let linkField = app.textFields["closet-product-link"]
        linkField.tap()
        linkField.typeText("https://coordit.test/item")
        app.swipeDown()

        let submit = app.buttons["closet-add-submit"]
        XCTAssertTrue(submit.isEnabled)
        submit.tap()
        XCTAssertTrue(element("closet-link-size-row-L", in: app).waitForExistence(timeout: 5))
        element("closet-link-size-row-L", in: app).tap()
        submit.tap()
        assertScreen("closet-add-loading", in: app)
        assertScreen("closet-add-result", in: app)
        XCTAssertTrue(element("리넨 셔츠", in: app).waitForExistence(timeout: 5))

        let backToCloset = app.buttons["FIT DETAIL"]
        XCTAssertTrue(backToCloset.waitForExistence(timeout: 5))
        backToCloset.tap()
        assertScreen("closet-overview", in: app)
        XCTAssertTrue(app.buttons["리넨 셔츠"].waitForExistence(timeout: 5))
    }

    private func launchApp(
        at route: String,
        fixture: String? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-start-route",
            route,
        ]
        if let fixture {
            app.launchArguments += ["--coordit-fitlab-fixture", fixture]
        }
        app.launchArguments += extraArguments
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
            "Missing final route: \(route)",
            file: file,
            line: line
        )
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func waitForDisappearance(
        _ element: XCUIElement,
        timeout: TimeInterval = 3,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: element
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [expectation], timeout: timeout),
            .completed,
            file: file,
            line: line
        )
    }

    private func whiteLogoCenter(in image: UIImage) throws -> CGFloat {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        let context = try XCTUnwrap(
            CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        )
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let bytes = try XCTUnwrap(context.data?.assumingMemoryBound(to: UInt8.self))
        let minY = Int(CGFloat(height) * 0.40)
        let maxY = Int(CGFloat(height) * 0.56)
        var minX = width
        var maxX = 0

        for y in minY..<maxY {
            let row = bytes + y * width * 4
            for x in 0..<width {
                let pixel = row + x * 4
                guard pixel[0] > 230, pixel[1] > 230, pixel[2] > 230 else { continue }
                minX = min(minX, x)
                maxX = max(maxX, x)
            }
        }

        XCTAssertLessThan(minX, maxX, "Could not locate the white splash logo")
        return CGFloat(minX + maxX) / 2
    }
}
#endif
