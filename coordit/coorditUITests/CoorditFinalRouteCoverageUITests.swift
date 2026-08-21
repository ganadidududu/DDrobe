#if canImport(XCTest)
import XCTest

final class CoorditFinalRouteCoverageUITests: XCTestCase {
    private let routes = [
        "main01",
        "splash",
        "main04",
        "fitlab-input",
        "fitlab-loading",
        "fitlab-result-top",
        "fitlab-result-bottom",
        "fitlab-history-register",
        "fitlab-history-detail",
        "mypage",
        "mypage-thread-charge",
        "mypage-body",
        "mypage-account",
        "mypage-privacy",
        "mypage-app-settings",
        "mypage-notifications",
        "mypage-profile-edit",
        "mypage-password-change",
        "mypage-logout",
        "mypage-account-deletion",
        "mypage-body-measurements",
        "mypage-privacy-policy",
        "mypage-terms",
        "closet-overview",
        "closet-detail-top",
        "closet-detail-bottom",
        "closet-add-method",
        "closet-add-link",
        "closet-add-photo",
        "closet-add-manual",
        "closet-add-loading",
        "closet-add-result",
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAllFinalRoutesExist() throws {
        continueAfterFailure = true

        for route in routes {
            let app = launchApp(at: route)
            assertScreen(route, in: app)

            if route == "main01" {
                XCTAssertTrue(
                    element("main01-screen", in: app).exists,
                    "The approved Main01 screen must remain in the routed hierarchy."
                )
            }

            app.terminate()
        }
    }

    func testTabSelectionChangesVisibleRoute() throws {
        let app = launchApp(at: "main01")
        assertScreen("main01", in: app)
        XCTAssertTrue(element("main01-screen", in: app).exists)

        let fitLabTab = app.buttons["FIT LAB"]
        XCTAssertTrue(fitLabTab.waitForExistence(timeout: 5))
        fitLabTab.tap()
        assertScreen("fitlab-input", in: app)

        let closetTab = app.buttons["CLOSET"]
        XCTAssertTrue(closetTab.waitForExistence(timeout: 5))
        closetTab.tap()
        assertScreen("closet-overview", in: app)

        let homeTab = app.buttons["HOME"]
        XCTAssertTrue(homeTab.waitForExistence(timeout: 5))
        homeTab.tap()
        assertScreen("main04", in: app)
    }

    func testSplashAndMain04RoutesExist() throws {
        continueAfterFailure = true

        for route in ["splash", "main04"] {
            let app = launchApp(at: route)
            assertScreen(route, in: app)
            app.terminate()
        }
    }

    func testFitLabRootBackReturnsHome() throws {
        let app = launchApp(at: "fitlab-input")
        assertScreen("fitlab-input", in: app)

        let backButton = app.buttons["FIT LAB 뒤로가기"]
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        backButton.tap()

        assertScreen("main04", in: app)
    }

    func testFeatureTitleBarsShareGeometryAndMyPageBackReturnsHome() throws {
        let fitLabApp = launchApp(at: "fitlab-input")
        let fitLabTitleBar = fitLabApp.buttons["FIT LAB 뒤로가기"]
        XCTAssertTrue(fitLabTitleBar.waitForExistence(timeout: 5))
        let fitLabFrame = fitLabTitleBar.frame
        fitLabApp.terminate()

        let closetRoutes = [
            (route: "closet-overview", title: "CLOSET"),
            (route: "closet-detail-bottom", title: "FIT DETAIL"),
            (route: "closet-add-method", title: "ADD CLOTHES")
        ]

        for closetRoute in closetRoutes {
            let closetApp = launchApp(at: closetRoute.route)
            let closetScreen = closetApp.scrollViews["coordit-screen-\(closetRoute.route)"]
            let closetTitleBar = closetScreen.buttons[closetRoute.title]
            XCTAssertTrue(closetTitleBar.waitForExistence(timeout: 5))
            let closetFrame = closetTitleBar.frame

            XCTAssertEqual(fitLabFrame.minX, closetFrame.minX, accuracy: 0.5)
            XCTAssertEqual(fitLabFrame.width, closetFrame.width, accuracy: 0.5)
            XCTAssertEqual(fitLabFrame.height, closetFrame.height, accuracy: 0.5)
            closetApp.terminate()
        }

        let myPageApp = launchApp(at: "mypage")
        let myPageTitleBar = myPageApp.buttons["coordit-settings-back"]
        XCTAssertTrue(myPageTitleBar.waitForExistence(timeout: 5))
        let myPageFrame = myPageTitleBar.frame

        XCTAssertEqual(fitLabFrame.minX, myPageFrame.minX, accuracy: 0.5)
        XCTAssertEqual(fitLabFrame.width, myPageFrame.width, accuracy: 0.5)
        XCTAssertEqual(fitLabFrame.height, myPageFrame.height, accuracy: 0.5)

        myPageTitleBar.tap()
        assertScreen("main04", in: myPageApp)
    }

    private func launchApp(at route: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--coordit-ui-testing",
            "--coordit-start-route",
            route,
        ]
        app.launch()
        return app
    }

    private func assertScreen(
        _ route: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifier = route == "main01" ? "main01-screen" : "coordit-screen-\(route)"
        XCTAssertTrue(
            element(identifier, in: app).waitForExistence(timeout: 5),
            "Missing final route identifier: \(identifier)",
            file: file,
            line: line
        )
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
#endif
