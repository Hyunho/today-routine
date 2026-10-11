import XCTest
@testable import RoutineCore

final class AgendaLayoutTests: XCTestCase {
    func testShortGapUsesTimeScaleWithoutMinimumHeight() {
        let config = ListLayoutConfig()
        let short = AgendaSegment(id: "gap", start: 1105, end: 1110, isGap: true)
        XCTAssertEqual(short.height(using: config), 2, accuracy: 0.001)
        let hour = AgendaSegment(id: "hour-gap", start: 600, end: 660, isGap: true)
        XCTAssertEqual(hour.height(using: config), 24, accuracy: 0.001)
    }

    func testCustomConfigAndInvalidFields() throws {
        let custom = try JSONDecoder().decode(ListLayoutConfig.self, from: Data("""
        {"itemMinHeight":60,"durationHeightPerMinute":1,"gapHeightPerHour":30,"itemSpacing":2,"lineInset":12}
        """.utf8))
        XCTAssertEqual(AgendaSegment(id: "hour", start: 0, end: 60, isGap: false).height(using: custom), 95)
        XCTAssertEqual(AgendaSegment(id: "gap", start: 0, end: 120, isGap: true).height(using: custom), 60)
        XCTAssertEqual(custom.itemSpacing, 2)
        XCTAssertEqual(custom.lineInset, 12)
        let invalid = try JSONDecoder().decode(ListLayoutConfig.self, from: Data("""
        {"itemMinHeight":-1,"durationHeightPerMinute":"bad","gapHeightPerHour":0,"itemSpacing":4,"lineInset":999}
        """.utf8))
        XCTAssertEqual(invalid.itemMinHeight, 54)
        XCTAssertEqual(invalid.durationHeightPerMinute, 0.5)
        XCTAssertEqual(invalid.gapHeightPerHour, 24)
        XCTAssertEqual(invalid.itemSpacing, 4)
        XCTAssertEqual(invalid.lineInset, 8)
        XCTAssertEqual(try JSONDecoder().decode(ListLayoutConfig.self, from: Data("{}".utf8)), ListLayoutConfig())
    }

    func testConfigFileCreationReloadAndMalformedFilePreservation() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("Config/list-layout.json")
        XCTAssertEqual(try ListLayoutConfig.loadOrCreate(at: url), ListLayoutConfig())
        try Data("{\"itemSpacing\":3}".utf8).write(to: url)
        XCTAssertEqual(try ListLayoutConfig.loadOrCreate(at: url).itemSpacing, 3)
        let broken = Data("{broken".utf8)
        try broken.write(to: url)
        XCTAssertThrowsError(try ListLayoutConfig.loadOrCreate(at: url))
        XCTAssertEqual(try Data(contentsOf: url), broken)
    }

    func testGapsDurationsAndOverlappingEvents() {
        let segments = AgendaLayout.segments([
            TimelineInterval(id: "long", start: 600, end: 780),
            TimelineInterval(id: "short", start: 660, end: 685),
            TimelineInterval(id: "later", start: 840, end: 865)
        ])
        XCTAssertEqual(segments.filter(\.isGap).map { [$0.start, $0.end] }, [[0, 600], [780, 840], [865, 1440]])
        XCTAssertGreaterThan(segments.first { $0.id == "long" }!.height, segments.first { $0.id == "short" }!.height)
        XCTAssertEqual(AgendaLayout.currentSegment(in: segments, minute: 670)?.id, "short")
        XCTAssertEqual(AgendaLayout.currentSegment(in: segments, minute: 700)?.id, "long")
        XCTAssertEqual(AgendaLayout.currentSegment(in: segments, minute: 810)?.id, "gap-780")
        XCTAssertEqual(AgendaLayout.currentSegment(in: segments, minute: 840)?.id, "later")
    }
    func testFullDayGridKeepsEarlyAndLateEvents() {
        let entries = [TimelineInterval(id: "early", start: 60, end: 90), TimelineInterval(id: "late", start: 1380, end: 1440)]
        let placed = TimelineLayout.place(entries, startMinute: 0, endMinute: 1440)
        XCTAssertEqual(placed.map(\.start), [60, 1380])
        XCTAssertEqual(placed.map(\.end), [90, 1440])
    }
    func testOneHourIsLargerThanDefaultTask() {
        let task = AgendaSegment(id: "task", start: 600, end: 625, isGap: false)
        let hour = AgendaSegment(id: "hour", start: 600, end: 660, isGap: false)
        XCTAssertEqual(task.height, 54)
        XCTAssertGreaterThan(hour.height, task.height)
    }
    func testEmptyDayAndMidnightBounds() {
        let empty = AgendaLayout.segments([])
        XCTAssertEqual(empty.count, 1)
        XCTAssertEqual(AgendaLayout.currentSegment(in: empty, minute: 0)?.start, 0)
        XCTAssertEqual(AgendaLayout.currentSegment(in: empty, minute: 1439)?.end, 1440)
        let clipped = AgendaLayout.segments([TimelineInterval(id: "overnight", start: -60, end: 30)])
        XCTAssertEqual(clipped.first?.start, 0)
        XCTAssertEqual(AgendaLayout.currentSegment(in: clipped, minute: 30)?.id, "gap-30")
    }
}


extension AgendaLayoutTests {
    func testLocalLayoutSaveCreatesDirectoryAndPersistsEdits() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Config/list-layout.json")
        var config = ListLayoutConfig()
        config.itemSpacing = 22
        try config.save(at: url)
        XCTAssertEqual(try ListLayoutConfig.loadOrCreate(at: url).itemSpacing, 22)
        config.gapHeightPerHour = 60
        try config.save(at: url)
        let saved = try ListLayoutConfig.loadOrCreate(at: url)
        XCTAssertEqual(saved.itemSpacing, 22)
        XCTAssertEqual(saved.gapHeightPerHour, 60)
    }
}


extension AgendaLayoutTests {
    func testUnknownDurationKeepsRoutineAtMinimumHeightWithoutReservingTime() {
        let segments = AgendaLayout.segments([
            TimelineInterval(id: "routine", start: 600, end: 600),
            TimelineInterval(id: "late", start: 1439, end: 1439)
        ])
        XCTAssertEqual(segments.filter { !$0.isGap }.map(\.id), ["routine", "late"])
        XCTAssertEqual(segments.first { $0.id == "routine" }?.height, ListLayoutConfig().itemMinHeight)
        XCTAssertEqual(segments.filter(\.isGap).map { [$0.start, $0.end] }, [[0, 600], [600, 1439], [1439, 1440]])
        XCTAssertEqual(AgendaLayout.currentSegment(in: segments, minute: 610)?.id, "gap-600")
        let placements = TimelineLayout.place([TimelineInterval(id: "routine", start: 600, end: 600)], startMinute: 0, endMinute: 1440)
        XCTAssertEqual(placements.map(\.id), ["routine"])
        XCTAssertEqual(placements.first?.end, 600)
    }
}

extension AgendaLayoutTests {
    func testConfiguredDurationControlsEndAndHeightWhileClippingAtMidnight() {
        XCTAssertNil(RoutineRules.endMinute(start: 600, duration: nil))
        XCTAssertNil(RoutineRules.endMinute(start: nil, duration: 90))
        XCTAssertEqual(RoutineRules.endMinute(start: 600, duration: 90), 690)
        XCTAssertEqual(RoutineRules.endMinute(start: 1430, duration: 90), 1440)
        let segments = AgendaLayout.segments([
            TimelineInterval(id: "read", start: 600, end: RoutineRules.endMinute(start: 600, duration: 90)!)
        ])
        XCTAssertGreaterThan(segments.first { $0.id == "read" }!.height, ListLayoutConfig().itemMinHeight)
        XCTAssertEqual(RoutineRules.durationLabel(90), "1시간 30분")
        XCTAssertEqual(RoutineRules.durationLabel(nil), "미정")
    }
}
