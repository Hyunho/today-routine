import SwiftUI
struct SettingsView: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var permissionInFlight = false
    var body: some View {
        NavigationStack { Form {
            Section("내 기기의 기록") { Label("이 기기에 저장", systemImage: "internaldrive"); Text("인터넷 없이 사용할 수 있습니다. 사이트와의 동기화는 지원하지 않습니다.").font(.footnote).foregroundStyle(.secondary) }
            if let sync = model.sync { Section("자동 동기화") { NavigationLink { SyncSettingsView(sync:sync) } label: { VStack(alignment:.leading) { Text("iCloud Drive 폴더"); Text(sync.status).font(.caption).foregroundStyle(.secondary) } } } }
            Section { Text(model.notifications.status).font(.subheadline) } header: { Text("기기 알림") } footer: { Text("한국 시간 기준으로 앞으로 7일, 최대 60개 알림을 예약합니다. 앱을 열 때 갱신되므로 7일 이상 열지 않으면 알림이 이어지지 않을 수 있습니다.") }
            ForEach(model.snapshot.routines.filter { $0.status == .active && $0.repeatKind != .weeklyGoal }.sorted { $0.sortOrder < $1.sortOrder }) { r in
                let pref = model.snapshot.reminders.first { $0.routineID == r.id }
                Section(r.name) {
                    Toggle("알림 사용", isOn: Binding(get: { pref?.enabled ?? false }, set: { enabled in
                        if !enabled { model.perform { try $0.saveReminder(routineID: r.id, enabled: false, minute: pref?.minute ?? r.minute ?? 540) }; return }
                        permissionInFlight = true
                        Task { do { let allowed = try await model.notifications.requestPermission(); if allowed { model.perform { try $0.saveReminder(routineID: r.id, enabled: true, minute: pref?.minute ?? r.minute ?? 540) } } else { model.refreshNotifications() } } catch { model.error = error.localizedDescription }; permissionInFlight = false }
                    })).disabled(permissionInFlight)
                    if pref?.enabled == true { MinutePicker(title: "알림 시간", minute: Binding(get: { pref?.minute ?? 540 }, set: { minute in model.perform { try $0.saveReminder(routineID: r.id, enabled: true, minute: minute) } })) }
                }
            }
            Section { Text("주간 횟수 목표 루틴에는 시간을 자동 배정하지 않습니다.").font(.footnote).foregroundStyle(.secondary) }
        }.navigationTitle("설정").toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }.task { model.refreshNotifications() }
        }.modifier(SheetSaveErrors(model: model))
    }
}
