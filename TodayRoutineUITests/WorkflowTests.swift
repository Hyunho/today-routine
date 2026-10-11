import XCTest
final class WorkflowTests: XCTestCase {
    func testTimeGridScrollsToCurrentTimeOnEveryVisit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "-today.scheduleView", "시간 블록"]
        app.launch()
        let line = app.descendants(matching: .any).matching(identifier: "today-current-time").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(line.frame.midY, window.minY + 80)
        XCTAssertLessThan(line.frame.midY, window.maxY - 100)
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }
        app.tabBars.buttons["오늘"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(line.frame.midY, window.minY + 80)
        XCTAssertLessThan(line.frame.midY, window.maxY - 100)
    }
    func testTodayListScrollsToCurrentTimeOnEveryVisit() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-pending-stack", "-today.scheduleView", "목록"]
        app.launch()
        let line = app.descendants(matching: .any).matching(identifier: "today-current-time").firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        let window = app.windows.firstMatch.frame
        XCTAssertGreaterThan(line.frame.midY, window.minY + 80)
        XCTAssertLessThan(line.frame.midY, window.maxY - 100)
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }
        app.tabBars.buttons["오늘"].tap()
        XCTAssertTrue(line.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(line.frame.midY, window.minY + 80)
        XCTAssertLessThan(line.frame.midY, window.maxY - 100)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "오늘 타임라인"; shot.lifetime = .keepAlways; add(shot)
    }
    func testPendingStackScrollReturnAndComplete() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-pending-stack"]
        app.launchArguments += ["-today.scheduleView", "목록"]; app.launch()
        for _ in 0..<12 { if app.segmentedControls.buttons["타임라인"].isHittable { break }; app.swipeDown() }
        app.segmentedControls.buttons["타임라인"].tap()
        XCTAssertFalse(app.buttons["스택 작업 0 원래 위치로 이동"].exists)
        for _ in 0..<4 { app.swipeUp() }
        let first = app.buttons["스택 작업 0 원래 위치로 이동"]
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["스택 작업 1 원래 위치로 이동"].exists)
        let cards = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "원래 위치로 이동"))
        XCTAssertEqual(cards.count, 3)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label ENDSWITH %@", "미완료 ", "개 더 보기")).firstMatch.exists)
        first.tap()
        XCTAssertTrue(app.buttons["스택 작업 0 상세 보기"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["스택 작업 0 상세 보기"].isHittable)
        XCTAssertFalse(first.exists)
        for _ in 0..<4 { app.swipeUp() }
        let complete = app.buttons["상단 스택 작업 0 완료"]
        XCTAssertTrue(complete.waitForExistence(timeout: 5))
        complete.tap()
        XCTAssertFalse(first.exists)
        for _ in 0..<8 { app.swipeDown() }
        XCTAssertTrue(app.buttons["스택 작업 0 완료 취소"].isHittable)
        XCTAssertFalse(app.buttons["스택 작업 2 원래 위치로 이동"].exists)
    }

    func testTodayCompletionOnFarRight() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }
        app.buttons["루틴 추가"].tap()
        app.textFields["루틴 이름"].tap()
        app.textFields["루틴 이름"].typeText("배치 확인")
        app.buttons["단계 추가"].tap()
        app.textFields["단계 이름"].tap()
        app.textFields["단계 이름"].typeText("세부 작업")
        app.switches["시간 지정"].switches.firstMatch.tap()
        app.buttons["저장"].tap()
        app.tabBars.buttons["오늘"].tap()
        app.segmentedControls.buttons["타임라인"].tap()
        let detail = app.buttons["배치 확인 단계 보기"]
        let complete = app.buttons["배치 확인 완료"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(complete.frame.minX, detail.frame.midX)
        detail.tap()
        XCTAssertTrue(app.buttons["세부 작업"].exists)
        XCTAssertFalse(app.buttons["루틴 수정"].exists)
        XCTAssertFalse(app.buttons["오늘 건너뛰기"].exists)
        XCTAssertFalse(app.buttons["이 날짜의 시간 변경"].exists)
        app.buttons["배치 확인 상세 보기"].tap()
        for _ in 0..<4 { if app.buttons["루틴 수정"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["오늘 건너뛰기"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["루틴 수정"].exists)
        app.navigationBars.buttons["오늘"].tap()
        detail.tap()
        XCTAssertFalse(app.buttons["세부 작업"].exists)
        complete.tap()
        XCTAssertTrue(app.staticTexts["완료 1개"].exists)
        app.buttons["배치 확인 완료 취소"].tap()
        XCTAssertTrue(app.staticTexts["완료 0개"].exists)
        app.segmentedControls.buttons["시간 블록"].tap()
        let timelineDetail = app.buttons["배치 확인 상세 보기"]
        for _ in 0..<5 { if timelineDetail.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(timelineDetail.isHittable)
        XCTAssertLessThan(timelineDetail.frame.maxX, complete.frame.midX)
        complete.tap()
        XCTAssertTrue(app.buttons["배치 확인 완료 취소"].exists)
        XCTAssertFalse(app.buttons["닫기"].exists)
        timelineDetail.tap()
        for _ in 0..<3 { if app.buttons["이 날짜의 시간 저장"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["이 날짜의 시간 저장"].waitForExistence(timeout: 3))
    }
    func testTodayWithoutStepsHasNoExpansion() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launchArguments += ["-today.scheduleView", "목록"]; app.launch(); app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }; app.buttons["루틴 추가"].tap()
        app.textFields["루틴 이름"].tap(); app.textFields["루틴 이름"].typeText("단계 없는 루틴")
        app.buttons["저장"].tap(); app.tabBars.buttons["오늘"].tap()
        app.segmentedControls.buttons["타임라인"].tap()
        XCTAssertFalse(app.buttons["단계 없는 루틴 단계 보기"].exists)
        let detail = app.buttons["단계 없는 루틴 상세 보기"]
        XCTAssertTrue(detail.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["단계 없는 루틴 완료"].exists)
        detail.tap()
        for _ in 0..<3 { if app.buttons["이 날짜의 시간 저장"].isHittable { break }; app.swipeUp() }
        XCTAssertTrue(app.buttons["이 날짜의 시간 저장"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["오늘 건너뛰기"].exists)
        for _ in 0..<3 { if app.buttons["이 작업에 집중"].isHittable { break }; app.swipeUp() }
        app.buttons["이 작업에 집중"].tap()
        let timer = app.staticTexts["focus-elapsed"]
        XCTAssertTrue(timer.waitForExistence(timeout: 3))
        XCTAssertFalse(app.tabBars.buttons["오늘"].exists)
        XCTAssertFalse(app.segmentedControls.buttons["타임라인"].exists)
        let initialTime = timer.label
        let ticking = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in timer.label != initialTime }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ticking], timeout: 4), .completed)
        app.buttons["집중 종료"].tap()
        XCTAssertTrue(app.staticTexts["완료 0개"].waitForExistence(timeout: 3))
        app.buttons["단계 없는 루틴 상세 보기"].tap()
        for _ in 0..<3 { if app.buttons["이 작업에 집중"].isHittable { break }; app.swipeUp() }
        app.buttons["이 작업에 집중"].tap()
        XCTAssertTrue(app.buttons["작업 완료하고 종료"].waitForExistence(timeout: 3))
        app.buttons["작업 완료하고 종료"].tap()
        XCTAssertTrue(app.tabBars.buttons["오늘"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["완료 1개"].exists)
    }
    func testValidationKeepsEditorAndInput() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }; app.buttons["루틴 추가"].tap()
        app.buttons["저장"].tap()
        XCTAssertTrue(app.alerts["저장하지 못했습니다"].waitForExistence(timeout: 3))
        app.alerts.buttons["확인"].tap()
        XCTAssertTrue(app.textFields["루틴 이름"].exists)
        app.textFields["루틴 이름"].tap(); app.textFields["루틴 이름"].typeText("오류 뒤에도 입력 가능")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["오류 뒤에도 입력 가능"].waitForExistence(timeout: 3))
    }
    func testSaveFailureKeepsDraftAndCanRetry() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-fail-save-once"]; app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }; app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; name.tap(); name.typeText("잃어버리면 안 되는 입력")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.alerts["저장하지 못했습니다"].waitForExistence(timeout: 3)); app.alerts.buttons["확인"].tap()
        XCTAssertEqual(name.value as? String, "잃어버리면 안 되는 입력")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["잃어버리면 안 되는 입력"].waitForExistence(timeout: 3))
    }
    func testStepsAndPlanningWithLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]; app.launchArguments += ["-today.scheduleView", "목록"]; app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }; app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; name.tap(); name.typeText("매일 아침 마음을 가다듬는 긴 이름의 루틴")
        app.swipeUp()
        app.buttons["단계 추가"].tap()
        let step = app.textFields["단계 이름"]; step.tap(); step.typeText("물 한 잔")
        app.buttons["저장"].tap(); app.tabBars.buttons["오늘"].tap()
        let expand = app.buttons["매일 아침 마음을 가다듬는 긴 이름의 루틴 단계 보기"]
        if !expand.isHittable { app.swipeUp() }; expand.tap()
        if !app.buttons["물 한 잔"].isHittable { app.swipeUp() }; app.buttons["물 한 잔"].tap()
        app.swipeDown(); XCTAssertTrue(app.staticTexts["완료 1개"].exists)
        app.tabBars.buttons["일감"].tap(); app.buttons["미리 알림 연결"].tap()
        app.switches["reminder-list-work"].switches.firstMatch.tap(); app.buttons["완료"].tap()
        app.navigationBars.buttons["일감 추가"].tap()
        app.textFields["미리 알림 제목"].tap(); app.textFields["미리 알림 제목"].typeText("독서 계획")
        app.buttons["저장"].tap()
        let item = app.buttons["독서 계획 미리 알림 상세"]
        for _ in 0..<4 { if item.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(item.exists)
        app.terminate(); app.launchArguments += ["-today.scheduleView", "목록"]; app.launch(); app.tabBars.buttons["일감"].tap()
        for _ in 0..<4 { if item.isHittable { break }; app.swipeUp() }
        XCTAssertTrue(item.exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "큰 글자 미리 알림 화면"; shot.lifetime = .keepAlways; add(shot)
    }
    func testSystemNotificationScheduling() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }; app.buttons["루틴 추가"].tap()
        app.textFields["루틴 이름"].tap(); app.textFields["루틴 이름"].typeText("알림 확인")
        app.switches["시간 지정"].switches.firstMatch.tap()
        app.buttons["저장"].tap(); app.tabBars.buttons["오늘"].tap(); app.buttons["설정"].tap()
        for _ in 0..<4 { if app.switches["기본 알림 사용"].isHittable { break }; app.swipeUp() }
        let control = app.switches["기본 알림 사용"]
        if control.switches.firstMatch.exists { control.switches.firstMatch.tap() }
        else { control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        else if springboard.buttons["허용"].exists { springboard.buttons["허용"].tap() }
        let scheduled = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "예정 알림 ")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5))
        let populated = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in !scheduled.label.contains(" 0개") }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [populated], timeout: 5), .completed, app.debugDescription)
        for _ in 0..<4 { if app.switches["기본 알림 사용"].isHittable { break }; app.swipeUp() }
        if control.switches.firstMatch.exists { control.switches.firstMatch.tap() }
        else { control.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertTrue(app.staticTexts["예정 알림 0개 · 한국 시간 기준"].waitForExistence(timeout: 5))
    }
    func testCalendarTabAndNestedHistory() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launch()
        XCTAssertFalse(app.tabBars.buttons["기록"].exists)
        app.tabBars.buttons["캘린더"].tap()
        XCTAssertTrue(app.buttons["캘린더 관리"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["calendarToday"].exists)
        XCTAssertTrue(app.buttons["openAppleCalendar"].exists)
        XCTAssertLessThan(app.buttons["calendarToday"].frame.midX, app.buttons["openAppleCalendar"].frame.midX)
        app.buttons["캘린더 관리"].tap()
        XCTAssertTrue(app.navigationBars["캘린더 연결"].waitForExistence(timeout: 5))
        app.buttons["닫기"].tap()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }
        app.buttons["주간 기록"].tap()
        XCTAssertTrue(app.staticTexts["이번 주 0회 완료"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["루틴 추가"].exists)
        app.navigationBars["나의 루틴"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.buttons["all-routines"].waitForExistence(timeout: 5))
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "전체 네비게이션"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["all-오늘"].tap()
        XCTAssertTrue(app.tabBars.buttons["오늘"].isSelected)
    }
    func testCreateCompleteAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }
        app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("아침 독서")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["아침 독서"].waitForExistence(timeout: 5))
        app.tabBars.buttons["오늘"].tap()
        app.buttons["아침 독서 완료"].tap()
        XCTAssertTrue(app.staticTexts["완료 1개"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["완료 1개"].waitForExistence(timeout: 5))
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }
        app.buttons["주간 기록"].tap()
        XCTAssertTrue(app.staticTexts["이번 주 1회 완료"].waitForExistence(timeout: 5))
    }
}
