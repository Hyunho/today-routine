import Foundation
import UserNotifications
import Observation
@MainActor @Observable final class NotificationService {
    var status = "알림 상태를 확인 중입니다."
    private var tail: Task<Void, Never>?
    private let center = UNUserNotificationCenter.current()
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert,.sound,.badge]) }
    func enqueue(snapshot: StoreSnapshot) {
        let requests = ReminderPlanner.requests(snapshot: snapshot, now: Date())
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do { try await self.replace(requests) } catch { self.status = "알림 예약 실패: \(error.localizedDescription)" }
        }
    }
    private func replace(_ requests: [ReminderRequest]) async throws {
        let settings = await center.notificationSettings()
        let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
        let existing = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(withIdentifiers: existing.filter { $0.identifier.hasPrefix("routine/") }.map(\.identifier))
        guard allowed else { status = settings.authorizationStatus == .notDetermined ? "알림을 켜면 권한을 요청합니다." : "알림 권한이 꺼져 있습니다. iPhone 설정에서 허용해 주세요."; return }
        for r in requests {
            let content = UNMutableNotificationContent(); content.title = r.title; content.body = "오늘의 루틴을 시작할 시간이에요."; content.sound = .default
            var date = RoutineRules.calendar.dateComponents([.year,.month,.day,.hour,.minute], from: r.fireDate); date.timeZone = RoutineRules.calendar.timeZone
            try await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)))
        }
        status = "예정 알림 \(requests.count)개 · 한국 시간 기준"
    }
}
