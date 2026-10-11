import XCTest
final class SyncWorkflowTests: XCTestCase {
    func testLocalModeAndConnectedFolderStatus() {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store",UUID().uuidString]; app.launch()
        app.buttons["설정"].tap(); app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.tap()
        XCTAssertTrue(app.buttons["동기화 폴더 선택"].waitForExistence(timeout:5))
        XCTAssertTrue(app.staticTexts["기기에만 저장"].exists)
        app.terminate(); app.launchArguments += ["--uitest-sync"]; app.launch()
        app.buttons["설정"].tap(); app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.tap()
        XCTAssertTrue(app.buttons["연결 해제"].waitForExistence(timeout:8))
        XCTAssertTrue(app.staticTexts["폴더 저장 완료 · 상대 기기 확인 대기"].waitForExistence(timeout:8))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "iPhone 자동 동기화 설정"; shot.lifetime = .keepAlways; add(shot)
    }
    func testExternalCSVAutomaticallyCompletesRoutine() throws {
        continueAfterFailure = false
        let app = XCUIApplication(); app.launchArguments = ["--uitest-store",UUID().uuidString,"--uitest-sync"]; app.launch()
        app.tabBars.buttons["전체"].tap(); if app.buttons["all-routines"].exists { app.buttons["all-routines"].tap() }; app.buttons["루틴 추가"].tap()
        let name = app.textFields["루틴 이름"]; name.tap(); name.typeText("CSV 자동 확인")
        app.buttons["저장"].tap(); app.tabBars.buttons["오늘"].tap(); app.buttons["설정"].tap()
        app.buttons.containing(.staticText,identifier:"iCloud Drive 폴더").firstMatch.tap()
        let path = app.staticTexts.matching(NSPredicate(format:"identifier BEGINSWITH %@","csv-path-")).firstMatch
        XCTAssertTrue(path.waitForExistence(timeout:8))
        let url = URL(fileURLWithPath:path.label)
        let original = try String(contentsOf:url,encoding:.utf8)
        try original.replacingOccurrences(of:"FALSE",with:"TRUE").write(to:url,atomically:true,encoding:.utf8)
        app.navigationBars["자동 동기화"].buttons["설정"].tap(); app.buttons["완료"].tap()
        XCTAssertTrue(app.staticTexts["완료 1개"].waitForExistence(timeout:20))
        let shot = XCTAttachment(screenshot:app.screenshot()); shot.name = "CSV 외부 수정 자동 완료"; shot.lifetime = .keepAlways; add(shot)
    }
}
