import XCTest

final class AppleRemindersWorkflowTests: XCTestCase {
    func testPrimaryAddCreatesReminderOnly() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록"]
        app.launch(); app.tabBars.buttons["일감"].tap()
        app.buttons["미리 알림 연결"].tap()
        app.switches["reminder-list-work"].switches.firstMatch.tap(); app.buttons["완료"].tap()
        app.navigationBars.buttons["일감 추가"].tap()
        let title = app.textFields["미리 알림 제목"]
        XCTAssertTrue(title.waitForExistence(timeout: 3))
        title.tap(); title.typeText("상단에서 추가")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.buttons["상단에서 추가 미리 알림 상세"].waitForExistence(timeout: 3))
        app.terminate(); app.launch(); app.tabBars.buttons["일감"].tap()
        XCTAssertTrue(app.buttons["상단에서 추가 미리 알림 상세"].waitForExistence(timeout: 3))
    }
    func testAddWithoutWritableListOpensConnection() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록"]
        app.launch(); app.tabBars.buttons["일감"].tap()
        app.navigationBars.buttons["일감 추가"].tap()
        XCTAssertTrue(app.switches["reminder-list-readonly"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["일감 제목"].exists)
        app.switches["reminder-list-readonly"].switches.firstMatch.tap(); app.buttons["완료"].tap()
        app.navigationBars.buttons["일감 추가"].tap()
        XCTAssertTrue(app.switches["reminder-list-readonly"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["미리 알림 제목"].exists)
    }
    func testRevokedAccessCannotCreateLocalTask() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록"]
        app.launch(); app.tabBars.buttons["일감"].tap(); app.buttons["미리 알림 연결"].tap()
        app.switches["reminder-list-work"].switches.firstMatch.tap(); app.buttons["완료"].tap()
        app.terminate(); app.launchArguments.append("--uitest-reminders-denied"); app.launch()
        app.tabBars.buttons["일감"].tap(); app.navigationBars.buttons["일감 추가"].tap()
        XCTAssertTrue(app.buttons["미리 알림 접근 허용"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.textFields["일감 제목"].exists)
    }
    func testLegacyTasksDisappearOnUpgrade() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록", "--uitest-legacy-tasks"]
        app.launch()
        for _ in 0..<10 { if app.staticTexts["완료 0개"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["완료 0개"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertFalse(app.buttons["삭제할 내부 일감 상세 보기"].exists)
        app.segmentedControls.buttons["시간 블록"].tap()
        let block = app.buttons["보존할 집중 시간 상세 보기"]
        for _ in 0..<10 { if block.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(block.isHittable); block.tap()
        XCTAssertTrue(app.textFields["블록 제목"].waitForExistence(timeout: 3))
        XCTAssertEqual(app.textFields["블록 제목"].value as? String, "보존할 집중 시간")
        app.buttons["저장"].tap()
        app.tabBars.buttons["일감"].tap(); app.buttons["미리 알림 연결"].tap()
        app.switches["reminder-list-work"].switches.firstMatch.tap(); app.buttons["완료"].tap()
        XCTAssertTrue(app.buttons["오늘 마감 확인 미리 알림 상세"].waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["삭제할 내부 일감"].exists)
        XCTAssertFalse(app.staticTexts["삭제할 완료 일감"].exists)
        app.terminate(); app.launch()
        for _ in 0..<10 { if app.staticTexts["완료 0개"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["완료 0개"].waitForExistence(timeout: 5), app.debugDescription)
        app.segmentedControls.buttons["시간 블록"].tap()
        for _ in 0..<10 { if block.isHittable { break }; app.swipeDown() }
        XCTAssertTrue(block.isHittable)
        XCTAssertFalse(app.buttons["삭제할 내부 일감 상세 보기"].exists)
    }
    func testConnectEditCompleteAndRelaunch() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록"]
        app.launch()
        app.tabBars.buttons["일감"].tap()
        app.buttons["미리 알림 연결"].tap()
        app.switches["reminder-list-work"].switches.firstMatch.tap()
        app.buttons["완료"].tap()
        XCTAssertTrue(app.buttons["오늘 마감 확인 미리 알림 상세"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["다른 목록 항목 미리 알림 상세"].exists)
        app.buttons["오늘 마감 확인 미리 알림 상세"].tap()
        let title = app.textFields["미리 알림 제목"]
        title.tap()
        title.typeText(" 수정")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.buttons["오늘 마감 확인 수정 미리 알림 상세"].waitForExistence(timeout: 3))
        app.tabBars.buttons["오늘"].tap()
        for _ in 0..<6 { if app.staticTexts["완료 0개"].isHittable { break }; app.swipeDown() }
        XCTAssertTrue(app.buttons["오늘 마감 확인 수정 미리 알림 완료"].waitForExistence(timeout: 3))
        app.buttons["오늘 마감 확인 수정 미리 알림 완료"].tap()
        for _ in 0..<6 { if app.staticTexts["완료 1개"].exists { break }; app.swipeDown() }
        XCTAssertTrue(app.staticTexts["완료 1개"].waitForExistence(timeout: 3), app.debugDescription)
        XCTAssertFalse(app.buttons["내일 마감 확인 미리 알림 상세"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "오늘 미리 알림 연동"; shot.lifetime = .keepAlways; add(shot)
        app.terminate(); app.launch()
        XCTAssertTrue(app.buttons["오늘 마감 확인 수정 미리 알림 완료 취소"].waitForExistence(timeout: 5))
        app.tabBars.buttons["일감"].tap()
        app.buttons["연결 목록 관리 (1개)"].tap()
        app.buttons["모든 목록 연결 해제"].tap()
        app.buttons["완료"].tap()
        XCTAssertFalse(app.buttons["오늘 마감 확인 수정 미리 알림 상세"].exists)
    }
    func testCreateValidationAndReadOnlyList() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록"]
        app.launch(); app.tabBars.buttons["일감"].tap(); app.buttons["미리 알림 연결"].tap()
        app.switches["reminder-list-work"].switches.firstMatch.tap()
        app.switches["reminder-list-readonly"].switches.firstMatch.tap()
        app.buttons["완료"].tap()
        app.buttons["미리 알림 추가"].tap()
        app.buttons["저장"].tap()
        XCTAssertTrue(app.alerts["미리 알림 연동"].waitForExistence(timeout: 3))
        app.alerts.buttons["확인"].tap()
        app.textFields["미리 알림 제목"].tap()
        app.textFields["미리 알림 제목"].typeText("새 미리 알림")
        app.switches["날짜 지정"].switches.firstMatch.tap()
        app.buttons["저장"].tap()
        app.tabBars.buttons["오늘"].tap()
        XCTAssertTrue(app.buttons["새 미리 알림 미리 알림 상세"].waitForExistence(timeout: 3))
        app.tabBars.buttons["일감"].tap()
        let readOnly = app.buttons["공유 참고 항목 미리 알림 상세"]
        for _ in 0..<4 { if readOnly.isHittable { break }; app.swipeUp() }
        XCTAssertFalse(app.buttons["공유 참고 항목 미리 알림 완료"].isEnabled)
        readOnly.tap()
        XCTAssertFalse(app.buttons["저장"].exists)
        XCTAssertFalse(app.textFields["미리 알림 제목"].isEnabled)
        XCTAssertTrue(app.buttons["닫기"].exists)
    }
    func testDeniedPermissionExplainsAccess() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString, "--uitest-reminders", "-today.scheduleView", "목록", "--uitest-reminders-denied"]
        app.launch(); app.tabBars.buttons["일감"].tap(); app.buttons["미리 알림 연결"].tap()
        app.buttons["미리 알림 접근 허용"].tap()
        XCTAssertTrue(app.alerts["미리 알림 연동"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.alerts.staticTexts["시스템 설정에서 오늘의 루틴의 미리 알림 접근을 허용해 주세요."].exists)
    }
}
