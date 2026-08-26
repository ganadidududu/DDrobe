#if canImport(XCTest)
import XCTest

final class CoorditFeatureFlowsUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testFreshInstallShowsSplashThenSocialAuthenticationEntry() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: ["--coordit-welcome-state", "fresh"]
        )
        assertScreen("splash", in: app)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "fresh-install-splash"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let loginEntry = app.buttons["splash-signup-entry"]
        XCTAssertTrue(loginEntry.waitForExistence(timeout: 3))
        XCTAssertTrue(loginEntry.isHittable)
        XCTAssertFalse(element("coordit-splash-auth-sheet", in: app).exists)
        XCTAssertFalse(element("coordit-screen-main04", in: app).exists)

        loginEntry.tap()
        XCTAssertTrue(element("coordit-splash-auth-sheet", in: app).waitForExistence(timeout: 5))
        let googleLogin = element("splash-auth-google", in: app)
        let appleLogin = element("splash-auth-apple", in: app)
        XCTAssertTrue(googleLogin.waitForExistence(timeout: 3))
        XCTAssertTrue(googleLogin.isHittable)
        XCTAssertTrue(appleLogin.waitForExistence(timeout: 3))
        XCTAssertTrue(appleLogin.isHittable)
        XCTAssertFalse(element("coordit-auth-backend-status", in: app).exists)
        let emailPasswordNotice = app.staticTexts
            .matching(NSPredicate(format: "label CONTAINS %@", "이메일과 비밀번호"))
            .firstMatch
        XCTAssertFalse(emailPasswordNotice.exists)
    }

    func testReturningAuthenticatedSplashEntersMainWithoutFixtureAuthenticationError() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: [
                "--coordit-welcome-state", "fresh",
                "--coordit-ui-testing-authenticated",
                "--coordit-api-base-url", "http://127.0.0.1:45678",
            ]
        )

        assertScreen("splash", in: app)
        XCTAssertTrue(element("coordit-splash-tap-hint", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["splash-signup-entry"].exists)
        element("coordit-screen-splash", in: app).tap()
        assertScreen("main04", in: app)
        XCTAssertFalse(element("home-reference-sync-status", in: app).waitForExistence(timeout: 10))
    }

    func testPersistedSocialSessionSurvivesColdRelaunchWithoutProviderSignup() throws {
        addTeardownBlock {
            let cleanup = self.launchApp(
                at: "splash",
                extraArguments: ["--coordit-ui-testing-clear-persisted-session"]
            )
            cleanup.terminate()
        }

        let seeded = launchApp(
            at: "splash",
            extraArguments: [
                "--coordit-ui-testing-clear-persisted-session",
                "--coordit-ui-testing-seed-persisted-session",
                "--coordit-api-base-url", "http://127.0.0.1:45678",
            ]
        )
        XCTAssertTrue(element("coordit-splash-tap-hint", in: seeded).waitForExistence(timeout: 5))
        XCTAssertFalse(seeded.buttons["splash-signup-entry"].exists)
        seeded.terminate()

        let restored = launchApp(
            at: "splash",
            extraArguments: ["--coordit-api-base-url", "http://127.0.0.1:45678"]
        )
        XCTAssertTrue(element("coordit-splash-tap-hint", in: restored).waitForExistence(timeout: 5))
        XCTAssertFalse(restored.buttons["splash-signup-entry"].exists)
        element("coordit-screen-splash", in: restored).tap()
        assertScreen("main04", in: restored)
    }

    func testReturningLoggedOutUserSeesSplashBeforeAuthenticationEntry() throws {
        let app = launchApp(
            at: "splash",
            extraArguments: ["--coordit-welcome-state", "returning"]
        )

        assertScreen("splash", in: app)
        let loginEntry = app.buttons["splash-signup-entry"]
        XCTAssertTrue(loginEntry.waitForExistence(timeout: 3))
        XCTAssertTrue(loginEntry.isHittable)
        XCTAssertFalse(element("coordit-splash-auth-sheet", in: app).exists)
        loginEntry.tap()
        XCTAssertTrue(element("coordit-splash-auth-sheet", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["splash-auth-google"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["splash-auth-apple"].waitForExistence(timeout: 3))
        XCTAssertFalse(element("coordit-screen-main04", in: app).exists)
        XCTAssertFalse(element("coordit-thread-charge-balance", in: app).exists)
    }

    func testUnauthenticatedThreadChargeRouteCannotRevealThreadBalance() throws {
        let app = launchApp(
            at: "mypage-thread-charge",
            extraArguments: [
                "--coordit-welcome-state", "returning",
                "--coordit-enforce-auth-gate",
            ]
        )

        assertScreen("splash", in: app)
        XCTAssertTrue(app.buttons["splash-signup-entry"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("coordit-splash-auth-sheet", in: app).exists)
        XCTAssertFalse(element("coordit-thread-charge-balance", in: app).exists)
        XCTAssertFalse(app.staticTexts["36 실타래"].exists)
    }

    func testSplashLogoIsHorizontallyCentered() throws {
        let app = launchApp(at: "splash")
        assertScreen("splash", in: app)

        let screenshot = app.screenshot().image
        let logoCenter = try whiteLogoCenter(in: screenshot)
        let screenCenter = CGFloat(screenshot.cgImage!.width) / 2

        XCTAssertEqual(logoCenter, screenCenter, accuracy: 6)
    }

    func testSignedInMyPageAccountShowsLogoutWithoutSocialProviders() throws {
        let app = launchApp(
            at: "mypage-account",
            extraArguments: ["--coordit-ui-testing-authenticated"]
        )
        assertScreen("mypage-account", in: app)

        XCTAssertTrue(element("mypage-backend-local-logout", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("mypage-backend-google-login", in: app).exists)
        XCTAssertFalse(element("mypage-backend-apple-login", in: app).exists)
    }

    func testSignedOutMyPageAccountDoesNotOfferSocialProviders() throws {
        let app = launchApp(at: "mypage-account")
        assertScreen("mypage-account", in: app)

        XCTAssertFalse(element("mypage-backend-google-login", in: app).exists)
        XCTAssertFalse(element("mypage-backend-apple-login", in: app).exists)
    }

    func testIncompleteSocialAccountMustFinishOnboardingBeforeUsingTheApp() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-ui-testing-onboarding-incomplete",
        ]
        app.launch()

        XCTAssertTrue(element("coordit-splash-tap-hint", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("coordit-onboarding-title", in: app).exists)
        element("coordit-screen-splash", in: app).tap()
        XCTAssertTrue(element("coordit-onboarding-title", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("onboarding-display-name", in: app).exists)
        XCTAssertTrue(app.textFields["onboarding-birth-year"].exists)
        XCTAssertTrue(app.textFields["onboarding-birth-month"].exists)
        XCTAssertTrue(app.textFields["onboarding-birth-day"].exists)
        XCTAssertFalse(element("onboarding-gender-non_binary", in: app).exists)
        app.buttons["onboarding-next"].tap()
        XCTAssertTrue(app.buttons["나중에 입력하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(element("onboarding-measurement-height", in: app).exists)
        XCTAssertTrue(element("onboarding-measurement-weight", in: app).exists)
        XCTAssertFalse(element("onboarding-measurement-outseam", in: app).exists)
        app.buttons["나중에 입력하기"].tap()
        XCTAssertTrue(app.staticTexts["[필수] 서비스 이용약관"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["[필수] 개인정보 처리방침"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding-save"].isEnabled)
        app.buttons["onboarding-back"].tap()
        XCTAssertEqual(element("coordit-onboarding-title", in: app).label, "핏 정보")
    }

    func testOnboardingBirthDateUsesSeparateYearMonthDayFields() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-ui-testing-onboarding-incomplete",
        ]
        app.launch()

        XCTAssertTrue(element("coordit-splash-tap-hint", in: app).waitForExistence(timeout: 5))
        element("coordit-screen-splash", in: app).tap()
        let year = app.textFields["onboarding-birth-year"]
        let month = app.textFields["onboarding-birth-month"]
        let day = app.textFields["onboarding-birth-day"]
        XCTAssertTrue(year.waitForExistence(timeout: 5))
        XCTAssertTrue(month.exists)
        XCTAssertTrue(day.exists)
        XCTAssertEqual(year.placeholderValue, "1998")
        XCTAssertEqual(month.placeholderValue, "05")
        XCTAssertEqual(day.placeholderValue, "17")
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

    func testClosetDetailDoesNotOfferReassessment() throws {
        let app = launchApp(at: "closet-detail-bottom")
        assertScreen("closet-detail-bottom", in: app)

        let reassess = app.buttons["closet-reevaluate"]
        for _ in 0..<3 where !reassess.exists { app.swipeUp() }
        XCTAssertFalse(reassess.exists, "옷장 상세에서는 재평가를 제공하지 않아야 해요.")
        XCTAssertFalse(element("closet-reassessment-status", in: app).exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "closet-detail-without-reassessment"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testClosetDetailShowsItsSavedScoreAndGapToBestFit() throws {
        for (route, expectedScore, expectedGap, expectedDifferences) in [
            (
                "closet-detail-top",
                "총점 | 94.0",
                "BEST FIT과 6.0점 차이",
                ["어깨, -1 cm", "가슴, +2 cm", "총장, +1.5 cm", "소매, -0.5 cm"]
            ),
            (
                "closet-detail-bottom",
                "총점 | 91.0",
                "BEST FIT과 9.0점 차이",
                ["허리, -3 cm", "엉덩이, +1 cm", "밑위, -0.5 cm", "총장, +2 cm"]
            ),
        ] {
            let app = launchApp(at: route)
            assertScreen(route, in: app)

            let totalScore = element("closet-detail-total-score", in: app)
            XCTAssertTrue(totalScore.waitForExistence(timeout: 5))
            XCTAssertEqual(totalScore.label, expectedScore)
            let bestFitGap = element("closet-detail-best-fit-gap", in: app)
            XCTAssertTrue(bestFitGap.waitForExistence(timeout: 5))
            XCTAssertEqual(bestFitGap.label, expectedGap)
            for _ in 0..<5 where !totalScore.isHittable { app.swipeUp() }
            XCTAssertTrue(totalScore.isHittable)
            for (index, expectedDifference) in expectedDifferences.enumerated() {
                let difference = element("closet-detail-fit-difference-\(index)", in: app)
                XCTAssertTrue(difference.waitForExistence(timeout: 5))
                XCTAssertTrue(difference.isHittable)
                XCTAssertEqual(difference.label, expectedDifference)
            }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "\(route)-fit-score-differences"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTAssertFalse(element("closet-detail-score-description", in: app).exists)
            XCTAssertFalse(app.buttons["closet-reevaluate"].exists)
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
