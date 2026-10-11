import XCTest
@testable import RoutineCore
final class TimelineLayoutTests: XCTestCase {
    func testOverlapsShareColumnsAndTouchingIntervalsDoNotOverlap() {
        let items = [TimelineInterval(id: "a", start: 300, end: 360), TimelineInterval(id: "b", start: 330, end: 390), TimelineInterval(id: "c", start: 390, end: 420)]
        let result = TimelineLayout.place(items)
        XCTAssertEqual(result.map(\.columns), [2, 2, 1])
        XCTAssertEqual(result.map(\.column), [0, 1, 0])
    }
    func testClipsToGridAndExcludesOutsideIntervals() {
        let result = TimelineLayout.place([.init(id: "early", start: 270, end: 330), .init(id: "late", start: 1300, end: 1400), .init(id: "outside", start: 1400, end: 1430)])
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].start, 300)
        XCTAssertEqual(result[1].end, 1320)
    }
}
extension TimelineLayoutTests {
    func testDragSnapsAndPreservesDurationWithinDay() {
        XCTAssertEqual(TimelineLayout.movedStart(start: 360, duration: 60, translation: 62), 390)
        XCTAssertEqual(TimelineLayout.movedStart(start: 360, duration: 60, translation: -62), 330)
        XCTAssertEqual(TimelineLayout.movedStart(start: 10, duration: 60, translation: -100), 0)
        let latest = TimelineLayout.movedStart(start: 1380, duration: 60, translation: 200)
        XCTAssertLessThan(latest + 60, 1440)
        XCTAssertEqual(latest % 15, 0)
    }
}
