import Foundation
struct TimelineInterval {
    let id: String
    let start: Int
    let end: Int
}
struct TimelinePlacement: Identifiable {
    let id: String
    let start: Int
    let end: Int
    let column: Int
    var columns: Int
}
enum TimelineLayout {
    static func place(_ intervals: [TimelineInterval], startMinute: Int = 300, endMinute: Int = 1320) -> [TimelinePlacement] {
        let sorted = intervals.filter { ($0.end > startMinute || ($0.start == $0.end && $0.start == startMinute)) && $0.start < endMinute && $0.end >= $0.start }
            .sorted { $0.start == $1.start ? $0.id < $1.id : $0.start < $1.start }
        var result: [TimelinePlacement] = [], group: [TimelinePlacement] = []
        var ends: [Int] = [], groupEnd = 0
        func flush() {
            result += group.map { var item = $0; item.columns = ends.count; return item }
            group = []; ends = []
        }
        for item in sorted {
            let start = max(startMinute, item.start), end = min(endMinute, item.end)
            if !group.isEmpty && start >= groupEnd { flush() }
            let column = ends.firstIndex(where: { $0 <= start }) ?? ends.count
            if column == ends.count { ends.append(end) } else { ends[column] = end }
            groupEnd = group.isEmpty ? end : max(groupEnd, end)
            group.append(.init(id: item.id, start: start, end: end, column: column, columns: 1))
        }
        flush()
        return result
    }
}
extension TimelineLayout {
    // The grid uses two points per minute; keep the entire block on the same day.
    static func movedStart(start: Int, duration: Int, translation: Double) -> Int {
        let snapped = Int((Double(start) / 15 + translation / 30).rounded()) * 15
        let latest = max(0, (1439 - max(0, duration)) / 15 * 15)
        return min(latest, max(0, snapped))
    }
}
