import XCTest
final class InboxWorkflowTests: XCTestCase {
    func testPanelWidthCanBeDraggedAndSurvivesClosing() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        defer { app.terminate() }
        app.buttons["settings-panel-toggle"].click()
        let handle = app.descendants(matching: .any)["panel-resize-handle"].firstMatch
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        let before = app.windows.firstMatch.frame.width
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: -100, dy: 0)))
        let enlarged = app.windows.firstMatch.frame.width
        XCTAssertGreaterThan(enlarged, before + 70)
        app.buttons["settings-panel-close"].click()
        app.buttons["settings-panel-toggle"].click()
        XCTAssertEqual(app.windows.firstMatch.frame.width, enlarged, accuracy: 2)
    }

    func testPanelFeedKeepsArticleAcrossMainTabsAndPanelSwitches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        defer { app.terminate() }
        app.buttons["settings-panel-toggle"].click()
        let article = app.buttons["inbox-panel-item-fixture-0"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.click()
        let back = app.buttons["panel-feed-back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.buttons["전체"].click()
        app.buttons["all-routines"].click()
        XCTAssertTrue(app.buttons["루틴 추가"].waitForExistence(timeout: 5))
        XCTAssertTrue(back.exists)
        XCTAssertTrue(app.buttons["panel-feed-save"].exists)
        app.popUpButtons["right-panel-content"].click()
        app.menuItems["설정"].click()
        XCTAssertTrue(app.switches["today-cylinder-effect"].waitForExistence(timeout: 5))
        XCTAssertFalse(back.isHittable)
        app.popUpButtons["right-panel-content"].click()
        app.menuItems["피드"].click()
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        app.buttons["settings-panel-close"].click()
        XCTAssertFalse(back.isHittable)
        app.buttons["settings-panel-toggle"].click()
        XCTAssertTrue(back.isHittable)
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].isHittable)
        back.click()
        XCTAssertTrue(article.waitForExistence(timeout: 5))
    }

    func testPanelAndMainFeedShareSavedStateButKeepIndependentArticles() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        defer { app.terminate() }
        app.buttons["settings-panel-toggle"].click()
        app.buttons["inbox-panel-item-fixture-0"].click()
        app.buttons["panel-feed-save"].click()
        app.buttons["피드"].click()
        app.buttons["inbox-item-fixture-0"].click()
        XCTAssertTrue(app.toolbars.buttons["나중에 읽기 해제"].firstMatch.waitForExistence(timeout: 5))
        app.buttons["panel-feed-back"].click()
        app.buttons["inbox-panel-item-fixture-2"].click()
        XCTAssertTrue(app.buttons["panel-feed-back"].exists)
        XCTAssertEqual(app.staticTexts["app-page-stack"].label, "feed → 테스트 글 0")
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].isHittable)
    }

    func testSubscriptionErrorHasOneOwnerWithBothFeedsVisible() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        defer { app.terminate() }
        app.buttons["피드"].click()
        app.buttons["settings-panel-toggle"].click()
        let subscriptions = app.buttons["panel-feed-subscriptions"]
        XCTAssertTrue(subscriptions.waitForExistence(timeout: 5))
        subscriptions.click()
        let address = app.textFields["RSS 주소"]
        XCTAssertTrue(address.waitForExistence(timeout: 5))
        address.click()
        address.typeText("not-a-feed-url")
        app.buttons["구독 추가"].click()
        let alert = app.alerts["구독을 변경하지 못했습니다"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        XCTAssertEqual(app.alerts.count, 1)
        XCTAssertFalse(app.alerts["피드를 저장하지 못했습니다"].exists)
        alert.buttons["확인"].click()
        app.buttons["닫기"].click()
        XCTAssertFalse(app.alerts["피드를 저장하지 못했습니다"].exists)
    }

    func testReturningToFeedAfterWebAndSettings() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        app.buttons["피드"].click()
        let article = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.click()
        // The fixture has a valid link; opening it does not depend on a live
        // Valley page loading successfully or changing its redirect target.
        XCTAssertTrue(app.buttons["open-in-browser"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["open-in-browser"].isEnabled)
        let stack = app.staticTexts["app-page-stack"]
        XCTAssertEqual(stack.label, "feed → 테스트 글 0")
        app.buttons["open-in-browser"].click()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        let articlePath = NSPredicate(format: "label == %@", "feed → 테스트 글 0")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: articlePath, object: stack)], timeout: 5), .completed)
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].waitForExistence(timeout: 5))
        app.buttons["전체"].click()
        app.buttons["Valley"].click()
        XCTAssertTrue(app.buttons["open-in-browser"].waitForExistence(timeout: 5))
        app.buttons["피드"].click()
        for _ in 0..<3 {
            XCTAssertTrue(app.buttons["나중에 읽기 저장"].waitForExistence(timeout: 5))
            app.buttons["전체"].click()
            XCTAssertTrue(app.buttons["open-in-browser"].waitForExistence(timeout: 5))
            app.buttons["오늘"].click()
            app.buttons["설정"].click()
            XCTAssertTrue(app.buttons["settings-panel-close"].waitForExistence(timeout: 5))
            app.buttons["settings-panel-close"].click()
            app.buttons["피드"].click()
        }
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].waitForExistence(timeout: 5))
    }

    func testFeedAndAllNavigationKeepIndependentToolbars() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        app.buttons["피드"].click()
        let article = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.click()
        XCTAssertTrue(app.buttons["나중에 읽기 저장"].waitForExistence(timeout: 5))

        app.buttons["전체"].click()
        app.buttons["all-routines"].click()
        XCTAssertTrue(app.buttons["루틴 추가"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["나중에 읽기 저장"].exists)
        for _ in 0..<3 {
            app.buttons["피드"].click()
            XCTAssertTrue(app.buttons["나중에 읽기 저장"].waitForExistence(timeout: 5))
            XCTAssertFalse(app.buttons["루틴 추가"].exists)
            app.buttons["전체"].click()
            XCTAssertTrue(app.buttons["루틴 추가"].waitForExistence(timeout: 5))
        }
    }

    func testLongArticleScrollsWhenPointerIsOverBody() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        app.buttons["피드"].click()
        let article = app.buttons["inbox-item-fixture-3"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.click()
        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 5))
        let firstParagraph = app.staticTexts["스크롤 테스트 문단 1. 긴 피드 본문을 끝까지 읽을 수 있어야 합니다."]
        XCTAssertTrue(firstParagraph.waitForExistence(timeout: 5))
        let lastParagraph = app.staticTexts["긴 피드 마지막 문단"]
        XCTAssertFalse(lastParagraph.isHittable)
        for _ in 0..<12 {
            webView.scroll(byDeltaX: 0, deltaY: -400)
            if lastParagraph.isHittable { break }
        }
        XCTAssertTrue(lastParagraph.isHittable, "Scrolling over the feed body must reach the end of the article")
        app.buttons["전체"].click()
        app.buttons["피드"].click()
        XCTAssertTrue(lastParagraph.isHittable, "Returning to Feed must preserve the article scroll position")
        XCTAssertTrue(app.buttons["open-in-browser"].isHittable)
    }

    func testAppResourceUsageRemainsVisibleAcrossTabs() {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launch()

        let usage = app.staticTexts["app-resource-usage"]
        XCTAssertTrue(usage.waitForExistence(timeout: 8))
        let measured = NSPredicate(format: "label MATCHES %@", "CPU [0-9]+\\.[0-9]% · 메모리 [0-9]+ MB")
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: measured, object: usage)], timeout: 8), .completed)
        app.buttons["전체"].click()
        XCTAssertTrue(usage.exists)
    }

    func testReadingSurvivesTabSwitches() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        app.buttons["피드"].click()
        let article = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.click()
        let body = app.staticTexts["테스트 피드 본문 0"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        for tab in ["오늘", "일감", "전체", "캘린더"] {
            app.buttons[tab].click()
            XCTAssertFalse(body.isHittable)
            app.buttons["피드"].click()
            XCTAssertTrue(body.waitForExistence(timeout: 5))
            XCTAssertTrue(body.isHittable)
        }
    }

    func testRightClickReadAndSaveActionsPersist() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch(); app.buttons["피드"].click()
        let first = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.rightClick()
        XCTAssertTrue(app.menuItems["링크 복사"].exists)
        XCTAssertTrue(app.menuItems["원문 열기"].exists)
        app.menuItems["읽음으로 표시"].click()
        first.rightClick()
        XCTAssertTrue(app.menuItems["읽지 않음으로 표시"].exists)
        app.menuItems["나중에 읽기 저장"].click()
        app.terminate(); app.launch(); app.buttons["피드"].click()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.rightClick()
        XCTAssertTrue(app.menuItems["나중에 읽기 해제"].exists)
        app.menuItems["읽지 않음으로 표시"].click()
        first.rightClick()
        XCTAssertTrue(app.menuItems["읽음으로 표시"].exists)
        app.menuItems["나중에 읽기 해제"].click()
    }
    func testReadSaveAndRoutineFilter() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]; app.launch()
        app.buttons["피드"].click()
        let first = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.click()
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].waitForExistence(timeout: 3))
        app.buttons["나중에 읽기 저장"].click()
        app.terminate(); app.launch(); app.buttons["피드"].click(); first.click()
        XCTAssertTrue(app.buttons["나중에 읽기 해제"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Mac 피드"; shot.lifetime = .keepAlways; add(shot)
    }
}
