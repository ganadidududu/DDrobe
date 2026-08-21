#if canImport(XCTest)
import Foundation
import XCTest

final class CoorditMyPageNestedNavigationUITests: XCTestCase {
    private struct Destination {
        let parentRoute: String
        let rowLabel: String
        let route: String
    }

    private let destinations = [
        Destination(parentRoute: "mypage-account", rowLabel: "프로필 수정", route: "mypage-profile-edit"),
        Destination(parentRoute: "mypage-account", rowLabel: "회원 탈퇴", route: "mypage-account-deletion"),
        Destination(parentRoute: "mypage-body", rowLabel: "신체 정보 수정", route: "mypage-body-measurements"),
        Destination(parentRoute: "mypage-privacy", rowLabel: "개인정보 처리방침", route: "mypage-privacy-policy"),
        Destination(parentRoute: "mypage-privacy", rowLabel: "서비스 이용약관", route: "mypage-terms"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testDeviceCanReachLiveBackendHealth() async throws {
        let baseURL = try requireLiveBackendBaseURL()
        let url = try XCTUnwrap(URL(string: baseURL).map { $0.appending(path: "health") })
        let (data, response) = try await URLSession.shared.data(from: url)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        XCTAssertEqual(httpResponse.statusCode, 200, "Unexpected health status from \(url.absoluteString)")
        XCTAssertTrue(
            String(data: data, encoding: .utf8)?.contains("coordit-backend") == true,
            "Unexpected health response from \(url.absoluteString): \(String(data: data, encoding: .utf8) ?? "<non-utf8>")"
        )
    }

    func testEveryChevronRowOpensItsDestination() throws {
        for destination in destinations {
            let app = launchApp(at: destination.parentRoute)
            assertScreen(destination.parentRoute, in: app)

            let row = app.buttons[destination.rowLabel]
            XCTAssertTrue(row.waitForExistence(timeout: 5), "Missing row: \(destination.rowLabel)")
            tap(row, in: app)

            assertScreen(destination.route, in: app)
            app.terminate()
            XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
        }
    }

    func testSignedInAccountShowsLogoutInsteadOfSocialProviders() throws {
        let app = launchApp(at: "mypage-account", authenticated: true)
        assertScreen("mypage-account", in: app)

        XCTAssertTrue(element("mypage-backend-local-logout", in: app).waitForExistence(timeout: 5))
        XCTAssertFalse(element("mypage-backend-google-login", in: app).exists)
        XCTAssertFalse(element("mypage-backend-apple-login", in: app).exists)
    }

    func testPrivacyCardFollowsItsHeaderWithoutLargeGap() throws {
        let app = launchApp(at: "mypage-privacy")
        assertScreen("mypage-privacy", in: app)

        let header = app.buttons["개인정보/보안 뒤로가기"]
        let firstRow = app.buttons["개인정보 처리방침"]
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(firstRow.waitForExistence(timeout: 5))
        XCTAssertLessThan(firstRow.frame.minY - header.frame.maxY, 40)
    }

    func testSharedFitLabLaunchURLRoutesToURLInput() throws {
        let sharedURL = "https://www.musinsa.com/products/6252903"
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-shared-fitlab-url",
            sharedURL,
        ]
        app.launch()

        assertScreen("fitlab-input", in: app)
        XCTAssertTrue(element("fitlab-url-flow", in: app).waitForExistence(timeout: 5))
        let field = element("fitlab-url-field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing shared URL field")
        XCTAssertEqual(field.value as? String, sharedURL)
    }

    func testPendingSharedFitLabURLRoutesToURLInput() throws {
        let sharedURL = "https://www.musinsa.com/products/6252903"
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-pending-fitlab-url",
            sharedURL,
        ]
        app.launch()

        assertScreen("fitlab-input", in: app)
        XCTAssertTrue(element("fitlab-url-flow", in: app).waitForExistence(timeout: 5))
        let field = element("fitlab-url-field", in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing pending URL field")
        XCTAssertEqual(field.value as? String, sharedURL)
    }

    func testMusinsaShareSheetCanSendProductToCoordit() throws {
        let musinsa = XCUIApplication(bundleIdentifier: "com.grab.musinsa")
        musinsa.terminate()
        musinsa.launch()

        sleep(2)
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        if springboard.buttons["취소"].exists {
            springboard.buttons["취소"].tap()
        }

        musinsa.swipeUp()
        sleep(1)
        musinsa.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.29)).tap()

        sleep(3)

        if musinsa.buttons["공유"].waitForExistence(timeout: 1) {
            musinsa.buttons["공유"].tap()
        } else {
            musinsa.coordinate(withNormalizedOffset: CGVector(dx: 0.10, dy: 0.86)).tap()
        }

        sleep(2)

        let coorditShareCell = musinsa.cells.matching(NSPredicate(format: "label ==[c] %@", "coordit")).firstMatch
        XCTAssertTrue(coorditShareCell.waitForExistence(timeout: 5), "Coordit is missing from Musinsa share sheet")
        coorditShareCell.tap()

        let coordit = XCUIApplication(bundleIdentifier: "com.inseong.coordit")
        XCTAssertTrue(coordit.wait(for: .runningForeground, timeout: 10), "Coordit did not open from Musinsa share")
        if coordit.buttons["Coordit 앱 다시 열기"].waitForExistence(timeout: 3) {
            coordit.buttons["Coordit 앱 다시 열기"].tap()
        }
        XCTAssertTrue(element("coordit-screen-fitlab-input", in: coordit).waitForExistence(timeout: 10))
        XCTAssertTrue(element("fitlab-url-flow", in: coordit).waitForExistence(timeout: 10))
    }

    func testAuthenticatedMyPageShowsYarnBalanceAndOpensCharge() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-thread-balance",
            "36",
            "--coordit-start-route",
            "mypage",
        ]
        app.launch()
        assertScreen("mypage", in: app)

        XCTAssertTrue(
            app.staticTexts["보유 실타래"].waitForExistence(timeout: 5),
            "Missing authenticated yarn balance label: 보유 실타래"
        )
        XCTAssertTrue(
            app.staticTexts["36 실타래"].waitForExistence(timeout: 5),
            "Missing authenticated yarn balance value: 36 실타래"
        )

        let chargeButton = app.buttons["충전"]
        XCTAssertTrue(chargeButton.waitForExistence(timeout: 5), "Missing authenticated yarn charge button: 충전")
        XCTAssertFalse(element("mypage-login-entry", in: app).exists)
        XCTAssertFalse(app.buttons["로그인 / 회원가입"].exists)

        tap(chargeButton, in: app)
        assertScreen("mypage-thread-charge", in: app)
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testThreadChargeControlsAreDisabledUntilSettlementIsConfigured() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-thread-balance",
            "36",
            "--coordit-start-route",
            "mypage-thread-charge",
        ]
        app.launch()
        assertScreen("mypage-thread-charge", in: app)

        for text in ["실타래 충전", "보유 실타래", "36 실타래", "5 실타래", "10 실타래", "20 실타래", "1,500원", "2,500원", "4,000원"] {
            XCTAssertTrue(app.staticTexts[text].waitForExistence(timeout: 5), "Missing visible charge content: \(text)")
        }

        let adCTA = app.buttons["광고 보고 실타래 충전하기"]
        XCTAssertTrue(adCTA.waitForExistence(timeout: 5), "Missing visible ad CTA")

        let requiredIdentifiers = [
            "coordit-thread-charge-balance",
            "coordit-thread-charge-ad-cta",
            "coordit-thread-charge-pack-5",
            "coordit-thread-charge-pack-10",
            "coordit-thread-charge-pack-20",
        ]
        for identifier in requiredIdentifiers {
            XCTAssertTrue(
                element(identifier, in: app).waitForExistence(timeout: 5),
                "Missing charge accessibility identifier: \(identifier)"
            )
        }

        let controls = [
            "coordit-thread-charge-ad-cta",
            "coordit-thread-charge-pack-5",
            "coordit-thread-charge-pack-10",
            "coordit-thread-charge-pack-20",
        ]
        for identifier in controls {
            let control = element(identifier, in: app)
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing charge control: \(identifier)")
            XCTAssertFalse(control.isEnabled, "Charge control must stay disabled without settlement")
        }

        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    func testEditableAndConfirmationDestinationsExposeWorkingControls() throws {
        var app = launchApp(at: "mypage-profile-edit")
        completeAction("프로필 저장", expecting: "mypage-profile-saved", in: app)

        app = launchApp(at: "mypage-logout")
        completeAction("로그아웃 확인", expecting: "mypage-logout-complete", in: app)

        app = launchApp(at: "mypage-account-deletion")
        let acknowledgement = app.buttons["삭제되는 데이터와 복구 불가 안내를 확인했습니다."]
        XCTAssertTrue(acknowledgement.waitForExistence(timeout: 5))
        tap(acknowledgement, in: app)
        completeAction("회원 탈퇴 확인", expecting: "mypage-account-deletion-complete", in: app)

        app = launchApp(at: "mypage-body-measurements", authenticated: true)
        XCTAssertTrue(element("mypage-measurement-height", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("mypage-measurement-weight", in: app).exists)
        XCTAssertFalse(element("mypage-measurement-shoulder", in: app).exists)
        XCTAssertFalse(element("mypage-measurement-chest", in: app).exists)
        XCTAssertFalse(element("mypage-measurement-waist", in: app).exists)
        XCTAssertFalse(element("mypage-measurement-hip", in: app).exists)
        XCTAssertFalse(element("mypage-measurement-inseam", in: app).exists)
        typeText("171", into: "mypage-measurement-height", in: app)
        typeText("61", into: "mypage-measurement-weight", in: app)
        completeAction("키와 몸무게 저장", expecting: "mypage-body-measurements-saved", in: app)

    }

    func testBodyMeasurementsEditorOnlyExposesHeightAndWeight() throws {
        let app = launchApp(at: "mypage-body-measurements", authenticated: true)
        assertScreen("mypage-body-measurements", in: app)

        XCTAssertTrue(element("mypage-measurement-height", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("mypage-measurement-weight", in: app).exists)
        for legacyField in [
            "mypage-measurement-shoulder",
            "mypage-measurement-chest",
            "mypage-measurement-waist",
            "mypage-measurement-hip",
            "mypage-measurement-inseam"
        ] {
            XCTAssertFalse(element(legacyField, in: app).exists, "Unexpected legacy field: \(legacyField)")
        }

        typeText("171", into: "mypage-measurement-height", in: app)
        typeText("61", into: "mypage-measurement-weight", in: app)
        let save = element("mypage-body-measurements-save", in: app)
        XCTAssertTrue(save.isEnabled)
        tap(save, in: app)
        XCTAssertTrue(element("mypage-body-measurements-saved", in: app).waitForExistence(timeout: 5))
    }

    func testAppSettingsOnlyShowsVersionAndMailSupport() throws {
        let app = launchApp(at: "mypage-app-settings")
        assertScreen("mypage-app-settings", in: app)

        XCTAssertTrue(app.staticTexts["hyu.coordit@gmail.com"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["문의하기"].exists)
        XCTAssertFalse(app.staticTexts["테마"].exists)
        XCTAssertFalse(app.staticTexts["언어"].exists)
        XCTAssertFalse(app.buttons["버그 신고"].exists)
    }

    func testMarketingNotificationsExposeSystemControls() throws {
        let app = launchApp(at: "mypage-notifications")
        assertScreen("mypage-notifications", in: app)

        XCTAssertTrue(element("mypage-marketing-notifications", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("mypage-marketing-notifications-status", in: app).exists)
        XCTAssertTrue(element("mypage-open-notification-settings", in: app).exists)
    }

    func testPasswordRouteExplainsSocialOnlyAuthentication() throws {
        let app = launchApp(at: "mypage-password-change")
        XCTAssertTrue(app.staticTexts["비밀번호는 사용하지 않아요"].waitForExistence(timeout: 5))
        XCTAssertFalse(element("mypage-password-current", in: app).exists)
    }

    private func launchApp(at route: String, authenticated: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        var launchArguments = [
            "--coordit-ui-testing",
            "--coordit-start-route",
            route,
        ]
        if authenticated {
            launchArguments.append("--coordit-ui-testing-authenticated")
        }
        app.launchArguments = launchArguments
        app.launch()
        return app
    }

    private var liveBackendBaseURL: String {
        ProcessInfo.processInfo.environment["COORDIT_API_BASE_URL"] ?? ""
    }

    private func requireLiveBackendBaseURL() throws -> String {
        let value = liveBackendBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            throw XCTSkip("Set COORDIT_API_BASE_URL to run live backend device tests.")
        }
        return value
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

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func typeText(_ text: String, into identifier: String, in app: XCUIApplication) {
        let field = element(identifier, in: app)
        XCTAssertTrue(field.waitForExistence(timeout: 5), "Missing field: \(identifier)")
        makeHittable(field, in: app)
        field.tap()
        field.typeText(text)
    }

    private func completeAction(_ label: String, expecting identifier: String, in app: XCUIApplication) {
        let action = app.buttons[label]
        XCTAssertTrue(action.waitForExistence(timeout: 5), "Missing action: \(label)")
        tap(action, in: app)
        XCTAssertTrue(
            element(identifier, in: app).waitForExistence(timeout: 5),
            "Missing completion state: \(identifier)"
        )
        app.terminate()
        XCTAssertTrue(app.wait(for: .notRunning, timeout: 5))
    }

    private func tap(_ element: XCUIElement, in app: XCUIApplication) {
        makeHittable(element, in: app)
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(element)")
        element.tap()
    }

    private func makeHittable(_ element: XCUIElement, in app: XCUIApplication) {
        if app.keyboards.firstMatch.exists {
            let dismissKeyboard = app.buttons["coordit-keyboard-dismiss"]
            if dismissKeyboard.waitForExistence(timeout: 1), dismissKeyboard.isHittable {
                dismissKeyboard.tap()
            }
        }

        for _ in 0..<5 where !element.isHittable {
            app.swipeUp()
        }
    }
}
#endif
