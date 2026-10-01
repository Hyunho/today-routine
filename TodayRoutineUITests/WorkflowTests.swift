import XCTest
final class WorkflowTests: XCTestCase {
    func testValidationKeepsEditorAndInput() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["루틴"].tap(); app.buttons["루틴 추가"].tap()
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
        app.tabBars.buttons["루틴"].tap(); app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; name.tap(); name.typeText("잃어버리면 안 되는 입력")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.alerts["저장하지 못했습니다"].waitForExistence(timeout: 3)); app.alerts.buttons["확인"].tap()
        XCTAssertEqual(name.value as? String, "잃어버리면 안 되는 입력")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["잃어버리면 안 되는 입력"].waitForExistence(timeout: 3))
    }
    func testStepsAndPlanningWithLargeText() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString, "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityM"]; app.launch()
        app.tabBars.buttons["루틴"].tap(); app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; name.tap(); name.typeText("매일 아침 마음을 가다듬는 긴 이름의 루틴")
        app.swipeUp()
        app.buttons["단계 추가"].tap()
        let step = app.textFields["단계 이름"]; step.tap(); step.typeText("물 한 잔")
        app.buttons["저장"].tap(); app.tabBars.buttons["오늘"].tap()
        let expand = app.buttons["매일 아침 마음을 가다듬는 긴 이름의 루틴 단계 보기"]
        if !expand.isHittable { app.swipeUp() }; expand.tap()
        if !app.buttons["물 한 잔"].isHittable { app.swipeUp() }; app.buttons["물 한 잔"].tap()
        app.swipeDown(); XCTAssertTrue(app.staticTexts["완료 1개"].exists)
        app.tabBars.buttons["계획"].tap(); app.buttons["일감 추가"].tap()
        app.textFields["일감 제목"].tap(); app.textFields["일감 제목"].typeText("독서 계획")
        app.buttons["저장"].tap(); XCTAssertTrue(app.staticTexts["독서 계획"].waitForExistence(timeout: 3))
        app.buttons["타임블록"].tap(); app.buttons["타임블록 추가"].tap()
        app.textFields["블록 제목"].tap(); app.textFields["블록 제목"].typeText("집중 독서")
        app.buttons["저장"].tap(); XCTAssertTrue(app.staticTexts["집중 독서"].waitForExistence(timeout: 3))
        app.terminate(); app.launch(); app.tabBars.buttons["계획"].tap()
        XCTAssertTrue(app.staticTexts["독서 계획"].exists)
        app.buttons["타임블록"].tap(); XCTAssertTrue(app.staticTexts["집중 독서"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "큰 글자 계획 화면"; shot.lifetime = .keepAlways; add(shot)
    }
    func testSystemNotificationScheduling() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["루틴"].tap(); app.buttons["루틴 추가"].tap()
        app.textFields["루틴 이름"].tap(); app.textFields["루틴 이름"].typeText("알림 확인")
        app.buttons["저장"].tap(); app.tabBars.buttons["오늘"].tap(); app.buttons["설정"].tap()
        app.switches["알림 사용"].switches.firstMatch.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let allow = springboard.buttons["Allow"]
        if allow.waitForExistence(timeout: 3) { allow.tap() }
        else if springboard.buttons["허용"].exists { springboard.buttons["허용"].tap() }
        let scheduled = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "예정 알림 ")).firstMatch
        XCTAssertTrue(scheduled.waitForExistence(timeout: 5)); XCTAssertFalse(scheduled.label.contains(" 0개"))
        app.switches["알림 사용"].switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["예정 알림 0개 · 한국 시간 기준"].waitForExistence(timeout: 5))
    }
    func testCreateCompleteAndRelaunch() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store", UUID().uuidString]; app.launch()
        app.tabBars.buttons["루틴"].tap()
        app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("아침 독서")
        app.buttons["저장"].tap()
        XCTAssertTrue(app.staticTexts["아침 독서"].waitForExistence(timeout: 5))
        app.tabBars.buttons["오늘"].tap()
        app.buttons["아침 독서 완료"].tap()
        XCTAssertTrue(app.staticTexts["완료 1개"].exists)
        app.terminate(); app.launch()
        XCTAssertTrue(app.staticTexts["완료 1개"].waitForExistence(timeout: 5))
        app.tabBars.buttons["기록"].tap()
        XCTAssertTrue(app.staticTexts["이번 주 1회 완료"].waitForExistence(timeout: 5))
    }
}
