import XCTest
final class InboxWorkflowTests: XCTestCase {
    func testWebLinkOpensDefaultBrowserAndReturnsToArticle() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch()
        app.tabBars.buttons["피드"].tap()
        let article = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(article.waitForExistence(timeout: 5))
        article.tap()
        app.buttons["open-in-browser"].tap()
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].waitForExistence(timeout: 5))
    }

    func testRoutineReminderOpensRoutineDetailPage() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox", "--uitest-inbox-routine"]
        app.launch()
        app.tabBars.buttons["피드"].tap()
        app.segmentedControls.buttons["루틴 알림"].tap()
        let reminder = app.buttons["inbox-item-fixture-reminder"]
        XCTAssertTrue(reminder.waitForExistence(timeout: 5))
        let completion = app.buttons["inbox-completion-fixture-reminder"]
        XCTAssertEqual(completion.value as? String, "미완료")
        XCTAssertLessThan(completion.frame.midX, reminder.frame.minX)
        completion.tap()
        XCTAssertTrue(app.tabBars.buttons["피드"].isSelected)
        XCTAssertFalse(app.navigationBars["루틴 상세"].exists)
        XCTAssertEqual(completion.value as? String, "완료")
        completion.tap()
        XCTAssertEqual(completion.value as? String, "미완료")
        reminder.tap()
        XCTAssertTrue(app.buttons["알림 연결 확인 완료"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["오늘"].isSelected)
        XCTAssertFalse(app.textFields["루틴 이름"].exists)
        app.buttons["알림 연결 확인 완료"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["루틴 상세"].exists)
        XCTAssertFalse(app.buttons["닫기"].exists)
        app.navigationBars.buttons["오늘"].tap()
        XCTAssertFalse(app.navigationBars["루틴 상세"].exists)
        XCTAssertTrue(app.tabBars.buttons["피드"].isSelected)
        XCTAssertTrue(app.segmentedControls.buttons["루틴 알림"].isSelected)
        XCTAssertTrue(reminder.isHittable)
        app.tabBars.buttons["오늘"].tap()
        let detail = app.buttons["알림 연결 확인 상세 보기"]
        for _ in 0..<8 { if detail.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(detail.isHittable)
        detail.tap()
        XCTAssertTrue(app.navigationBars["루틴 상세"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "루틴 상세 페이지"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.navigationBars.buttons["오늘"].tap()
        app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertEqual(completion.value as? String, "완료")
        reminder.tap()
        XCTAssertTrue(app.buttons["알림 연결 확인 완료 취소"].waitForExistence(timeout: 5))
    }

    func testPullToSyncAcrossTabsAndEmptyFeed() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox", "--uitest-sync"]
        app.launch()
        for tab in ["오늘", "일감", "피드"] {
            app.tabBars.buttons[tab].tap()
            if tab == "오늘" { app.segmentedControls.buttons["타임라인"].tap() }
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85))
            start.press(forDuration: 0.05, thenDragTo: end)
            let status = app.staticTexts["동기화 요청 상태"]
            XCTAssertTrue(status.waitForExistence(timeout: 15), tab)
            XCTAssertTrue(status.label.contains("로컬 폴더"), status.label)
        }
        app.buttons["나중에 읽기만 보기"].tap()
        XCTAssertTrue(app.staticTexts["저장한 항목이 없습니다"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.85)))
        XCTAssertTrue(app.staticTexts["동기화 요청 상태"].exists)
    }

    func testLongPressMenuReadAndSave() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]
        app.launch(); app.tabBars.buttons["피드"].tap()
        let first = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.press(forDuration: 1)
        XCTAssertTrue(app.buttons["링크 복사"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["원문 열기"].exists)
        app.buttons["읽음으로 표시"].tap()
        first.press(forDuration: 1)
        XCTAssertTrue(app.buttons["읽지 않음으로 표시"].waitForExistence(timeout: 3))
        app.buttons["나중에 읽기 저장"].tap()
        app.terminate(); app.launch(); app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        first.press(forDuration: 1)
        XCTAssertTrue(app.buttons["나중에 읽기 해제"].waitForExistence(timeout: 3))
        app.buttons["읽지 않음으로 표시"].tap()
        first.press(forDuration: 1)
        XCTAssertTrue(app.buttons["읽음으로 표시"].waitForExistence(timeout: 3))
        app.buttons["글 열기"].tap()
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].waitForExistence(timeout: 3))
    }

    func testMarkdownAndHTMLReading() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]
        app.launch(); app.tabBars.buttons["피드"].tap()
        app.buttons["inbox-item-fixture-1"].tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["마크다운 제목"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["# 마크다운 제목"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "마크다운 피드 본문"; shot.lifetime = .keepAlways; add(shot)
        for _ in 0..<5 { if app.staticTexts["본문 마지막 문단"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.staticTexts["본문 마지막 문단"].isHittable)
        XCTAssertTrue(app.staticTexts["표 내용"].exists)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["inbox-item-fixture-2"].tap()
        XCTAssertTrue(app.staticTexts["HTML 제목"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["HTML 표"].exists)
        XCTAssertFalse(app.staticTexts["실행됨"].exists)
    }

    func testLargeTextDarkTimeline() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM", "-AppleInterfaceStyle", "Dark"]
        app.launch(); app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(app.buttons["inbox-item-fixture-0"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["구독 관리"].isHittable)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "피드 큰 글자 다크 모드"; shot.lifetime = .keepAlways; add(shot)
    }
    func testReadSaveFilterAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]; app.launch()
        app.tabBars.buttons["피드"].tap()
        let first = app.buttons["inbox-item-fixture-0"]
        XCTAssertTrue(first.waitForExistence(timeout: 5)); first.tap()
        XCTAssertTrue(app.staticTexts["테스트 피드 본문 0"].waitForExistence(timeout: 3))
        app.buttons["나중에 읽기 저장"].tap(); app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["나중에 읽기만 보기"].tap()
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        app.terminate(); app.launch(); app.tabBars.buttons["피드"].tap()
        first.tap(); XCTAssertTrue(app.buttons["나중에 읽기 해제"].waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "피드 글 읽기"; shot.lifetime = .keepAlways; add(shot)
    }
    func testSubscriptionsAndRoutineHistory() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox"]; app.launch()
        app.tabBars.buttons["피드"].tap(); app.buttons["구독 관리"].tap()
        let url = app.textFields["RSS 주소"]; XCTAssertTrue(url.waitForExistence(timeout: 3)); url.tap(); url.typeText("https://example.com/second.xml")
        app.buttons["구독 추가"].tap()
        XCTAssertTrue(app.staticTexts["테스트 구독"].waitForExistence(timeout: 5))
        app.buttons["테스트 구독 구독 삭제"].tap(); app.buttons["구독 삭제"].tap()
        XCTAssertTrue(app.staticTexts["테스트 구독"].waitForNonExistence(timeout: 3))
        app.buttons["닫기"].tap(); app.buttons["루틴 알림"].tap()
        app.buttons["inbox-item-fixture-reminder"].tap()
        XCTAssertTrue(app.staticTexts["예정 시각 기준 기록"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["이 루틴은 삭제되었습니다."].exists)
    }
    func testPositionAndInboxFailureIsolation() {
        continueAfterFailure = false
        let app = XCUIApplication(); let id = UUID().uuidString
        app.launchArguments = ["--uitest-store", id, "--uitest-inbox"]; app.launch()
        app.tabBars.buttons["피드"].tap(); app.scrollViews["피드 목록"].swipeUp()
        let middle = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'inbox-item-fixture-'")).allElementsBoundByIndex.first { $0.isHittable }
        XCTAssertNotNil(middle); let anchor = middle!.identifier
        app.tabBars.buttons["오늘"].tap(); app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(app.buttons[anchor].isHittable)
        app.terminate(); app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-inbox-corrupt"]; app.launch()
        app.tabBars.buttons["피드"].tap()
        XCTAssertTrue(app.staticTexts["피드를 열 수 없습니다"].waitForExistence(timeout: 3))
        app.tabBars.buttons["오늘"].tap(); XCTAssertTrue(app.buttons["설정"].exists)
    }
}
