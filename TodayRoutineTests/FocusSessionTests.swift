import XCTest
@testable import RoutineCore

final class FocusSessionTests: XCTestCase {
    func testElapsedUsesStartTimeAcrossBackgroundIntervals() {
        let start = Date(timeIntervalSince1970: 1_000)
        let session = FocusSession(target: .task(UUID()), title: "작업", day: start, startedAt: start)
        XCTAssertEqual(session.timeLabel(at: start), "00:00:00")
        XCTAssertEqual(session.timeLabel(at: start.addingTimeInterval(3661)), "01:01:01")
        XCTAssertEqual(session.elapsed(at: start.addingTimeInterval(125.9)), 125)
    }
    func testClockMovingBackwardNeverShowsNegativeElapsed() {
        let start = Date()
        let session = FocusSession(target: .routine(UUID()), title: "루틴", day: start, startedAt: start)
        XCTAssertEqual(session.timeLabel(at: start.addingTimeInterval(-10)), "00:00:00")
    }
}
