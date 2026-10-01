import XCTest
final class WorkflowTests: XCTestCase {
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
