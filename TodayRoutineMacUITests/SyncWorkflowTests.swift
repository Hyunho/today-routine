import XCTest
final class SyncWorkflowTests: XCTestCase {
    func testRoutineDurationCanBeSavedReopenedAndCleared() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launch()
        app.buttons["전체"].click()
        app.buttons["all-routines"].click()
        app.buttons["루틴 추가"].click()
        let name = app.textFields["루틴 이름"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        name.click(); name.typeText("소요시간 확인")
        let toggle = app.descendants(matching: .any).matching(identifier: "routine-duration-enabled").firstMatch
        XCTAssertTrue(toggle.exists)
        toggle.click()
        let duration = app.textFields["routine-duration-minutes"]
        XCTAssertTrue(duration.waitForExistence(timeout: 3))
        duration.click(); duration.typeText("90")
        app.buttons["저장"].click()
        let row = app.staticTexts["소요시간 확인"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "소요시간 1시간 30분")).firstMatch.exists)
        row.click()
        XCTAssertTrue(duration.waitForExistence(timeout: 3))
        XCTAssertEqual(duration.value as? String, "90")
        toggle.click()
        app.buttons["저장"].click()
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "소요시간 미정")).firstMatch.exists)
    }

    func testSettingsPanelExpandsAndClosesWithoutLeavingToday() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-store", UUID().uuidString]
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        let width = window.frame.width
        app.buttons["설정"].firstMatch.click()
        XCTAssertTrue(app.buttons["settings-panel-close"].waitForExistence(timeout: 5))
        XCTAssertGreaterThan(window.frame.width, width + 300)
        XCTAssertEqual(app.sheets.count, 0)
        let effect = app.switches["today-cylinder-effect"]
        XCTAssertTrue(effect.exists)
        let original = effect.value as? String
        effect.click()
        XCTAssertNotEqual(effect.value as? String, original)
        app.buttons["settings-panel-close"].click()
        XCTAssertFalse(app.buttons["settings-panel-close"].exists)
        XCTAssertEqual(window.frame.width, width, accuracy: 24)
        app.buttons["settings-panel-toggle"].click()
        XCTAssertTrue(app.buttons["settings-panel-close"].waitForExistence(timeout: 5))
        XCTAssertNotEqual(effect.value as? String, original)
        effect.click()
        XCTAssertEqual(effect.value as? String, original)
    }

    func testCreateRoutineCompleteAndSyncSettings() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store",UUID().uuidString,"--uitest-sync"]; app.launch()
        app.buttons["전체"].click(); app.buttons["all-routines"].click(); app.buttons["루틴 추가"].click()
        let name = app.textFields["루틴 이름"]; XCTAssertTrue(name.waitForExistence(timeout:5)); name.click(); name.typeText("맥 아침 독서")
        app.buttons["저장"].click()
        XCTAssertTrue(app.staticTexts["맥 아침 독서"].waitForExistence(timeout:5))
        app.staticTexts["오늘"].click(); app.buttons["맥 아침 독서 완료"].click()
        XCTAssertTrue(app.staticTexts["완료 1개"].waitForExistence(timeout:5))
        app.buttons["설정"].click(); app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.click()
        XCTAssertTrue(app.buttons["연결 해제"].waitForExistence(timeout:8))
        XCTAssertTrue(app.buttons["맥 아침 독서"].waitForExistence(timeout:8))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "Mac 자동 동기화 설정"; shot.lifetime = .keepAlways; add(shot)
    }
}
