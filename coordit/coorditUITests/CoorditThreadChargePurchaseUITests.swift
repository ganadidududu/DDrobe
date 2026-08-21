#if canImport(XCTest)
import XCTest

final class CoorditThreadChargePurchaseUITests: XCTestCase {
    private var runningApp: XCUIApplication?

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        runningApp?.terminate()
        runningApp = nil
    }

    func testStoreKitConfigurationContainsOnlyThreeConsumables() throws {
        let bundle = Bundle(for: Self.self)
        let configurationURL = try XCTUnwrap(
            bundle.url(forResource: "CoorditThreadProducts", withExtension: "storekit"),
            "The StoreKit configuration must be test-only and bundled with coorditUITests"
        )
        let data = try Data(contentsOf: configurationURL)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let products = try XCTUnwrap(object["products"] as? [[String: Any]])
        let productIDs = Set(products.compactMap { $0["productID"] as? String })
        let productTypes = Set(products.compactMap { $0["type"] as? String })

        XCTAssertEqual(
            productIDs,
            [
                "com.inseong.coordit.thread.5",
                "com.inseong.coordit.thread.10",
                "com.inseong.coordit.thread.20",
            ]
        )
        XCTAssertEqual(productTypes, ["Consumable"])
    }

    func testVerifiedPack10PostsJWSRefreshesBalanceThenFinishesOnce() throws {
        let app = launchChargeScreen(readiness: "enabled", purchaseScenario: "credited", balance: 36)

        XCTAssertTrue(
            app.staticTexts["coordit-thread-charge-pack-10-title"]
                .waitForExistence(timeout: 5),
            "The active package title must come from the StoreKit product"
        )
        XCTAssertEqual(
            app.staticTexts["coordit-thread-charge-pack-10-title"].label,
            "StoreKit 실타래 10개"
        )
        XCTAssertEqual(
            app.staticTexts["coordit-thread-charge-pack-10-price"].label,
            "₩2,500"
        )
        attachScreenshot(named: "storekit-products-ready", from: app)

        app.buttons["coordit-thread-charge-pack-10"].tap()

        XCTAssertTrue(app.staticTexts["46 실타래"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["실타래 10개를 충전했어요."]
                .waitForExistence(timeout: 5)
        )

        let receipt = waitForReceipt(containing: "fixture-finish:credited-10:count=1", in: app)
        XCTAssertEqual(occurrences(of: "app-account-token:present", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "backend-post:jws-nonempty", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "backend-response:201:credited", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "balance-refresh:46", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "fixture-finish:credited-10:", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "fixture-finish:credited-10:count=1", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "fixture-finish:credited-10:count=2", in: receipt), 0)
        assertEventOrder(
            [
                "backend-post:jws-nonempty",
                "backend-response:201:credited",
                "balance-refresh:46",
                "fixture-finish:credited-10:count=1",
            ],
            in: receipt
        )
        attachScreenshot(named: "storekit-credited", from: app)
    }

    func testUnfinishedDuplicateReprocessesWithoutSecondBalanceDeltaAndFinishes() throws {
        let app = launchChargeScreen(readiness: "enabled", purchaseScenario: "already_credited", balance: 46)

        XCTAssertTrue(app.staticTexts["46 실타래"].waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.staticTexts["이미 반영된 구매를 확인했어요."]
                .waitForExistence(timeout: 5)
        )

        let receipt = waitForReceipt(containing: "fixture-finish:unfinished-10:count=1", in: app)
        XCTAssertEqual(occurrences(of: "backend-post:jws-nonempty", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "backend-response:200:already_credited", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "balance-refresh:46", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "fixture-finish:unfinished-10:", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "fixture-finish:unfinished-10:count=1", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "fixture-finish:unfinished-10:count=2", in: receipt), 0)
        XCTAssertFalse(receipt.contains("local-credit"), "The client must never grant threads locally")
        assertEventOrder(
            [
                "unfinished:unfinished-10",
                "backend-post:jws-nonempty",
                "backend-response:200:already_credited",
                "balance-refresh:46",
                "fixture-finish:unfinished-10:count=1",
            ],
            in: receipt
        )
        attachScreenshot(named: "storekit-already-credited", from: app)
    }

    func testCancelledPurchaseDoesNotPostFinishOrCredit() throws {
        let app = launchChargeScreen(readiness: "enabled", purchaseScenario: "cancelled", balance: 36)

        let pack = app.buttons["coordit-thread-charge-pack-5"]
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        pack.tap()

        XCTAssertTrue(app.staticTexts["구매를 취소했어요."].waitForExistence(timeout: 5))
        let receipt = waitForReceipt(containing: "purchase-result:cancelled", in: app)
        XCTAssertEqual(occurrences(of: "backend-post:", in: receipt), 0)
        XCTAssertEqual(occurrences(of: "fixture-finish:", in: receipt), 0)
        XCTAssertEqual(app.staticTexts["36 실타래"].label, "36 실타래")
        XCTAssertTrue(pack.isEnabled, "Cancellation must leave the purchase row retryable")
        attachScreenshot(named: "storekit-cancelled", from: app)
    }

    func testPendingPurchaseDoesNotPostFinishOrCredit() throws {
        let app = launchChargeScreen(readiness: "enabled", purchaseScenario: "pending", balance: 36)

        let pack = app.buttons["coordit-thread-charge-pack-5"]
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        pack.tap()

        XCTAssertTrue(
            app.staticTexts["구매 승인을 기다리고 있어요. 승인 후 자동으로 반영돼요."]
                .waitForExistence(timeout: 5)
        )
        let receipt = waitForReceipt(containing: "purchase-result:pending", in: app)
        XCTAssertEqual(occurrences(of: "backend-post:", in: receipt), 0)
        XCTAssertEqual(occurrences(of: "fixture-finish:", in: receipt), 0)
        XCTAssertEqual(app.staticTexts["36 실타래"].label, "36 실타래")
        XCTAssertTrue(pack.isEnabled, "Pending must leave the purchase row retryable")
        attachScreenshot(named: "storekit-pending", from: app)
    }

    func testUnverifiedPurchaseDoesNotPostFinishOrCredit() throws {
        let app = launchChargeScreen(readiness: "enabled", purchaseScenario: "unverified", balance: 36)

        let pack = app.buttons["coordit-thread-charge-pack-20"]
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        pack.tap()

        XCTAssertTrue(
            app.staticTexts["구매 정보를 확인할 수 없어요."]
                .waitForExistence(timeout: 5)
        )
        let receipt = waitForReceipt(containing: "purchase-result:unverified", in: app)
        XCTAssertEqual(occurrences(of: "backend-post:", in: receipt), 0)
        XCTAssertEqual(occurrences(of: "fixture-finish:", in: receipt), 0)
        XCTAssertEqual(app.staticTexts["36 실타래"].label, "36 실타래")
        XCTAssertTrue(pack.isEnabled, "Unverified results must leave the purchase row retryable")
        attachScreenshot(named: "storekit-unverified", from: app)
    }

    func testBackendErrorPostsOnceButDoesNotRefreshFinishOrCredit() throws {
        let app = launchChargeScreen(readiness: "enabled", purchaseScenario: "backend_error", balance: 36)

        let pack = app.buttons["coordit-thread-charge-pack-10"]
        XCTAssertTrue(pack.waitForExistence(timeout: 5))
        pack.tap()

        XCTAssertTrue(
            app.staticTexts["결제 서버에 연결할 수 없어요."]
                .waitForExistence(timeout: 5)
        )
        let receipt = waitForReceipt(containing: "backend-post:jws-nonempty", in: app)
        XCTAssertEqual(occurrences(of: "backend-post:jws-nonempty", in: receipt), 1)
        XCTAssertEqual(occurrences(of: "backend-response:", in: receipt), 0)
        XCTAssertEqual(occurrences(of: "balance-refresh:", in: receipt), 0)
        XCTAssertEqual(occurrences(of: "fixture-finish:", in: receipt), 0)
        XCTAssertEqual(app.staticTexts["36 실타래"].label, "36 실타래")
        XCTAssertTrue(pack.isEnabled, "Backend failures must leave the purchase row retryable")
        attachScreenshot(named: "storekit-backend-error", from: app)
    }

    func testChargeControlsRemainDisabledWhenServerReadinessIsFalse() throws {
        let app = launchChargeScreen(readiness: "false")

        let balance = app.staticTexts["36 실타래"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "Missing initial thread balance")
        XCTAssertTrue(
            app.staticTexts["충전 기능은 아직 준비 중이에요."]
                .waitForExistence(timeout: 5),
            "Missing server-readiness unavailable message"
        )
        let retryButton = app.buttons["coordit-thread-charge-readiness-retry"]
        XCTAssertTrue(
            retryButton.waitForExistence(timeout: 5),
            "Missing readiness retry action"
        )
        XCTAssertGreaterThanOrEqual(retryButton.frame.width, 44)
        XCTAssertGreaterThanOrEqual(retryButton.frame.height, 44)

        assertControlsCannotStartMonetization(in: app, balance: balance)
        attachScreenshot(named: "storekit-readiness-disabled", from: app)
    }

    func testChargeControlsRemainDisabledWhenReadinessRequestIsUnavailable() throws {
        let app = launchChargeScreen(readiness: "unavailable")

        let balance = app.staticTexts["36 실타래"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "Missing initial thread balance")
        XCTAssertTrue(
            app.staticTexts["충전 기능을 확인할 수 없어요. 다시 시도해 주세요."]
                .waitForExistence(timeout: 5),
            "Missing retryable readiness error"
        )
        XCTAssertTrue(
            app.buttons["coordit-thread-charge-readiness-retry"].waitForExistence(timeout: 5),
            "Missing readiness retry action"
        )

        assertControlsCannotStartMonetization(in: app, balance: balance)
    }

    func testChargeControlsFailClosedWhenReadinessPayloadIsMalformed() throws {
        let app = launchChargeScreen(readiness: "malformed")

        let balance = app.staticTexts["36 실타래"]
        XCTAssertTrue(balance.waitForExistence(timeout: 5), "Missing initial thread balance")
        XCTAssertTrue(
            app.staticTexts["충전 기능을 확인할 수 없어요. 다시 시도해 주세요."]
                .waitForExistence(timeout: 5),
            "Malformed readiness must show retryable unavailable message"
        )

        assertControlsCannotStartMonetization(in: app, balance: balance)
    }

    private func assertControlsCannotStartMonetization(
        in app: XCUIApplication,
        balance: XCUIElement
    ) {
        let identifiers = [
            "coordit-thread-charge-ad-cta",
            "coordit-thread-charge-pack-5",
            "coordit-thread-charge-pack-10",
            "coordit-thread-charge-pack-20",
        ]

        for identifier in identifiers {
            let control = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            XCTAssertTrue(control.waitForExistence(timeout: 5), "Missing charge control: \(identifier)")
            XCTAssertFalse(control.isEnabled, "Charge control must be disabled: \(identifier)")
            if control.isHittable {
                control.tap()
            }
        }

        XCTAssertEqual(balance.label, "36 실타래", "Readiness failure must not mutate thread balance")
        XCTAssertFalse(app.alerts.firstMatch.exists, "Readiness failure must not present provider UI")
    }

    private func launchChargeScreen(
        readiness: String,
        purchaseScenario: String? = nil,
        balance: Int = 36
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-ui-testing-authenticated",
            "--coordit-ui-testing-user-id",
            "00000000-0000-4000-8000-000000000010",
            "--coordit-thread-balance",
            String(balance),
            "--coordit-monetization-readiness",
            readiness,
            "--coordit-start-route",
            "mypage-thread-charge",
        ]
        if let purchaseScenario {
            app.launchArguments += ["--coordit-storekit-fixture", purchaseScenario]
        }
        app.launch()
        runningApp = app
        XCTAssertTrue(
            app.descendants(matching: .any)
                .matching(identifier: "coordit-screen-mypage-thread-charge")
                .firstMatch
                .waitForExistence(timeout: 5),
            "Charge screen did not load"
        )
        if readiness == "unavailable" || readiness == "malformed" {
            print("COORDIT_ACCESSIBILITY_TREE_BEGIN\n\(app.debugDescription)\nCOORDIT_ACCESSIBILITY_TREE_END")
        }
        return app
    }

    private func waitForReceipt(containing event: String, in app: XCUIApplication) -> String {
        let receipt = app.descendants(matching: .any)
            .matching(identifier: "coordit-thread-purchase-fixture-receipt")
            .firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5), "Missing sanitized purchase receipt")
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", event),
            object: receipt
        )
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 5), .completed)
        let value = receipt.value as? String ?? ""
        print("COORDIT_PURCHASE_RECEIPT:\(value)")
        return value
    }

    private func occurrences(of needle: String, in haystack: String) -> Int {
        haystack.components(separatedBy: needle).count - 1
    }

    private func assertEventOrder(_ events: [String], in receipt: String) {
        var lowerBound = receipt.startIndex
        for event in events {
            guard let range = receipt.range(of: event, range: lowerBound..<receipt.endIndex) else {
                XCTFail("Missing ordered purchase event: \(event) in \(receipt)")
                return
            }
            lowerBound = range.upperBound
        }
    }

    private func attachScreenshot(named name: String, from app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
#endif
