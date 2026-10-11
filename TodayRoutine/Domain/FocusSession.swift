import Foundation

struct FocusSession: Identifiable {
    enum Target { case routine(UUID), task(UUID), block(UUID) }
    let id = UUID()
    let target: Target
    let title: String
    let day: Date
    let startedAt: Date

    init(target: Target, title: String, day: Date, startedAt: Date = Date()) {
        self.target = target; self.title = title; self.day = day; self.startedAt = startedAt
    }

    func elapsed(at now: Date) -> Int { max(0, Int(now.timeIntervalSince(startedAt))) }
    func timeLabel(at now: Date) -> String {
        let seconds = elapsed(at: now)
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }
}
