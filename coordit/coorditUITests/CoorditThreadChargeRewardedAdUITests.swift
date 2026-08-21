#if os(iOS)
import XCTest

final class CoorditThreadChargeRewardedAdUITests: XCTestCase {
    private var runningApps: [XCUIApplication] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for app in runningApps.reversed() {
            app.terminate()
        }
        runningApps.removeAll()
    }

    func testRewardedAdUsesAttemptCustomDataAndWaitsForServerCredit() throws {
        let app = launchChargeScreen(authenticated: true, scenario: "credited")
        let balance = app.staticTexts["36 실타래"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "Missing initial server balance")

        let adCTA = app.buttons["coordit-thread-charge-ad-cta"]
        XCTAssertTrue(adCTA.waitForExistence(timeout: 5), "Missing rewarded-ad CTA")
        XCTAssertTrue(waitUntilEnabled(adCTA), "Fixture ad never reached the loaded state")
        adCTA.tap()

        XCTAssertTrue(
            app.staticTexts["실타래 지급을 확인하고 있어요."]
                .waitForExistence(timeout: 3),
            "The UI must expose the server-settlement wait state"
        )
        XCTAssertEqual(balance.label, "36 실타래", "The reward closure must not increment locally")
        printAccessibilityTree(for: app, scenario: "awaiting-server-settlement")
        attachScreenshot(named: "rewarded-ad-awaiting-server-settlement", from: app)

        XCTAssertTrue(
            app.staticTexts["37 실타래"].waitForExistence(timeout: 5),
            "Only the later fake server response may update B to B+1"
        )
        let receipt = waitForReceipt(containing: "settled-balance:37", in: app)
        let attemptID = "00000000-0000-4000-8000-000000000401"
        XCTAssertEqual(occurrences(of: "attempt-created:\(attemptID)", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "load-custom-data:\(attemptID)", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "reward-callback", in: receipt), 1)
        XCTAssertTrue(receipt.contains("poll-balance:36"))
        XCTAssertTrue(receipt.contains("poll-balance:37"))
        XCTAssertTrue(
            receipt.range(of: "attempt-created:\(attemptID)")!.lowerBound
                < receipt.range(of: "load-custom-data:\(attemptID)")!.lowerBound,
            "The one server attempt must be created immediately before loading the ad"
        )
        XCTAssertTrue(
            receipt.range(of: "reward-callback")!.lowerBound
                < receipt.range(of: "settled-balance:37")!.lowerBound,
            "A server response must settle after, never inside, the client reward closure"
        )
        print("COORDIT_REWARDED_AD_RECEIPT:\(receipt)")
        printAccessibilityTree(for: app, scenario: "credited")
        attachScreenshot(named: "rewarded-ad-credited", from: app)
    }

    func testRewardedAdInvalidOrTimedOutSettlementDoesNotChangeBalance() throws {
        for scenario in ["invalid-callback", "timeout"] {
            let app = launchChargeScreen(authenticated: true, scenario: scenario)
            let balance = app.staticTexts["36 실타래"]
            XCTAssertTrue(balance.waitForExistence(timeout: 5), "Missing initial balance for \(scenario)")

            let adCTA = app.buttons["coordit-thread-charge-ad-cta"]
            XCTAssertTrue(adCTA.waitForExistence(timeout: 5))
            XCTAssertTrue(waitUntilEnabled(adCTA), "Fixture ad never loaded for \(scenario)")
            adCTA.tap()

            XCTAssertTrue(
                app.staticTexts["실타래 지급 확인이 지연되고 있어요. 다시 시도해 주세요."]
                    .waitForExistence(timeout: 5),
                "A missing/invalid SSV settlement must become retryable for \(scenario)"
            )
            XCTAssertEqual(balance.label, "36 실타래", "\(scenario) must not mutate balance")
            XCTAssertTrue(adCTA.isEnabled, "A terminal timeout must expose retry")

            let receipt = waitForReceipt(containing: "settlement-timeout:8", in: app)
            XCTAssertEqual(occurrences(of: "poll-balance:36", in: receipt), 8)
            XCTAssertFalse(receipt.contains("settled-balance:"))
            print("COORDIT_REWARDED_AD_\(scenario.uppercased())_RECEIPT:\(receipt)")
            printAccessibilityTree(for: app, scenario: scenario)
            attachScreenshot(named: "rewarded-ad-\(scenario)", from: app)
            app.terminate()
        }

        let loadFailureApp = launchChargeScreen(authenticated: true, scenario: "load-failure")
        let loadFailureCTA = loadFailureApp.buttons["coordit-thread-charge-ad-cta"]
        XCTAssertTrue(loadFailureCTA.waitForExistence(timeout: 5))
        XCTAssertTrue(
            loadFailureApp.staticTexts["광고를 준비하지 못했어요. 다시 시도해 주세요."]
                .waitForExistence(timeout: 5)
        )
        XCTAssertEqual(loadFailureApp.staticTexts["36 실타래"].label, "36 실타래")
        XCTAssertTrue(loadFailureCTA.isEnabled, "A terminal load failure must expose retry")
        let loadReceipt = waitForReceipt(containing: "load-failed", in: loadFailureApp)
        XCTAssertFalse(loadReceipt.contains("reward-callback"))
        printAccessibilityTree(for: loadFailureApp, scenario: "load-failure")
        attachScreenshot(named: "rewarded-ad-load-failure", from: loadFailureApp)
    }

    func testSignedOutUserCannotPrepareRewardedAd() throws {
        let app = launchChargeScreen(authenticated: false, scenario: "credited")
        let adCTA = app.buttons["coordit-thread-charge-ad-cta"]
        XCTAssertTrue(adCTA.waitForExistence(timeout: 5), "Missing rewarded-ad CTA")
        XCTAssertFalse(adCTA.isEnabled, "Signed-out users cannot prepare or present an ad")
        XCTAssertTrue(
            app.staticTexts["광고 보상은 로그인 후 받을 수 있어요."]
                .waitForExistence(timeout: 5),
            "Signed-out state must explain why the ad is unavailable"
        )
        let receipt = waitForReceipt(containing: "prepare-blocked:signed-out", in: app)
        XCTAssertFalse(receipt.contains("attempt-created:"))
        XCTAssertFalse(receipt.contains("load-custom-data:"))
        XCTAssertEqual(
            app.staticTexts["0 실타래"].label,
            "0 실타래",
            "Signed-out routes must retain their fail-closed zero balance"
        )
        print("COORDIT_REWARDED_AD_SIGNED_OUT_RECEIPT:\(receipt)")
        printAccessibilityTree(for: app, scenario: "signed-out")
        attachScreenshot(named: "rewarded-ad-signed-out", from: app)
    }

    private func launchChargeScreen(
        authenticated: Bool,
        scenario: String,
        balance: Int = 36
    ) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-user-id",
            "00000000-0000-4000-8000-000000000010",
            "--coordit-thread-balance",
            String(balance),
            "--coordit-monetization-readiness",
            "enabled",
            "--coordit-rewarded-ad-fixture",
            scenario,
            "--coordit-storekit-fixture",
            "credited",
            "--coordit-start-route",
            "mypage-thread-charge",
        ]
        if authenticated {
            arguments.append("--coordit-ui-testing-authenticated")
        }
        app.launchArguments = arguments
        app.launch()
        runningApps.append(app)

        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "coordit-screen-mypage-thread-charge")
                .firstMatch
                .waitForExistence(timeout: 5),
            "Charge screen did not load for \(scenario)"
        )
        return app
    }

    private func waitUntilEnabled(_ element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "enabled == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    private func waitForReceipt(containing event: String, in app: XCUIApplication) -> String {
        let receipt = app.descendants(matching: .any)
            .matching(identifier: "coordit-thread-reward-fixture-receipt")
            .firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5), "Missing sanitized reward receipt")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", event),
            object: receipt
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        return receipt.value as? String ?? ""
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func printAccessibilityTree(for app: XCUIApplication, scenario: String) {
        print("COORDIT_REWARDED_AD_ACCESSIBILITY_TREE_BEGIN:\(scenario)")
        print(app.debugDescription)
        print("COORDIT_REWARDED_AD_ACCESSIBILITY_TREE_END:\(scenario)")
    }
}
#endif
