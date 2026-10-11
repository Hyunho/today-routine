import Foundation
import UserNotifications
import Observation
@MainActor protocol NotificationClient {
    func requestPermission() async throws -> Bool
    func authorization() async -> UNAuthorizationStatus
    func pendingIDs() async -> [String]
    func remove(ids: [String])
    func add(_ request: ReminderRequest) async throws
}
@MainActor struct SystemNotificationClient: NotificationClient {
    private var center: UNUserNotificationCenter { .current() }
    func requestPermission() async throws -> Bool { try await center.requestAuthorization(options: [.alert,.sound,.badge]) }
    func authorization() async -> UNAuthorizationStatus { await center.notificationSettings().authorizationStatus }
    func pendingIDs() async -> [String] { await center.pendingNotificationRequests().map(\.identifier) }
    func remove(ids: [String]) { center.removePendingNotificationRequests(withIdentifiers: ids) }
    func add(_ r: ReminderRequest) async throws {
        let content = UNMutableNotificationContent(); content.title = r.title; content.body = "오늘의 루틴을 시작할 시간이에요."; content.sound = .default
        var date = RoutineRules.calendar.dateComponents([.year,.month,.day,.hour,.minute], from: r.fireDate); date.timeZone = RoutineRules.calendar.timeZone
        try await center.add(UNNotificationRequest(identifier: r.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false)))
    }
}
@MainActor @Observable final class NotificationService {
    var status = "알림 상태를 확인 중입니다."
    private var tail: Task<Void, Never>?
    private let client: any NotificationClient
    init(client: (any NotificationClient)? = nil) { self.client = client ?? SystemNotificationClient() }
    func requestPermission() async throws -> Bool { try await client.requestPermission() }
    func waitUntilIdle() async { await tail?.value }
    func enqueue(snapshot: StoreSnapshot, defaults: ReminderDefaults = ReminderDefaults()) {
        let requests = ReminderPlanner.requests(snapshot: snapshot, now: Date(), defaults: defaults)
        let previous = tail
        tail = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do { try await self.replace(requests) } catch { self.status = "알림 예약 실패: \(error.localizedDescription)" }
        }
    }
    private func replace(_ requests: [ReminderRequest]) async throws {
        let authorization = await client.authorization()
        let existing = await client.pendingIDs()
        client.remove(ids: existing.filter { $0.hasPrefix("routine/") })
        guard authorization == .authorized || authorization == .provisional else {
            status = authorization == .notDetermined ? "알림을 켜면 권한을 요청합니다." : "알림 권한이 꺼져 있습니다. iPhone 설정에서 허용해 주세요."
            return
        }
        for request in requests { try await client.add(request) }
        status = "예정 알림 \(requests.count)개 · 한국 시간 기준"
    }
}
