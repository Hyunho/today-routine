import Foundation

struct ListLayoutConfig: Codable, Equatable {
    var itemMinHeight = 54.0
    var durationHeightPerMinute = 0.5
    var gapHeightPerHour = 24.0
    var itemSpacing = 8.0
    var lineInset = 8.0

    init() {}

    private enum CodingKeys: String, CodingKey {
        case itemMinHeight, durationHeightPerMinute, gapHeightPerHour, itemSpacing, lineInset
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        func value(_ key: CodingKeys, default fallback: Double, range: ClosedRange<Double>) -> Double {
            guard let number = try? values.decode(Double.self, forKey: key),
                  number.isFinite, range.contains(number) else { return fallback }
            return number
        }
        itemMinHeight = value(.itemMinHeight, default: 54, range: 44...240)
        durationHeightPerMinute = value(.durationHeightPerMinute, default: 0.5, range: 0...2)
        gapHeightPerHour = value(.gapHeightPerHour, default: 24, range: 16...240)
        itemSpacing = value(.itemSpacing, default: 8, range: 0...64)
        lineInset = value(.lineInset, default: 8, range: 0...32)
    }

    static var fileURL: URL {
        URL.applicationSupportDirectory.appendingPathComponent("TodayRoutine/Config/list-layout.json")
    }

    func save(at url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    static func loadOrCreate(at url: URL) throws -> ListLayoutConfig {
        if !FileManager.default.fileExists(atPath: url.path) {
            try ListLayoutConfig().save(at: url)
        }
        return try JSONDecoder().decode(ListLayoutConfig.self, from: Data(contentsOf: url))
    }
}

struct AgendaSegment: Identifiable {
    let id: String
    let start: Int
    let end: Int
    let isGap: Bool
    var height: Double {
        height(using: ListLayoutConfig())
    }
    func height(using config: ListLayoutConfig) -> Double {
        if isGap {
            return Double(end - start) / 60 * config.gapHeightPerHour
        }
        return config.itemMinHeight + Double(max(0, end - start - 25)) * config.durationHeightPerMinute
    }
}

enum AgendaLayout {
    static func segments(_ intervals: [TimelineInterval]) -> [AgendaSegment] {
        var result: [AgendaSegment] = [], coveredEnd = 0
        for item in intervals.sorted(by: { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }) {
            let start = max(0, item.start), end = min(1440, item.end)
            // A routine without a duration is a point in time, with minimum row height.
            guard start < end || (item.start == item.end && (0..<1440).contains(item.start)) else { continue }
            if start > coveredEnd {
                result.append(AgendaSegment(id: "gap-\(coveredEnd)", start: coveredEnd, end: start, isGap: true))
            }
            result.append(AgendaSegment(id: item.id, start: start, end: end, isGap: false))
            coveredEnd = max(coveredEnd, end)
        }
        if coveredEnd < 1440 {
            result.append(AgendaSegment(id: "gap-\(coveredEnd)", start: coveredEnd, end: 1440, isGap: true))
        }
        return result
    }

    static func currentSegment(in segments: [AgendaSegment], minute: Int) -> AgendaSegment? {
        // Overlapping events remain individually readable; place the line only once,
        // in the most recently started event that still contains the current time.
        segments.last { !$0.isGap && $0.start <= minute && minute < $0.end }
            ?? segments.first { $0.isGap && $0.start <= minute && minute < $0.end }
    }
}
