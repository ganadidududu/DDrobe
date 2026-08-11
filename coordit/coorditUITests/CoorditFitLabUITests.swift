#if canImport(XCTest)
import XCTest

final class CoorditFitLabUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testInputShowsThreeMethods() throws {
        let app = launchFitLab()

        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].exists)
        XCTAssertTrue(app.buttons["링크로 불러오기"].exists)
        XCTAssertFalse(app.buttons["갤러리에서 추가"].exists)
        XCTAssertFalse(app.buttons["카메라에서 추가"].exists)
    }

    func testFinalBlockersBlankManualAndNormalizedURLDuplicateMakeZeroWrites() throws {
        var app = launchFitLab()
        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        app.buttons["직접 입력하기"].tap()
        fill(element("fitlab-size-label-row-0", in: app), with: "M")
        fill(element("fitlab-measurement-chest_width-row-0", in: app), with: "56")
        dismissKeyboard(in: app)
        tapWhenReachable("fitlab-manual-continue", in: app)
        XCTAssertTrue(element("fitlab-manual-product-error", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-manual-product-error", in: app).label, "상품명을 입력해 주세요.")
        XCTAssertFalse(element("fitlab-manual-review-ready", in: app).exists)
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        app.terminate()

        app = launchFitLab(fixture: "url-success")
        XCTAssertTrue(app.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        app.buttons["링크로 불러오기"].tap()
        fill(element("fitlab-url-field", in: app), with: "https://shop.example/products/duplicate")
        dismissKeyboard(in: app)
        element("fitlab-url-import", in: app).tap()
        XCTAssertTrue(element("fitlab-url-review", in: app).waitForExistence(timeout: 5))
        replace(scrollIntoView("fitlab-url-size-label-row-1", in: app), with: "ｍ")
        dismissKeyboard(in: app)
        let urlConfirm = element("fitlab-url-confirm", in: app)
        for _ in 0..<16 where !urlConfirm.isHittable { app.swipeUp() }
        XCTAssertTrue(urlConfirm.isHittable)
        urlConfirm.tap()
        XCTAssertTrue(app.staticTexts["사이즈명은 중복될 수 없어요."].waitForExistence(timeout: 3))
        XCTAssertFalse(element("fitlab-url-confirmed", in: app).exists)
        XCTAssertEqual(scrollIntoView("fitlab-url-size-label-row-1", in: app, direction: .down).value as? String, "ｍ")
        XCTAssertEqual(element("fitlab-url-request-ledger", in: app).label, "prefill=1|references=1|product=0|size=0|recommend=0|report=0")
        capture("final-url-normalized-duplicate", app: app)
    }

    func testFinalBlockersOCRCreatesNamedCategorizedDraftAndRoutesToSavableResult() throws {
        let app = launchFitLab(fixture: "ocr-submission-success")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))

        let product = scrollIntoView("fitlab-ocr-product-name", in: app)
        XCTAssertNotEqual(product.value as? String, "픽스처 후드")
        XCTAssertTrue(element("fitlab-ocr-category-picker", in: app).exists)
        fill(product, with: "OCR 리넨 셔츠")
        dismissKeyboard(in: app)
        capture("final-ocr-editable-product-category", app: app)
        let ocrConfirm = element("fitlab-ocr-confirm", in: app)
        for _ in 0..<16 where !ocrConfirm.isHittable { app.swipeUp() }
        XCTAssertTrue(ocrConfirm.isHittable)
        ocrConfirm.tap()
        XCTAssertTrue(element("fitlab-ocr-confirmed", in: app).waitForExistence(timeout: 3))
        tapWhenReachable("fitlab-ocr-continue-to-references", in: app)

        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        element("fitlab-reference-reference-fixture-tshirt", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()
        XCTAssertTrue(element("coordit-screen-fitlab-result-top", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("fitlab-add-history", in: app).exists)
        XCTAssertEqual(element("fitlab-draft-isolation-probe", in: app).label, "source=ocr|category=tshirt|product=OCR 리넨 셔츠|url=nil")
        XCTAssertTrue(element("fitlab-ocr-api-request-ledger", in: app).label.contains("create-product"))
        XCTAssertEqual(element("fitlab-product-request-probe", in: app).label, "name=OCR 리넨 셔츠|category=tshirt")
        capture("final-routed-result-save", app: app)
    }

    func testFinalBlockersDirectHistoryRouteRecoversNewestPersistedSnapshot() throws {
        let namespace = "final-deep-history-\(UUID().uuidString)"
        let arguments = ["--coordit-fitlab-history-namespace", namespace]
        var app = launchFitLab(
            route: "fitlab-result-top",
            fixture: "history-persistence",
            extraArguments: arguments + ["--coordit-fitlab-history-reset"]
        )
        XCTAssertTrue(element("fitlab-add-history", in: app).waitForExistence(timeout: 5))
        element("fitlab-add-history", in: app).tap()
        XCTAssertTrue(element("fitlab-input", in: app).waitForExistence(timeout: 5))
        app.terminate()

        app = launchFitLab(
            route: "fitlab-history-detail",
            fixture: "history-persistence",
            extraArguments: arguments
        )
        XCTAssertTrue(element("fitlab-history-detail", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("fitlab-history-detail-analysis", in: app).label, "analysis-fixture-upper")
        XCTAssertEqual(element("fitlab-history-detail-product", in: app).label, "픽스처 후드")
        capture("final-deep-history-recovery", app: app)
    }

    func testReportCopyComesFromCompletedLLMResponseInsteadOfFallback() throws {
        let app = launchFitLab(fixture: "submission-report-copy")
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(
            element("fitlab-dto-contract-status", in: app).label,
            "CONTRACT_OK url-request url-body size-keys recommendation-idempotency reference product size recommendation-parts result report report-idempotency report-timeout adversarial"
        )
        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()
        XCTAssertTrue(element("fitlab-fixture-result-upper", in: app).waitForExistence(timeout: 8))
        let report = element("fitlab-report-description", in: app)
        XCTAssertTrue(report.waitForExistence(timeout: 3))
        XCTAssertTrue(report.label.contains("M 사이즈는 92점으로 전체 후보 중 가장 안정적인 균형을 보여요."))
        XCTAssertFalse(element("fitlab-report-fallback", in: app).exists)
    }

    func testFitLabSubmissionConsumesOneThreadForAnalysisAndOneForReport() throws {
        let app = launchFitLab(
            fixture: "submission-report-thread-charge",
            extraArguments: ["--coordit-thread-balance", "2"]
        )
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("coordit-thread-balance-probe", in: app).label, "2")

        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()

        XCTAssertTrue(element("fitlab-fixture-result-upper", in: app).waitForExistence(timeout: 8))
        XCTAssertEqual(element("coordit-thread-balance-probe", in: app).label, "0")
        XCTAssertEqual(
            element("fitlab-submission-ledger", in: app).label,
            "references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=1|recommend=1|report=1"
        )
    }

    func testReportGenerationExplainsItsThreadCost() throws {
        let app = launchFitLab(
            fixture: "submission-report-thread-cost-notice",
            extraArguments: ["--coordit-thread-balance", "2"]
        )
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))

        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()

        let notice = element("fitlab-report-thread-cost-notice", in: app)
        XCTAssertTrue(notice.waitForExistence(timeout: 8))
        XCTAssertEqual(notice.label, "상세 리포트 1개 생성에 실타래 1개가 사용돼요.")
        capture("report-thread-cost-notice", app: app)
    }

    func testFitLabSubmissionWithNoThreadRoutesToChargePrompt() throws {
        let app = launchFitLab(
            fixture: "submission-success",
            extraArguments: ["--coordit-thread-balance", "0"]
        )
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("coordit-thread-balance-probe", in: app).label, "0")

        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()

        XCTAssertTrue(element("coordit-screen-mypage-thread-charge", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("coordit-thread-recharge-required-popup", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["실타래를 충전해주세요!"].exists)
        XCTAssertFalse(element("coordit-screen-fitlab-loading", in: app).exists)
        XCTAssertFalse(element("coordit-screen-fitlab-result-top", in: app).exists)
    }

    func testMissingReferenceSelectionCanOpenClosetReferenceSelector() throws {
        let app = launchFitLab(fixture: "submission-success")

        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        let manageReferences = app.buttons["fitlab-manage-references"]
        XCTAssertTrue(manageReferences.waitForExistence(timeout: 5))
        manageReferences.tap()

        XCTAssertTrue(app.navigationBars["기준 의류"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["home-reference-item-oxford"].exists)
        XCTAssertTrue(app.buttons["home-reference-item-denim"].exists)
    }

    func testFinalBlockersVisionRunsOffMainWithHeartbeatAndLateCancellationGuard() throws {
        let app = launchFitLab(fixture: "ocr-vision-threading")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-production-vision-fixture", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-processing", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(waitForLabel("tick", element: element("fitlab-ocr-heartbeat-probe", in: app), timeout: 1))
        XCTAssertTrue(waitForLabel("off-main", element: element("fitlab-ocr-execution-probe", in: app), timeout: 3))
        let cancel = element("fitlab-ocr-cancel-processing", in: app)
        XCTAssertTrue(cancel.exists)
        XCTAssertTrue(cancel.isHittable)
        cancel.tap()
        XCTAssertTrue(element("fitlab-ocr-source-chooser", in: app).waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.2)
        XCTAssertFalse(element("fitlab-ocr-review", in: app).exists)
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
    }

    func testReportFailureStaysOnLoadingUntilARealReportIsReady() throws {
        let app = launchFitLab(fixture: "submission-report-failure")
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()

        XCTAssertTrue(element("coordit-screen-fitlab-loading", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("fitlab-loading-error", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["fitlab-loading-retry"].isHittable)
        XCTAssertFalse(element("coordit-screen-fitlab-result-top", in: app).exists)
    }

    func testReportComparesAllFitScoresWhenItsChartRankingIsUnavailable() throws {
        let app = launchFitLab(fixture: "submission-report-without-chart-scores")
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))

        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()

        XCTAssertTrue(element("fitlab-fixture-result-upper", in: app).waitForExistence(timeout: 8))
        XCTAssertEqual(
            scrollIntoView("fitlab-size-score-M", in: app).label,
            "M 사이즈 92.0점, 추천"
        )
        XCTAssertEqual(
            scrollIntoView("fitlab-size-score-L", in: app).label,
            "L 사이즈 81.0점"
        )
    }

    func testFallbackReportCompletesAnalysisWithDeterministicReport() throws {
        let app = launchFitLab(fixture: "submission-report-fallback")
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        element("fitlab-reference-reference-fixture-hoodie", in: app).tap()
        element("fitlab-submit-analysis", in: app).tap()

        XCTAssertTrue(element("fitlab-fixture-result-upper", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("fitlab-report-description", in: app).waitForExistence(timeout: 3))
        XCTAssertFalse(element("fitlab-loading-error", in: app).exists)
        XCTAssertFalse(element("fitlab-report-fallback", in: app).exists)
    }

    func testF2AsyncSessionAndMigrationIsolation() throws {
        let app = launchFitLab(
            fixture: "history-edge",
            extraArguments: [
                "--coordit-fitlab-history-namespace", "f2-remediation-\(UUID().uuidString)",
                "--coordit-fitlab-history-reset",
            ]
        )
        XCTAssertTrue(element("fitlab-history-run-f2-audit", in: app).waitForExistence(timeout: 5))
        element("fitlab-history-run-f2-audit", in: app).tap()
        let probe = element("fitlab-history-f2-probe", in: app)
        XCTAssertTrue(waitForLabel(
            "save=pass|delete=pass|migration-write=pass|legacy-retained=pass",
            element: probe,
            timeout: 8
        ), "Unexpected F2 probe: \(probe.label)")
    }

    func testF2LateURLAndOCRResponsesCannotMutateExitedDraft() throws {
        let urlApp = launchFitLab(fixture: "url-late-response")
        XCTAssertTrue(urlApp.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        urlApp.buttons["링크로 불러오기"].tap()
        fill(element("fitlab-url-field", in: urlApp), with: "https://shop.example/late")
        dismissKeyboard(in: urlApp)
        element("fitlab-url-import", in: urlApp).tap()
        urlApp.buttons["FIT LAB 뒤로가기"].tap()
        XCTAssertTrue(urlApp.buttons["직접 입력하기"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.3)
        XCTAssertEqual(
            element("fitlab-draft-isolation-probe", in: urlApp).label,
            "source=url|category=hoodie|product=픽스처 후드|url=nil"
        )
        urlApp.terminate()

        let ocrApp = launchFitLab(fixture: "ocr-late-response")
        XCTAssertTrue(ocrApp.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        ocrApp.buttons["사진으로 첨부하기"].tap()
        XCTAssertTrue(element("fitlab-ocr-start-late-response", in: ocrApp).waitForExistence(timeout: 3))
        element("fitlab-ocr-start-late-response", in: ocrApp).tap()
        ocrApp.buttons["FIT LAB 뒤로가기"].tap()
        XCTAssertTrue(ocrApp.buttons["직접 입력하기"].waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 1.3)
        XCTAssertEqual(
            element("fitlab-draft-isolation-probe", in: ocrApp).label,
            "source=ocr|category=hoodie|product=픽스처 후드|url=nil"
        )
    }

    func testURLPrefillRequiresReviewBeforePersistence() throws {
        let app = launchFitLab(fixture: "url-category-race")
        XCTAssertTrue(app.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        app.buttons["링크로 불러오기"].tap()

        let urlField = element("fitlab-url-field", in: app)
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        XCTAssertTrue(element("fitlab-url-kind-picker", in: app).exists)
        tapWhenReachable("fitlab-url-category-picker", in: app)
        app.buttons["셔츠"].tap()
        fill(urlField, with: "  https://shop.example/products/linen-shirt  ")
        dismissKeyboard(in: app)
        element("fitlab-url-import", in: app).tap()

        XCTAssertTrue(element("fitlab-url-review", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["추출 결과 · 저장 전 확인 필요"].exists)
        let productName = scrollIntoView("fitlab-url-product-name", in: app)
        XCTAssertEqual(productName.value as? String, "리넨 셔츠")
        XCTAssertEqual(scrollIntoView("fitlab-url-size-label-row-0", in: app).value as? String, "M")
        XCTAssertEqual(scrollIntoView("fitlab-url-measurement-chest_width-row-0", in: app).value as? String, "56")

        replace(scrollIntoView("fitlab-url-product-name", in: app, direction: .down), with: "수정한 리넨 셔츠")
        replace(scrollIntoView("fitlab-url-measurement-chest_width-row-0", in: app), with: "57.5")
        dismissKeyboard(in: app)
        tapWhenReachable("fitlab-url-category-picker", in: app, direction: .down)
        app.buttons["티셔츠"].tap()

        XCTAssertEqual(element("fitlab-url-selected-reference-count", in: app).label, "선택한 기준 옷 0개")
        XCTAssertEqual(element("fitlab-url-reference-refresh-intent", in: app).label, "tshirt")
        let newCategoryReference = element("fitlab-url-reference-result", in: app)
        XCTAssertTrue(newCategoryReference.waitForExistence(timeout: 3))
        XCTAssertEqual(newCategoryReference.label, "reference-tshirt-new|tshirt")
        let categoryLedger = element("fitlab-url-request-ledger-detail", in: app)
        XCTAssertTrue(categoryLedger.label.contains("references:shirt"))
        XCTAssertTrue(categoryLedger.label.contains("references:tshirt"))
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(newCategoryReference.label, "reference-tshirt-new|tshirt", "The stale shirt response must not replace the newer tshirt references.")
        for _ in 0..<3 { app.swipeDown() }
        Thread.sleep(forTimeInterval: 0.5)
        capture("url-beta-editable-review", app: app)
        XCTAssertEqual(scrollIntoView("fitlab-url-request-ledger", in: app).label, "prefill=1|references=2|product=0|size=0|recommend=0|report=0")

        tapWhenReachable("fitlab-url-confirm", in: app)
        let confirmed = element("fitlab-url-confirmed", in: app)
        XCTAssertTrue(confirmed.waitForExistence(timeout: 3))
        XCTAssertEqual(confirmed.label, "수정한 리넨 셔츠 · M · 가슴 단면 57.5")
        XCTAssertEqual(element("fitlab-url-request-ledger", in: app).label, "prefill=1|references=2|product=0|size=0|recommend=0|report=0")
        capture("url-confirmed-without-persistence", app: app)
    }

    func testURLReviewAcceptsACompatibleLowerReferenceCategory() throws {
        let app = launchFitLab(fixture: "url-compatible-lower-reference")
        app.buttons["링크로 불러오기"].tap()
        app.buttons["하의"].tap()
        capture("url-lower-category-before-import", app: app)
        fill(element("fitlab-url-field", in: app), with: "https://shop.example/products/lower")
        dismissKeyboard(in: app)
        element("fitlab-url-import", in: app).tap()

        XCTAssertTrue(element("fitlab-url-review", in: app).waitForExistence(timeout: 5))

        let reference = element("fitlab-url-reference-result", in: app)
        XCTAssertTrue(reference.waitForExistence(timeout: 3))
        XCTAssertEqual(reference.label, "reference-fixture-jeans|jeans")
        capture("url-lower-category-review", app: app)
    }

    func testURLValidationAndRetry() throws {
        let app = launchFitLab(fixture: "url-server-error")
        XCTAssertTrue(app.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        app.buttons["링크로 불러오기"].tap()

        let urlField = element("fitlab-url-field", in: app)
        XCTAssertTrue(urlField.waitForExistence(timeout: 3))
        for invalid in [
            "ftp://shop.example/item",
            "https://user:secret@shop.example/item",
            "https://user%40evil.example@shop.example/item",
            "https://shop.example/bad path",
            "https://.",
            "https://example..com",
            "https://-example.com",
            "https://example-.com",
            "https://example.com./item",
            "https://exa%07mple.com/item",
        ] {
            replace(urlField, with: invalid)
            dismissKeyboard(in: app)
            element("fitlab-url-import", in: app).tap()
            XCTAssertTrue(app.staticTexts["HTTP 또는 HTTPS 상품 링크를 입력해 주세요."].waitForExistence(timeout: 2))
            XCTAssertEqual(element("fitlab-url-request-ledger", in: app).label, "prefill=0|references=0|product=0|size=0|recommend=0|report=0")
        }

        replace(urlField, with: "https://shop.example/products/retry-shirt")
        dismissKeyboard(in: app)
        element("fitlab-url-import", in: app).tap()
        XCTAssertTrue(element("fitlab-url-error", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(urlField.value as? String, "https://shop.example/products/retry-shirt")
        XCTAssertTrue(app.buttons["다시 시도"].exists)
        XCTAssertTrue(app.buttons["수동 입력으로 전환"].exists)
        XCTAssertTrue(app.buttons["사진 OCR로 전환"].exists)
        XCTAssertEqual(element("fitlab-url-request-ledger", in: app).label, "prefill=1|references=0|product=0|size=0|recommend=0|report=0")
        capture("url-server-error-preserves-input", app: app)

        app.buttons["다시 시도"].tap()
        XCTAssertTrue(element("fitlab-url-review", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("fitlab-url-reference-result", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-url-request-ledger", in: app).label, "prefill=2|references=1|product=0|size=0|recommend=0|report=0")
        XCTAssertEqual(element("fitlab-url-field-preserved", in: app).label, "https://shop.example/products/retry-shirt")
        capture("url-retry-success", app: app)
        app.terminate()

        for allowed in [
            "http://shop.example:8080/item",
            "https://127.0.0.1:8443/item",
            "https://[::1]:8443/item",
            "https://예시.테스트/상품",
        ] {
            let allowedApp = launchFitLab(fixture: "url-success")
            XCTAssertTrue(allowedApp.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
            allowedApp.buttons["링크로 불러오기"].tap()
            let allowedField = element("fitlab-url-field", in: allowedApp)
            fill(allowedField, with: allowed)
            dismissKeyboard(in: allowedApp)
            element("fitlab-url-import", in: allowedApp).tap()
            XCTAssertTrue(element("fitlab-url-review", in: allowedApp).waitForExistence(timeout: 5), "Expected valid URL: \(allowed)")
            XCTAssertTrue(element("fitlab-url-reference-result", in: allowedApp).waitForExistence(timeout: 3))
            XCTAssertEqual(element("fitlab-url-request-ledger", in: allowedApp).label, "prefill=1|references=1|product=0|size=0|recommend=0|report=0")
            allowedApp.terminate()
        }
    }

    func testURLExtractionFailureCanSwitchToPhotoOCR() throws {
        let app = launchFitLab(fixture: "url-server-error")
        XCTAssertTrue(app.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        app.buttons["링크로 불러오기"].tap()
        let urlField = element("fitlab-url-field", in: app)
        replace(urlField, with: "https://shop.example/products/unreadable")
        dismissKeyboard(in: app)
        element("fitlab-url-import", in: app).tap()
        XCTAssertTrue(element("fitlab-url-error", in: app).waitForExistence(timeout: 5))

        element("fitlab-url-switch-to-ocr", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-photo-library", in: app).waitForExistence(timeout: 5))
    }

    func testURLReviewRemainsReachableAtAccessibilityXXXL() throws {
        let app = launchFitLab(
            fixture: "url-success",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )
        XCTAssertTrue(app.buttons["링크로 불러오기"].waitForExistence(timeout: 5))
        app.buttons["링크로 불러오기"].tap()
        fill(element("fitlab-url-field", in: app), with: "https://shop.example/products/accessibility-shirt")
        dismissKeyboard(in: app)
        element("fitlab-url-import", in: app).tap()
        XCTAssertTrue(element("fitlab-url-review", in: app).waitForExistence(timeout: 5))

        let finalMeasurement = scrollIntoView("fitlab-url-measurement-sleeve_length-row-1", in: app)
        XCTAssertEqual(finalMeasurement.value as? String, "63")
        XCTAssertGreaterThan(finalMeasurement.frame.height, 50)
        capture("url-accessibility-xxxl-review", app: app)

        tapWhenReachable("fitlab-url-confirm", in: app)
        XCTAssertTrue(element("fitlab-url-confirmed", in: app).waitForExistence(timeout: 3))
    }

    func testInputStartsWithEmptyHistory() throws {
        let app = launchFitLab(fixture: "empty-history")

        XCTAssertTrue(element("fitlab-history-empty", in: app).waitForExistence(timeout: 5))
    }

    func testSaveRelaunchOpenAndDeleteHistory() throws {
        let namespace = "history-happy-\(UUID().uuidString)"
        let historyArguments = ["--coordit-fitlab-history-namespace", namespace]

        var app = launchFitLab(
            fixture: "history-persistence",
            extraArguments: historyArguments + ["--coordit-fitlab-history-reset"]
        )
        XCTAssertTrue(element("fitlab-history-empty", in: app).waitForExistence(timeout: 5))
        capture("task-8-history-empty", app: app)
        app.terminate()

        app = launchFitLab(
            route: "fitlab-result-top",
            fixture: "history-persistence",
            extraArguments: historyArguments
        )
        XCTAssertTrue(element("fitlab-add-history", in: app).waitForExistence(timeout: 5))
        element("fitlab-add-history", in: app).tap()
        XCTAssertTrue(element("fitlab-input", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("fitlab-history-card-analysis-fixture-upper", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("fitlab-history-count", in: app).label, "1")
        capture("task-8-history-saved-list", app: app)
        app.terminate()

        app = launchFitLab(fixture: "history-persistence", extraArguments: historyArguments)
        let savedCard = element("fitlab-history-card-analysis-fixture-upper", in: app)
        XCTAssertTrue(savedCard.waitForExistence(timeout: 5))
        savedCard.tap()
        XCTAssertTrue(element("fitlab-history-detail", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("fitlab-history-detail-product", in: app).label, "픽스처 후드")
        XCTAssertEqual(element("fitlab-history-detail-analysis", in: app).label, "analysis-fixture-upper")
        capture("task-8-history-detail", app: app)

        element("fitlab-history-delete", in: app).tap()
        XCTAssertTrue(element("fitlab-history-empty", in: app).waitForExistence(timeout: 5))
        XCTAssertEqual(element("fitlab-history-count", in: app).label, "0")
    }

    func testHistoryIsolationDuplicateRetentionAndCorruptRecovery() throws {
        let namespace = "history-edge-\(UUID().uuidString)"
        let app = launchFitLab(
            fixture: "history-edge",
            extraArguments: [
                "--coordit-fitlab-history-namespace", namespace,
                "--coordit-fitlab-history-reset",
            ]
        )
        XCTAssertTrue(element("fitlab-history-empty", in: app).waitForExistence(timeout: 5))

        element("fitlab-history-seed-retention", in: app).tap()
        XCTAssertTrue(waitForLabel(
            "count=50|unique=50|newest=analysis-51|oldest=analysis-2",
            element: element("fitlab-history-edge-probe", in: app),
            timeout: 8
        ))

        element("fitlab-history-switch-user-b", in: app).tap()
        XCTAssertTrue(waitForLabel("user=history-user-b|count=0", element: element("fitlab-history-user-probe", in: app)))
        XCTAssertTrue(element("fitlab-history-empty", in: app).exists)
        element("fitlab-history-switch-user-a", in: app).tap()
        let userAProbe = element("fitlab-history-user-probe", in: app)
        XCTAssertTrue(waitForLabel(
            "user=history-user-a|count=50",
            element: userAProbe,
            timeout: 8
        ), "Unexpected user A probe: \(userAProbe.label)")

        element("fitlab-history-save-duplicate", in: app).tap()
        XCTAssertTrue(waitForLabel(
            "count=50|unique=50|newest=analysis-51|oldest=analysis-2",
            element: element("fitlab-history-edge-probe", in: app),
            timeout: 5
        ))

        element("fitlab-history-run-store-audit", in: app).tap()
        let storeAudit = element("fitlab-history-store-audit", in: app)
        XCTAssertTrue(waitForLabel(
            "path=pass|symlink=pass|atomic=pass|truncated=pass|version=pass|migration=pass|interrupt=pass",
            element: storeAudit,
            timeout: 8
        ), "Unexpected store audit: \(storeAudit.label)")

        element("fitlab-history-run-race-audit", in: app).tap()
        let raceProbe = element("fitlab-history-race-probe", in: app)
        XCTAssertTrue(waitForLabel(
            "load=pass|save=pass|delete=pass",
            element: raceProbe,
            timeout: 8
        ), "Unexpected history race probe: \(raceProbe.label)")

        element("fitlab-history-corrupt", in: app).tap()
        XCTAssertTrue(element("fitlab-history-recovery-notice", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("fitlab-history-empty", in: app).exists)
        XCTAssertEqual(element("fitlab-history-quarantine-count", in: app).label, "1")
        capture("task-8-history-corrupt-notice", app: app)
    }

    func testUpperAndLowerResultsUseAuthoritativeValues() throws {
        let upper = launchFitLab(route: "fitlab-result-top", fixture: "upper-result")
        XCTAssertEqual(element("fitlab-recommended-size", in: upper).label, "M")
        XCTAssertEqual(element("fitlab-total-score", in: upper).label, "92.0")
        XCTAssertTrue(element("fitlab-mannequin-upper", in: upper).exists)
        XCTAssertFalse(element("fitlab-mannequin-lower", in: upper).exists)
        XCTAssertTrue(element("fitlab-overlay-shoulder_width", in: upper).label.contains("여유"))
        XCTAssertTrue(element("fitlab-overlay-chest_width", in: upper).label.contains("타이트"))
        for _ in 0..<3 { upper.swipeDown() }
        settleRendering()
        capture("result-upper-overview", app: upper)
        XCTAssertEqual(scrollIntoView("fitlab-size-score-M", in: upper).label, "M 사이즈 92.0점, 추천")
        XCTAssertEqual(element("fitlab-size-score-M", in: upper).value as? String, "선택됨")
        _ = scrollIntoView("fitlab-difference-chart", in: upper)
        XCTAssertEqual(
            element("fitlab-yarn-trail-shoulder_width", in: upper).value as? String,
            "right|blue"
        )
        XCTAssertEqual(
            element("fitlab-yarn-trail-chest_width", in: upper).value as? String,
            "left|red"
        )
        XCTAssertEqual(
            element("fitlab-yarn-trail-total_length", in: upper).value as? String,
            "center|green"
        )
        XCTAssertEqual(
            element("fitlab-yarn-trail-sleeve_length", in: upper).value as? String,
            "left|green"
        )
        _ = scrollIntoView("fitlab-yarn-trail-sleeve_length", in: upper)
        settleRendering()
        capture("result-upper-m-yarn-chart", app: upper)
        upper.swipeDown()
        settleRendering()
        capture("result-upper-m-yarn-chart-full", app: upper)
        scrollIntoView("fitlab-size-score-L", in: upper, direction: .down).tap()
        XCTAssertEqual(element("fitlab-size-score-L", in: upper).value as? String, "선택됨")
        XCTAssertEqual(element("fitlab-size-score-M", in: upper).value as? String, "선택 안 됨")
        XCTAssertEqual(element("fitlab-recommended-size", in: upper).label, "L")
        XCTAssertEqual(element("fitlab-total-score", in: upper).label, "81")
        XCTAssertTrue(element("fitlab-overlay-shoulder_width", in: upper).label.contains("여유"))
        for key in ["shoulder_width", "chest_width", "total_length", "sleeve_length"] {
            XCTAssertEqual(
                element("fitlab-yarn-trail-\(key)", in: upper).value as? String,
                "right|blue"
            )
        }
        upper.swipeUp()
        settleRendering()
        capture("result-upper-comparison", app: upper)
        upper.swipeUp()
        settleRendering()
        capture("result-upper-analysis", app: upper)
        upper.swipeDown()
        upper.swipeDown()
        _ = scrollIntoView("fitlab-difference-chart", in: upper)
        XCTAssertEqual(
            element("fitlab-measurement-shoulder_width", in: upper).value as? String,
            "베스트 53 cm | 상품 56 cm | 차이 +3 cm | 여유"
        )
        XCTAssertEqual(
            element("fitlab-measurement-chest_width", in: upper).value as? String,
            "베스트 58 cm | 상품 60 cm | 차이 +2 cm | 여유"
        )
        XCTAssertEqual(
            element("fitlab-measurement-total_length", in: upper).value as? String,
            "베스트 68 cm | 상품 70 cm | 차이 +2 cm | 여유"
        )
        XCTAssertEqual(
            element("fitlab-measurement-sleeve_length", in: upper).value as? String,
            "베스트 61 cm | 상품 63 cm | 차이 +2 cm | 여유"
        )
        XCTAssertFalse(element("fitlab-measurement-waist_width", in: upper).exists)
        upper.terminate()

        let lower = launchFitLab(route: "fitlab-result-bottom", fixture: "lower-result")
        XCTAssertEqual(element("fitlab-recommended-size", in: lower).label, "L")
        XCTAssertEqual(element("fitlab-total-score", in: lower).label, "88.0")
        XCTAssertTrue(element("fitlab-mannequin-lower", in: lower).exists)
        XCTAssertFalse(element("fitlab-mannequin-upper", in: lower).exists)
        XCTAssertTrue(element("fitlab-overlay-waist_width", in: lower).label.contains("여유"))
        XCTAssertTrue(element("fitlab-overlay-rise", in: lower).label.contains("타이트"))
        _ = scrollIntoView("fitlab-yarn-trail-outseam", in: lower)
        XCTAssertEqual(
            element("fitlab-yarn-trail-outseam", in: lower).value as? String,
            "right|blue"
        )
        for _ in 0..<3 { lower.swipeDown() }
        settleRendering()
        capture("result-lower-overview", app: lower)
        XCTAssertEqual(scrollIntoView("fitlab-size-score-L", in: lower).label, "L 사이즈 88.0점, 추천")
        lower.swipeUp()
        settleRendering()
        capture("result-lower-comparison", app: lower)
        lower.swipeUp()
        settleRendering()
        capture("result-lower-analysis", app: lower)
        lower.swipeDown()
        lower.swipeDown()
        _ = scrollIntoView("fitlab-difference-chart", in: lower)
        XCTAssertEqual(
            element("fitlab-measurement-waist_width", in: lower).value as? String,
            "베스트 39 cm | 상품 40 cm | 차이 +1 cm | 여유"
        )
        XCTAssertEqual(
            element("fitlab-measurement-hip_width", in: lower).value as? String,
            "베스트 50 cm | 상품 50 cm | 차이 0 cm | 비슷"
        )
        XCTAssertEqual(
            element("fitlab-measurement-rise", in: lower).value as? String,
            "베스트 30 cm | 상품 29 cm | 차이 -1 cm | 타이트"
        )
        XCTAssertEqual(
            element("fitlab-measurement-outseam", in: lower).value as? String,
            "베스트 100 cm | 상품 102 cm | 차이 +2 cm | 여유"
        )
        XCTAssertFalse(element("fitlab-measurement-shoulder_width", in: lower).exists)
    }

    func testNumericSizeLabelsStayReadableInScoreComparison() throws {
        let app = launchFitLab(route: "fitlab-result-bottom", fixture: "size-score-numeric-labels")

        XCTAssertEqual(
            scrollIntoView("fitlab-size-score-M(095)", in: app).label,
            "M(095) 사이즈 72.0점"
        )
        XCTAssertEqual(
            element("fitlab-size-score-L(100)", in: app).label,
            "L(100) 사이즈 88.0점, 추천"
        )
        XCTAssertEqual(
            element("fitlab-size-score-XL(105)", in: app).label,
            "XL(105) 사이즈 79.0점"
        )
        settleRendering()
        capture("size-score-comparison-numeric-labels", app: app)
    }

    func testLongDescriptionAndMissingMeasurementsRemainReachable() throws {
        let app = launchFitLab(route: "fitlab-result-top", fixture: "long-report")
        _ = scrollIntoView("fitlab-difference-chart", in: app)
        XCTAssertEqual(
            element("fitlab-measurement-sleeve_length", in: app).value as? String,
            "비교 데이터 없음"
        )

        let finalAction = element("fitlab-report-final-action", in: app)
        for _ in 0..<16 where !finalAction.exists || !finalAction.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(finalAction.exists, "2,000자 이상의 리포트 마지막 액션이 스크롤로 도달 가능해야 합니다.")
        XCTAssertEqual(finalAction.label, "긴 리포트의 마지막 액션")
        XCTAssertTrue(element("fitlab-report-description", in: app).label.count > 2_000)
        capture("result-long", app: app)
    }

    func testDirectRouteFixtures() throws {
        let expectations = [
            ("fitlab-input", "empty-history", "fitlab-fixture-input-ready", "픽스처 후드 · hoodie"),
            ("fitlab-loading", "submitting", "fitlab-fixture-loading-submitting", "사이즈 생성 중"),
            ("fitlab-result-top", "upper-result", "fitlab-fixture-result-upper", "추천 M · 92.0점"),
            ("fitlab-result-bottom", "lower-result", "fitlab-fixture-result-lower", "추천 L · 88.0점"),
        ]

        for (route, fixture, identifier, expectedValue) in expectations {
            let app = launchFitLab(route: route, fixture: fixture)
            let state = element(identifier, in: app)
            XCTAssertTrue(
                state.waitForExistence(timeout: 5),
                "Expected fixture-backed state \(identifier) for route \(route)."
            )
            XCTAssertEqual(state.label, expectedValue)
            XCTAssertEqual(
                element("fitlab-dto-contract-status", in: app).label,
                "CONTRACT_OK url-request url-body size-keys recommendation-idempotency reference product size recommendation-parts result report report-timeout adversarial"
            )
            app.terminate()
        }

        for route in ["fitlab-history-detail"] {
            let app = launchFitLab(route: route, fixture: "saved-history")
            XCTAssertTrue(element("fitlab-history-detail", in: app).waitForExistence(timeout: 5))
            XCTAssertEqual(
                element("fitlab-dto-contract-status", in: app).label,
                "CONTRACT_OK url-request url-body size-keys recommendation-idempotency reference product size recommendation-parts result report report-timeout adversarial"
            )
            app.terminate()
        }
    }

    func testUnauthenticatedSubmissionShowsLoginRequired() throws {
        let app = launchFitLab(route: "fitlab-input", fixture: "unauthenticated")
        let submit = app.buttons["핏 분석 시작"]
        XCTAssertTrue(submit.waitForExistence(timeout: 5))
        XCTAssertFalse(element("fitlab-login-required", in: app).exists)
        XCTAssertEqual(element("fitlab-fixture-api-request-ledger-count", in: app).label, "0")
        submit.tap()

        XCTAssertTrue(
            element("fitlab-login-required", in: app).waitForExistence(timeout: 5),
            "An unauthenticated submission must render a Korean login-required state."
        )
        XCTAssertTrue(app.staticTexts["핏 분석을 시작하려면 로그인이 필요해요."].exists)
        XCTAssertEqual(element("fitlab-fixture-api-request-ledger-count", in: app).label, "0")

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "unauthenticated-after-submit"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testSubmissionCallsExistingAPIsInOrder() throws {
        let app = launchFitLab(fixture: "submission-success")

        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["비교할 기준 옷을 선택해 주세요"].exists)
        XCTAssertTrue(element("fitlab-similar-reference-notice", in: app).exists)
        XCTAssertFalse(element("fitlab-submit-analysis", in: app).isEnabled)
        capture("task-6-reference-selection", app: app)

        let reference = element("fitlab-reference-reference-fixture-hoodie", in: app)
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        reference.tap()
        XCTAssertEqual(element("fitlab-selected-reference-count", in: app).label, "선택한 기준 옷 1개")
        element("fitlab-submit-analysis", in: app).tap()

        let result = element("fitlab-fixture-result-upper", in: app)
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertEqual(result.label, "추천 M · 92.0점")
        XCTAssertEqual(
            element("fitlab-submission-ledger", in: app).label,
            "references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=1|recommend=1|report=1"
        )
        XCTAssertEqual(
            element("fitlab-submission-ledger-detail", in: app).label,
            "references:hoodie|create-product|create-size:M:attempt|create-size:M:success|create-size:L:attempt|create-size:L:success|recommend|report:analysis-fixture-upper"
        )
        capture("task-6-submission-result", app: app)

        app.terminate()
        let reportApp = launchFitLab(fixture: "submission-report-failure")
        XCTAssertTrue(element("fitlab-reference-selection", in: reportApp).waitForExistence(timeout: 5))
        let reportReference = element("fitlab-reference-reference-fixture-hoodie", in: reportApp)
        XCTAssertTrue(reportReference.waitForExistence(timeout: 5))
        reportReference.tap()
        element("fitlab-submit-analysis", in: reportApp).tap()
        XCTAssertTrue(element("fitlab-loading-error", in: reportApp).waitForExistence(timeout: 8))
        XCTAssertFalse(element("fitlab-fixture-result-upper", in: reportApp).exists)
        XCTAssertEqual(element("fitlab-submission-ledger", in: reportApp).label, "references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=1|recommend=1|report=1")
        element("fitlab-loading-retry", in: reportApp).tap()
        XCTAssertTrue(element("fitlab-fixture-result-upper", in: reportApp).waitForExistence(timeout: 8))
        XCTAssertEqual(element("fitlab-submission-ledger", in: reportApp).label, "references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=1|recommend=1|report=2")
        XCTAssertFalse(element("fitlab-report-fallback", in: reportApp).exists)
        capture("task-6-report-retry-result", app: reportApp)
    }

    func testSubmissionRetryDoesNotDuplicateCompletedWrites() throws {
        let app = launchFitLab(fixture: "submission-size-retry")
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 5))
        let reference = element("fitlab-reference-reference-fixture-hoodie", in: app)
        XCTAssertTrue(reference.waitForExistence(timeout: 5))
        reference.tap()

        element("fitlab-submit-analysis", in: app).tap()
        XCTAssertTrue(element("fitlab-loading-error", in: app).waitForExistence(timeout: 8))
        XCTAssertTrue(element("fitlab-loading-error", in: app).label.contains("L 사이즈 저장"))
        XCTAssertEqual(
            element("fitlab-submission-ledger", in: app).label,
            "references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=0|recommend=0|report=0"
        )
        capture("task-6-size-failure", app: app)

        element("fitlab-loading-retry", in: app).tap()
        XCTAssertTrue(element("fitlab-fixture-result-upper", in: app).waitForExistence(timeout: 8))
        XCTAssertEqual(
            element("fitlab-submission-ledger", in: app).label,
            "references=1|product=1|M-attempts=1|M-success=1|L-attempts=2|L-success=1|recommend=1|report=1"
        )
        XCTAssertEqual(
            element("fitlab-submission-ledger-detail", in: app).label,
            "references:hoodie|create-product|create-size:M:attempt|create-size:M:success|create-size:L:attempt|create-size:L:attempt|create-size:L:success|recommend|report:analysis-fixture-upper"
        )
        capture("task-6-retry-result", app: app)

        XCTAssertFalse(element("fitlab-discard-submission", in: app).exists)
        XCTAssertTrue(element("fitlab-fixture-result-upper", in: app).exists)

        app.terminate()
        let recommendationRaceApp = launchFitLab(fixture: "submission-recommendation-race")
        XCTAssertTrue(element("fitlab-reference-selection", in: recommendationRaceApp).waitForExistence(timeout: 5))
        element("fitlab-reference-reference-fixture-hoodie", in: recommendationRaceApp).tap()
        element("fitlab-submit-analysis", in: recommendationRaceApp).tap()
        XCTAssertTrue(
            waitForLabel("references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=1|recommend=1|report=0", element: element("fitlab-submission-ledger", in: recommendationRaceApp))
        )
        element("fitlab-test-force-discard", in: recommendationRaceApp).tap()
        element("fitlab-test-release-recommendation", in: recommendationRaceApp).tap()
        let recommendationState = element("fitlab-submission-state-probe", in: recommendationRaceApp)
        XCTAssertTrue(
            waitForLabelContaining(
                "checkpoint=empty|recommendation=empty|report=empty",
                element: recommendationState
            ),
            "A recommendation from a discarded generation must not restore result state. Actual: \(recommendationState.label)"
        )
        XCTAssertFalse(element("fitlab-submission-result", in: recommendationRaceApp).exists)

        recommendationRaceApp.terminate()
        let reportRaceApp = launchFitLab(fixture: "submission-report-race")
        XCTAssertTrue(element("fitlab-reference-selection", in: reportRaceApp).waitForExistence(timeout: 5))
        element("fitlab-reference-reference-fixture-hoodie", in: reportRaceApp).tap()
        element("fitlab-submit-analysis", in: reportRaceApp).tap()
        XCTAssertTrue(element("fitlab-loading-error", in: reportRaceApp).waitForExistence(timeout: 8))
        element("fitlab-loading-retry", in: reportRaceApp).tap()
        XCTAssertTrue(
            waitForLabel("references=1|product=1|M-attempts=1|M-success=1|L-attempts=1|L-success=1|recommend=1|report=2", element: element("fitlab-submission-ledger", in: reportRaceApp))
        )
        XCTAssertFalse(
            element("fitlab-discard-submission", in: reportRaceApp).exists,
            "Discard must be unavailable while a report retry is active."
        )
        element("fitlab-test-force-discard", in: reportRaceApp).tap()
        element("fitlab-test-release-report", in: reportRaceApp).tap()
        XCTAssertTrue(
            waitForLabelContaining(
                "checkpoint=empty|recommendation=empty|report=empty",
                element: element("fitlab-submission-state-probe", in: reportRaceApp)
            ),
            "A report from a discarded retry must not restore result state or navigate."
        )
        XCTAssertFalse(element("fitlab-submission-result", in: reportRaceApp).exists)
    }

    func testManualUpperAndLowerDrafts() throws {
        let app = launchFitLab()
        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        capture("manual-input-three-methods", app: app)
        app.buttons["직접 입력하기"].tap()

        XCTAssertTrue(element("fitlab-manual-form", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("fitlab-measurement-shoulder_width-row-0", in: app).exists)
        XCTAssertTrue(element("fitlab-measurement-chest_width-row-0", in: app).exists)
        XCTAssertTrue(element("fitlab-measurement-total_length-row-0", in: app).exists)
        XCTAssertTrue(element("fitlab-measurement-sleeve_length-row-0", in: app).exists)
        XCTAssertFalse(element("fitlab-measurement-waist_width-row-0", in: app).exists)
        capture("manual-upper-form", app: app)

        fill(element("fitlab-product-name", in: app), with: "테스트 셔츠")
        fill(element("fitlab-size-label-row-0", in: app), with: "M")
        fill(element("fitlab-measurement-shoulder_width-row-0", in: app), with: "45.5")
        dismissKeyboard(in: app)
        element("fitlab-add-size-row", in: app).tap()
        fill(element("fitlab-size-label-row-1", in: app), with: "L")
        fill(element("fitlab-measurement-chest_width-row-1", in: app), with: "55")
        dismissKeyboard(in: app)
        tapWhenReachable("fitlab-manual-continue", in: app)

        let upperReview = element("fitlab-manual-review-ready", in: app)
        XCTAssertTrue(upperReview.waitForExistence(timeout: 3))
        XCTAssertTrue(upperReview.label.contains("상의 · 2개 사이즈"))
        capture("manual-upper-review", app: app)
        element("fitlab-manual-edit", in: app).tap()

        tapWhenReachable("fitlab-kind-lower", in: app, direction: .down)
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
        capture("manual-destructive-kind-confirmation", app: app)
        app.alerts.firstMatch.buttons["변경"].tap()
        XCTAssertTrue(element("fitlab-measurement-waist_width-row-0", in: app).waitForExistence(timeout: 2))
        XCTAssertTrue(element("fitlab-measurement-hip_width-row-0", in: app).exists)
        XCTAssertTrue(element("fitlab-measurement-rise-row-0", in: app).exists)
        XCTAssertTrue(element("fitlab-measurement-outseam-row-0", in: app).exists)
        XCTAssertFalse(element("fitlab-measurement-shoulder_width-row-0", in: app).exists)
        capture("manual-lower-form", app: app)

        fill(element("fitlab-product-name", in: app), with: "테스트 팬츠")
        fill(element("fitlab-size-label-row-0", in: app), with: "30")
        fill(element("fitlab-measurement-waist_width-row-0", in: app), with: "39,5")
        dismissKeyboard(in: app)
        element("fitlab-add-size-row", in: app).tap()
        fill(element("fitlab-size-label-row-1", in: app), with: "32")
        fill(element("fitlab-measurement-outseam-row-1", in: app), with: "104")
        dismissKeyboard(in: app)
        tapWhenReachable("fitlab-manual-continue", in: app)

        let lowerReview = element("fitlab-manual-review-ready", in: app)
        XCTAssertTrue(lowerReview.waitForExistence(timeout: 3))
        XCTAssertTrue(lowerReview.label.contains("하의 · 2개 사이즈"))
        capture("manual-lower-valid-review", app: app)
    }

    func testManualValidationRejectsDuplicateAndInvalidRows() throws {
        let app = launchFitLab()
        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        app.buttons["직접 입력하기"].tap()

        fill(element("fitlab-size-label-row-0", in: app), with: " M ")
        fill(element("fitlab-measurement-shoulder_width-row-0", in: app), with: "45,5")
        dismissKeyboard(in: app)
        element("fitlab-add-size-row", in: app).tap()
        fill(element("fitlab-size-label-row-1", in: app), with: "m")
        fill(element("fitlab-measurement-shoulder_width-row-1", in: app), with: "nan")
        fill(element("fitlab-measurement-chest_width-row-1", in: app), with: "infinity")
        fill(element("fitlab-measurement-sleeve_length-row-1", in: app), with: "-1")
        dismissKeyboard(in: app)
        element("fitlab-add-size-row", in: app).tap()
        fill(element("fitlab-size-label-row-2", in: app), with: "L")
        dismissKeyboard(in: app)
        tapWhenReachable("fitlab-manual-continue", in: app)

        XCTAssertTrue(app.staticTexts["사이즈명은 중복될 수 없어요."].waitForExistence(timeout: 2))
        XCTAssertTrue(app.staticTexts["측정값은 0보다 큰 유한한 cm 숫자여야 해요."].exists)
        XCTAssertTrue(app.staticTexts["측정값을 하나 이상 입력해 주세요."].exists)
        XCTAssertFalse(element("fitlab-manual-review-ready", in: app).exists)
        capture("manual-validation-errors", app: app)

        for index in stride(from: 2, through: 0, by: -1) {
            element("fitlab-delete-size-row-\(index)", in: app).tap()
        }
        tapWhenReachable("fitlab-manual-continue", in: app)
        XCTAssertTrue(app.staticTexts["사이즈 행을 하나 이상 추가해 주세요."].waitForExistence(timeout: 2))

        capture("manual-no-row-error", app: app)
    }

    func testManualDestructiveCategoryAndKindChangesRequireConfirmation() throws {
        var app = launchFitLab(fixture: "manual-selected-reference")
        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        app.buttons["직접 입력하기"].tap()

        let shoulder = element("fitlab-measurement-shoulder_width-row-0", in: app)
        XCTAssertTrue(shoulder.waitForExistence(timeout: 3))
        XCTAssertEqual(shoulder.value as? String, "54")
        XCTAssertEqual(element("fitlab-selected-reference-count", in: app).label, "선택한 기준 옷 1개")

        element("fitlab-kind-lower", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
        app.alerts.firstMatch.buttons["취소"].tap()
        XCTAssertTrue(shoulder.exists)
        XCTAssertEqual(shoulder.value as? String, "54")
        XCTAssertEqual(element("fitlab-selected-reference-count", in: app).label, "선택한 기준 옷 1개")

        element("fitlab-kind-lower", in: app).tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
        capture("manual-kind-change-confirmation", app: app)
        app.alerts.firstMatch.buttons["변경"].tap()
        XCTAssertTrue(element("fitlab-measurement-waist_width-row-0", in: app).waitForExistence(timeout: 2))
        XCTAssertFalse(element("fitlab-measurement-shoulder_width-row-0", in: app).exists)
        XCTAssertEqual(element("fitlab-selected-reference-count", in: app).label, "선택한 기준 옷 0개")
        XCTAssertNotEqual(element("fitlab-size-label-row-0", in: app).value as? String, "M")
        app.terminate()

        app = launchFitLab(fixture: "manual-selected-reference")
        XCTAssertTrue(app.buttons["직접 입력하기"].waitForExistence(timeout: 5))
        app.buttons["직접 입력하기"].tap()
        XCTAssertEqual(element("fitlab-current-category", in: app).label, "현재 카테고리 후드")
        XCTAssertEqual(element("fitlab-measurement-shoulder_width-row-0", in: app).value as? String, "54")

        element("fitlab-category-picker", in: app).tap()
        XCTAssertTrue(app.buttons["셔츠"].waitForExistence(timeout: 2))
        app.buttons["셔츠"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
        app.alerts.firstMatch.buttons["취소"].tap()
        XCTAssertEqual(element("fitlab-current-category", in: app).label, "현재 카테고리 후드")
        XCTAssertEqual(element("fitlab-measurement-shoulder_width-row-0", in: app).value as? String, "54")
        XCTAssertEqual(element("fitlab-selected-reference-count", in: app).label, "선택한 기준 옷 1개")

        element("fitlab-category-picker", in: app).tap()
        XCTAssertTrue(app.buttons["셔츠"].waitForExistence(timeout: 2))
        app.buttons["셔츠"].tap()
        XCTAssertTrue(app.alerts.firstMatch.waitForExistence(timeout: 2))
        capture("manual-category-change-confirmation", app: app)
        app.alerts.firstMatch.buttons["변경"].tap()
        XCTAssertEqual(element("fitlab-current-category", in: app).label, "현재 카테고리 셔츠")
        XCTAssertEqual(element("fitlab-selected-reference-count", in: app).label, "선택한 기준 옷 0개")
        XCTAssertNotEqual(element("fitlab-size-label-row-0", in: app).value as? String, "M")
        XCTAssertNotEqual(element("fitlab-measurement-shoulder_width-row-0", in: app).value as? String, "54")
    }

    func testOCRProductionChooserHasNoFixtureControls() throws {
        let app = launchFitLab()
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()

        XCTAssertTrue(element("fitlab-ocr-source-chooser", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("fitlab-ocr-photo-library", in: app).exists)
        XCTAssertTrue(element("fitlab-ocr-camera", in: app).exists)
        XCTAssertFalse(element("fitlab-ocr-simulator-fixture", in: app).exists)
        XCTAssertFalse(app.staticTexts["시뮬레이터 검증"].exists)
        capture("ocr-production-source-chooser", app: app)
    }

    func testOCRFixtureCanBeCorrectedAndConfirmed() throws {
        let app = launchFitLab(fixture: "ocr-upper")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()

        XCTAssertTrue(element("fitlab-ocr-source-chooser", in: app).waitForExistence(timeout: 3))
        element("fitlab-ocr-simulator-fixture", in: app).tap()

        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 5))
        XCTAssertTrue(element("fitlab-ocr-raw-text", in: app).label.contains("SIZE SHOULDER CHEST LENGTH SLEEVE"))
        XCTAssertTrue(element("fitlab-ocr-confidence", in: app).label.contains("신뢰도"))
        XCTAssertEqual(element("fitlab-ocr-size-label-row-0", in: app).value as? String, "M")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, "L")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-0", in: app).value as? String, "999")
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        XCTAssertEqual(element("fitlab-ocr-payload-metadata", in: app).label, "absent")
        capture("ocr-upper-editable-review", app: app)

        fill(scrollIntoView("fitlab-ocr-product-name", in: app, direction: .down), with: "OCR 테스트 셔츠")

        let wrongValue = element("fitlab-ocr-measurement-chest_width-row-0", in: app)
        wrongValue.tap()
        wrongValue.press(forDuration: 1.0)
        let selectAll = app.menuItems["Select All"].exists ? app.menuItems["Select All"] : app.menuItems["전체 선택"]
        selectAll.tap()
        wrongValue.typeText("56")
        dismissKeyboard(in: app)
        tapWhenReachable("fitlab-ocr-confirm", in: app)

        let confirmed = element("fitlab-ocr-confirmed", in: app)
        XCTAssertTrue(confirmed.waitForExistence(timeout: 3))
        XCTAssertTrue(confirmed.label.contains("M 가슴 단면 56"))
        XCTAssertTrue(confirmed.label.contains("원문 포함"))
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        XCTAssertEqual(element("fitlab-ocr-payload-metadata", in: app).label, "absent")
        tapWhenReachable("fitlab-ocr-continue-to-references", in: app)
        XCTAssertTrue(element("fitlab-reference-selection", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-ocr-payload-metadata", in: app).label, "present")
        XCTAssertEqual(
            element("fitlab-ocr-size-request-probe", in: app).label,
            "count=2|label=M|chest=56|text=SIZE SHOULDER CHEST LENGTH SLEEVE\nM 45 999 70 61\nL 47 58 72 63|confidence=0.924"
        )
        capture("ocr-confirmed-corrected", app: app)
    }

    func testOCRCancelDeniedAndUnparseableStates() throws {
        let app = launchFitLab(fixture: "ocr-errors")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()

        element("fitlab-ocr-camera", in: app).tap()
        let unavailable = element("fitlab-ocr-camera-unavailable", in: app)
        let denied = element("fitlab-ocr-camera-denied", in: app)
        XCTAssertTrue(
            unavailable.waitForExistence(timeout: 2) || denied.waitForExistence(timeout: 2),
            "The production camera path must report the simulator's actual capability or authorization state"
        )
        capture("ocr-camera-production-state", app: app)

        element("fitlab-ocr-reopen-chooser", in: app).tap()
        element("fitlab-ocr-simulate-unavailable", in: app).tap()
        XCTAssertTrue(unavailable.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["사진에서 선택"].exists)
        XCTAssertTrue(app.buttons["수동 입력으로 전환"].exists)
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-camera-unavailable", app: app)

        element("fitlab-ocr-reopen-chooser", in: app).tap()
        element("fitlab-ocr-simulate-unparseable", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["표를 완전히 읽지 못했어요. 원문을 보며 값을 직접 채워 주세요."].exists)
        XCTAssertTrue(element("fitlab-ocr-raw-text", in: app).label.contains("배송 무료"))
        XCTAssertTrue(element("fitlab-ocr-size-label-row-0", in: app).exists)
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-unparseable-editable", app: app)

        element("fitlab-ocr-recapture", in: app).tap()
        element("fitlab-ocr-camera-delegate-cancel", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(element("fitlab-ocr-raw-text", in: app).label.contains("배송 무료"))
        XCTAssertEqual(
            element("fitlab-ocr-camera-cancellation-probe", in: app).label,
            "delegate-cancelled:nil-image"
        )
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-production-camera-delegate-cancel-preserves-draft", app: app)
    }

    func testOCRProductionCameraDelegateCancellationPreservesDraft() throws {
        let app = launchFitLab(fixture: "ocr-errors")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulate-unparseable", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        let rawTextBeforeCancellation = element("fitlab-ocr-raw-text", in: app).label

        element("fitlab-ocr-recapture", in: app).tap()
        element("fitlab-ocr-camera-delegate-cancel", in: app).tap()

        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-ocr-raw-text", in: app).label, rawTextBeforeCancellation)
        XCTAssertEqual(
            element("fitlab-ocr-camera-cancellation-probe", in: app).label,
            "delegate-cancelled:nil-image"
        )
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-production-camera-wrapper-cancellation", app: app)
    }

    func testOCRLowerFixtureMapsAliasesAndTwoRows() throws {
        let app = launchFitLab(fixture: "ocr-lower")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()

        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-ocr-size-label-row-0", in: app).value as? String, "30")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, "32")
        XCTAssertEqual(element("fitlab-ocr-measurement-waist_width-row-0", in: app).value as? String, "39")
        XCTAssertEqual(element("fitlab-ocr-measurement-hip_width-row-1", in: app).value as? String, "52")
        XCTAssertEqual(element("fitlab-ocr-measurement-rise-row-1", in: app).value as? String, "30")
        XCTAssertEqual(element("fitlab-ocr-measurement-outseam-row-1", in: app).value as? String, "103")
        XCTAssertFalse(element("fitlab-ocr-measurement-chest_width-row-0", in: app).exists)
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-lower-two-rows", app: app)
    }

    func testOCRProductionVisionRecognizesRenderedChartImage() throws {
        let app = launchFitLab(fixture: "ocr-vision-production")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-production-vision-fixture", in: app).tap()

        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 15))
        XCTAssertTrue(element("fitlab-ocr-raw-text", in: app).label.localizedCaseInsensitiveContains("SIZE"))
        XCTAssertEqual(element("fitlab-ocr-size-label-row-0", in: app).value as? String, "M")
        XCTAssertEqual(element("fitlab-ocr-measurement-shoulder_width-row-0", in: app).value as? String, "45")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-0", in: app).value as? String, "56")
        XCTAssertEqual(element("fitlab-ocr-measurement-total_length-row-0", in: app).value as? String, "70")
        XCTAssertEqual(element("fitlab-ocr-measurement-sleeve_length-row-0", in: app).value as? String, "61")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, "L")
        XCTAssertEqual(element("fitlab-ocr-measurement-shoulder_width-row-1", in: app).value as? String, "47")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-1", in: app).value as? String, "58")
        XCTAssertEqual(element("fitlab-ocr-measurement-total_length-row-1", in: app).value as? String, "72")
        XCTAssertEqual(element("fitlab-ocr-measurement-sleeve_length-row-1", in: app).value as? String, "63")
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-production-vision-rendered-chart", app: app)
    }

    func testOCRParserHandlesDuplicateAliasesJitterAndMalformedCells() throws {
        var app = launchFitLab(fixture: "ocr-parser-upper-adversarial")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-ocr-size-label-row-0", in: app).value as? String, "M")
        XCTAssertEqual(element("fitlab-ocr-measurement-shoulder_width-row-0", in: app).value as? String, "45")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-0", in: app).value as? String, "56")
        XCTAssertEqual(element("fitlab-ocr-measurement-total_length-row-0", in: app).value as? String, "70")
        XCTAssertEqual(element("fitlab-ocr-measurement-sleeve_length-row-0", in: app).value as? String, "61")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, "L")
        XCTAssertEqual(element("fitlab-ocr-measurement-shoulder_width-row-1", in: app).value as? String, "47")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-1", in: app).value as? String, "58")
        XCTAssertEqual(element("fitlab-ocr-measurement-total_length-row-1", in: app).value as? String, "72")
        XCTAssertEqual(element("fitlab-ocr-measurement-sleeve_length-row-1", in: app).value as? String, "63")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-2", in: app).value as? String, "XL")
        XCTAssertEqual(element("fitlab-ocr-measurement-shoulder_width-row-2", in: app).value as? String, "")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-2", in: app).value as? String, "")
        XCTAssertEqual(element("fitlab-ocr-measurement-total_length-row-2", in: app).value as? String, "74")
        XCTAssertEqual(element("fitlab-ocr-measurement-sleeve_length-row-2", in: app).value as? String, "65")
        app.terminate()

        app = launchFitLab(fixture: "ocr-parser-lower-adversarial")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-ocr-size-label-row-0", in: app).value as? String, "30")
        XCTAssertEqual(element("fitlab-ocr-measurement-waist_width-row-0", in: app).value as? String, "39")
        XCTAssertEqual(element("fitlab-ocr-measurement-hip_width-row-0", in: app).value as? String, "50")
        XCTAssertEqual(element("fitlab-ocr-measurement-rise-row-0", in: app).value as? String, "29")
        XCTAssertEqual(element("fitlab-ocr-measurement-outseam-row-0", in: app).value as? String, "101")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, "32")
        XCTAssertEqual(element("fitlab-ocr-measurement-waist_width-row-1", in: app).value as? String, "41")
        XCTAssertEqual(element("fitlab-ocr-measurement-hip_width-row-1", in: app).value as? String, "52")
        XCTAssertEqual(element("fitlab-ocr-measurement-rise-row-1", in: app).value as? String, "30")
        XCTAssertEqual(element("fitlab-ocr-measurement-outseam-row-1", in: app).value as? String, "103")
        capture("ocr-parser-bilingual-jittered", app: app)
    }

    func testOCRParserPreservesNumericMixedAndFreeSizeLabelsAcrossEveryRow() throws {
        let app = launchFitLab(fixture: "ocr-parser-mixed-labels")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()

        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))
        XCTAssertEqual(element("fitlab-ocr-size-label-row-0", in: app).value as? String, "85")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, "W32")
        XCTAssertEqual(element("fitlab-ocr-size-label-row-2", in: app).value as? String, "FREE")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-0", in: app).value as? String, "50")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-1", in: app).value as? String, "53")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-2", in: app).value as? String, "56")
    }

    func testOCRValidationRejectsDuplicateAndInvalidRows() throws {
        let app = launchFitLab(fixture: "ocr-validation-invalid")
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))

        XCTAssertEqual(element("fitlab-ocr-size-label-row-1", in: app).value as? String, " m ")
        XCTAssertEqual(element("fitlab-ocr-measurement-shoulder_width-row-0", in: app).value as? String, "-1")
        XCTAssertEqual(element("fitlab-ocr-measurement-chest_width-row-1", in: app).value as? String, "nan")
        fill(scrollIntoView("fitlab-ocr-product-name", in: app, direction: .down), with: "OCR 검증 셔츠")
        tapWhenReachable("fitlab-ocr-confirm", in: app)

        XCTAssertTrue(app.staticTexts["사이즈명은 중복될 수 없어요."].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["측정값은 0보다 큰 유한한 cm 숫자여야 해요."].exists)
        XCTAssertTrue(app.staticTexts["표시된 항목을 확인해 주세요."].exists)
        XCTAssertFalse(element("fitlab-ocr-confirmed", in: app).exists)
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-validation-errors", app: app)
    }

    func testOCRCameraPermissionDenialUsesRealAuthorizationState() throws {
        let app = configuredFitLabApp(
            fixture: "ocr-errors",
            extraArguments: ["--coordit-ocr-force-camera-available"]
        )
        app.resetAuthorizationStatus(for: .camera)
        app.launch()
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-camera", in: app).tap()

        let appAlert = app.alerts.firstMatch
        let springboardAlert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        let permissionAlert = appAlert.waitForExistence(timeout: 1) ? appAlert : springboardAlert
        if permissionAlert.waitForExistence(timeout: 3) {
            let denialTitles = ["Don’t Allow", "허용 안 함", "허용하지 않음"]
            let deny = denialTitles.lazy
                .map { permissionAlert.buttons[$0] }
                .first(where: \.exists) ?? permissionAlert.buttons.firstMatch
            XCTAssertTrue(deny.waitForExistence(timeout: 2))
            deny.tap()
        }
        XCTAssertTrue(element("fitlab-ocr-camera-denied", in: app).waitForExistence(timeout: 5))
        let authorizationProbe = element("fitlab-ocr-camera-authorization-probe", in: app)
        XCTAssertTrue(authorizationProbe.waitForExistence(timeout: 2))
        XCTAssertTrue(
            ["requestAccess=false", "denied"].contains(authorizationProbe.label),
            "Expected the real AVFoundation denial state, got \(authorizationProbe.label)"
        )
        XCTAssertEqual(element("fitlab-ocr-api-request-ledger", in: app).label, "[]")
        capture("ocr-camera-denied-real-authorization", app: app)
    }

    func testOCRAccessibilitySizeKeepsLongDraftReachable() throws {
        var app = launchFitLab(
            fixture: "ocr-lower",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                "--coordit-fitlab-accessibility-xxxl",
            ]
        )
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        element("fitlab-ocr-simulator-fixture", in: app).tap()
        XCTAssertTrue(element("fitlab-ocr-review", in: app).waitForExistence(timeout: 3))

        let finalField = element("fitlab-ocr-measurement-outseam-row-1", in: app)
        for _ in 0..<12 where !finalField.exists || !finalField.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(finalField.exists)
        XCTAssertEqual(finalField.value as? String, "103")
        capture("ocr-accessibility-long-scroll", app: app)

        fill(scrollIntoView("fitlab-ocr-product-name", in: app, direction: .down), with: "OCR 접근성 팬츠")
        tapWhenReachable("fitlab-ocr-confirm", in: app)
        XCTAssertTrue(element("fitlab-ocr-confirmed", in: app).waitForExistence(timeout: 3))

        app.terminate()
        app = launchFitLab(
            fixture: "ocr-errors",
            extraArguments: [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                "--coordit-fitlab-accessibility-xxxl",
            ]
        )
        XCTAssertTrue(app.buttons["사진으로 첨부하기"].waitForExistence(timeout: 5))
        app.buttons["사진으로 첨부하기"].tap()
        tapWhenReachable("fitlab-ocr-simulate-unavailable", in: app)
        XCTAssertTrue(element("fitlab-ocr-camera-unavailable", in: app).waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["사진에서 선택"].exists)
        XCTAssertTrue(app.buttons["수동 입력으로 전환"].exists)
        XCTAssertGreaterThan(
            app.buttons["사진에서 선택"].frame.height,
            55,
            "The recovery capture must render at accessibility XXXL, not merely receive a launch argument."
        )
        capture("ocr-accessibility-recovery-unavailable", app: app)

        let finalRecoveryAction = app.buttons["다른 방법 보기"]
        for _ in 0..<8 where !finalRecoveryAction.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(finalRecoveryAction.isHittable)
        capture("ocr-accessibility-recovery-unavailable-bottom", app: app)
    }

    private func launchFitLab(
        route: String = "fitlab-input",
        fixture: String? = nil,
        extraArguments: [String] = []
    ) -> XCUIApplication {
        let app = configuredFitLabApp(route: route, fixture: fixture, extraArguments: extraArguments)
        app.launch()
        return app
    }

    private func configuredFitLabApp(
        route: String = "fitlab-input",
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
        return app
    }

    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    private func appButton(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons[label]
    }

    private func waitForLabel(_ label: String, element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.label == label { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return element.label == label
    }

    private func waitForLabelContaining(
        _ fragment: String,
        element: XCUIElement,
        timeout: TimeInterval = 3
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if element.label.contains(fragment) { return true }
            Thread.sleep(forTimeInterval: 0.05)
        } while Date() < deadline
        return element.label.contains(fragment)
    }

    private func fill(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing field \(field)")
        makeHittable(field)
        XCTAssertTrue(field.isHittable, "Field is not reachable for typing: \(field)")
        focus(field)
        field.typeText(value)
    }

    private func replace(_ field: XCUIElement, with value: String) {
        XCTAssertTrue(field.waitForExistence(timeout: 3), "Missing field \(field)")
        makeHittable(field)
        XCTAssertTrue(field.isHittable, "Field is not reachable for replacement: \(field)")
        focus(field)
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        field.typeText(value)
    }

    private func dismissKeyboard(in app: XCUIApplication) {
        if app.keyboards.buttons["완료"].exists {
            app.keyboards.buttons["완료"].tap()
        } else if app.buttons["완료"].exists {
            app.buttons["완료"].tap()
        } else if app.keyboards.firstMatch.exists {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.08)).tap()
        }
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func settleRendering() {
        let settled = expectation(description: "rendering settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { settled.fulfill() }
        wait(for: [settled], timeout: 2)
    }

    private enum ScrollDirection {
        case up
        case down
    }

    private func tapWhenReachable(
        _ identifier: String,
        in app: XCUIApplication,
        direction: ScrollDirection = .up
    ) {
        let target = element(identifier, in: app)
        if !target.isHittable {
            dismissKeyboard(in: app)
        }
        for _ in 0..<10 where !target.exists || !target.isHittable {
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Missing reachable element \(identifier)")
        target.tap()
    }

    private func scrollIntoView(
        _ identifier: String,
        in app: XCUIApplication,
        direction: ScrollDirection = .up
    ) -> XCUIElement {
        let target = element(identifier, in: app)
        if !target.isHittable {
            dismissKeyboard(in: app)
        }
        for _ in 0..<12 where !target.exists || !target.isHittable {
            switch direction {
            case .up: app.swipeUp()
            case .down: app.swipeDown()
            }
        }
        XCTAssertTrue(target.exists && target.isHittable, "Missing scrollable element \(identifier)")
        return target
    }

    private func makeHittable(_ field: XCUIElement) {
        let app = XCUIApplication()
        let window = app.windows.firstMatch.frame
        let top = window.minY + 210
        let bottom = window.maxY - 150
        let initialFrame = field.frame
        if field.isHittable, initialFrame.minY >= top, initialFrame.maxY <= bottom {
            return
        }
        if app.keyboards.firstMatch.exists {
            dismissKeyboard(in: app)
            _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 1)
        }
        for _ in 0..<12 {
            let frame = field.frame
            if field.isHittable, frame.minY >= top, frame.maxY <= bottom {
                return
            }
            if frame.maxY > bottom {
                app.swipeUp()
            } else if frame.minY < top {
                app.swipeDown()
            } else {
                app.swipeUp()
            }
        }
    }

    private func focus(_ field: XCUIElement) {
        let app = XCUIApplication()
        let focusedField = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == %@ AND hasKeyboardFocus == 1", field.identifier)
        ).firstMatch

        for attempt in 0..<3 {
            makeHittable(field)
            XCTAssertTrue(field.isHittable, "Field is not reachable for focus: \(field)")
            field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()

            if focusedField.waitForExistence(timeout: 1) {
                return
            }

            if attempt < 2, app.keyboards.firstMatch.exists {
                dismissKeyboard(in: app)
                _ = app.keyboards.firstMatch.waitForNonExistence(timeout: 1)
            }
        }

        XCTFail("Field did not acquire keyboard focus: \(field)")
    }
}
#endif
