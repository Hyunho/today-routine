import SwiftUI
#if os(macOS)
import AppKit
#endif
struct SettingsView: View {
    let model: AppModel
    var embedded = false
    @AppStorage("today.cylinderEffect") private var cylinderEffect = false
    @AppStorage("today.cylinderSize") private var cylinderSize = 100.0
    @Environment(\.dismiss) private var dismiss
    @State private var permissionInFlight = false
    @State private var reminderConnection = false
    @State private var applyAll = false
    @State private var showingSync = false
    var body: some View {
        Group {
            if embedded {
                // Keep panel navigation local: two NavigationStacks would both
                // contribute back buttons to the main window's toolbar.
                if showingSync, let sync = model.sync {
                    VStack(spacing: 0) {
                        HStack {
                            Button { showingSync = false } label: {
                                Label("설정으로", systemImage: "chevron.left")
                            }.buttonStyle(.plain)
                            Spacer()
                            Text("자동 동기화").font(.headline)
                        }.padding()
                        SyncSettingsView(sync: sync)
                    }
                } else { settingsForm }
            } else {
                NavigationStack {
                    settingsForm.navigationTitle("설정")
                        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
                }
            }
        }
        .task { model.refreshNotifications() }
        .sheet(isPresented: $reminderConnection) { AppleRemindersConnectionView(reminders: model.appleReminders) }
        .confirmationDialog("모든 루틴의 개별 알림 설정을 기본값으로 바꿀까요?", isPresented: $applyAll, titleVisibility: .visible) {
            Button("기본 설정 일괄 적용") { model.perform { try $0.useDefaultReminder() } }
        } message: { Text("별도 알림 시간과 알림 끄기 설정이 기본 설정 따르기로 변경됩니다.") }
        .modifier(SheetSaveErrors(model: model, embedded: embedded))
    }

    private var settingsForm: some View {
        Form {
            Section("앱 정보") {
                LabeledContent("앱 버전", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "알 수 없음")
                LabeledContent("빌드 번호", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "알 수 없음")
            }
            Section {
                Toggle("원통형 효과", isOn: $cylinderEffect)
                    .toggleStyle(.switch)
                    .accessibilityIdentifier("today-cylinder-effect")
                if cylinderEffect {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("원통 크기", value: "\(Int(cylinderSize))%")
                        Slider(value: $cylinderSize, in: 50...200, step: 10) {
                            Text("원통 크기")
                        } minimumValueLabel: {
                            Text("작게")
                        } maximumValueLabel: {
                            Text("크게")
                        }
                        .accessibilityValue("\(Int(cylinderSize))퍼센트")
                        .accessibilityIdentifier("today-cylinder-size")
                    }
                }
            } header: { Text("오늘 화면") } footer: {
                Text("타임라인과 상단 스택에서 가운데에 가까운 일감은 크게, 위아래로 멀어질수록 작게 표시합니다. 원통이 작을수록 크기 차이가 커지고, 클수록 완만해집니다. 기본 크기는 100%입니다.")
            }
            #if os(macOS)
            Section {
                layoutStepper("최소 항목 높이", key: \.itemMinHeight, range: 44...240)
                layoutStepper("긴 일정의 분당 추가 높이", key: \.durationHeightPerMinute, range: 0...2, step: 0.1)
                layoutStepper("빈 시간 1시간 높이", key: \.gapHeightPerHour, range: 16...240)
                layoutStepper("항목 사이 여백", key: \.itemSpacing, range: 0...64)
                layoutStepper("선 양끝 여백", key: \.lineInset, range: 0...32)
                Button("기본값으로 복원") { Task { await model.saveListLayout(ListLayoutConfig()) } }
                if model.isSavingListLayout { ProgressView("저장 중…") }
            } header: { Text("타임라인 간격") } footer: {
                Text("값을 바꾸면 저장 후 타임라인에 바로 반영됩니다. 단위는 pt입니다. 긴 일정은 25분을 넘는 시간에 추가 높이가 적용되며, 내용이 많으면 항목 높이는 자동으로 늘어납니다.")
            }
            .disabled(model.isSavingListLayout)
            Section {
                Button("설정 파일 열기") {
                    Task {
                        await model.reloadListLayout()
                        if !NSWorkspace.shared.open(model.listLayoutFileURL) {
                            model.error = "설정 파일을 열 수 없습니다. 아래 경로에서 파일을 확인해 주세요."
                        }
                    }
                }
                Button("다시 불러오기") { Task { await model.reloadListLayout() } }
                Text(model.listLayoutFileURL.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if !model.listLayoutStatus.isEmpty {
                    Text(model.listLayoutStatus).font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text("타임라인 간격 · 설정 파일") } footer: {
                Text("동기화 연결 시 공용 폴더의 Config/list-layout.json을 사용합니다. 연결 전에는 로컬 설정을 사용합니다. 위에서 조절한 값은 이 파일에 저장됩니다. 파일을 직접 수정해 저장해도 앱이 활성화된 동안 2초 이내에 반영됩니다.")
            }
            #endif
            Section("미리 알림") { Button("Apple 미리 알림 연결") { reminderConnection = true } }
            Section {
                ForEach(CalendarRoutineFrequency.allCases, id: \.self) { frequency in
                    Toggle(isOn: Binding(get: { model.appleCalendar.visibleFrequencies.contains(frequency) }, set: { model.appleCalendar.setFrequency(frequency, visible: $0) })) {
                        VStack(alignment: .leading) { Text(frequency.label); Text(frequency.detail).font(.caption).foregroundStyle(.secondary) }
                    }
                }
            } header: { Text("캘린더 루틴 · 반복 빈도") } footer: { Text("루틴 탭에 표시할 분류를 선택합니다. 매일 반복하는 일정은 주간에 포함됩니다. 선택은 이 기기에 저장됩니다.") }
            Section("내 기기의 기록") { Label("이 기기에 저장", systemImage: "internaldrive"); Text("인터넷 없이 사용할 수 있습니다. 사이트와의 동기화는 지원하지 않습니다.").font(.footnote).foregroundStyle(.secondary) }
            if let sync = model.sync {
                Section("자동 동기화") {
                    if embedded {
                        Button { showingSync = true } label: { syncLabel }
                            .buttonStyle(.plain)
                    } else {
                        NavigationLink { SyncSettingsView(sync: sync) } label: { syncLabel }
                    }
                }
            }
            Section { Text(model.notifications.status).font(.subheadline) } header: { Text("기기 알림") } footer: { Text("한국 시간 기준으로 앞으로 7일, 최대 60개 알림을 예약합니다. 앱을 열 때 갱신되므로 7일 이상 열지 않으면 알림이 이어지지 않을 수 있습니다.") }
            Section {
                Toggle("기본 알림 사용", isOn: Binding(get: { model.reminderDefaults.enabled }, set: { enabled in
                    withPermission(required: enabled) { var value = model.reminderDefaults; value.enabled = enabled; model.saveReminderDefaults(value) }
                })).disabled(permissionInFlight)
                Picker("기본 알림 시점", selection: defaultBinding(\.leadMinutes)) {
                    Text("정시").tag(0); Text("5분 전").tag(5); Text("10분 전").tag(10); Text("30분 전").tag(30)
                }
                Button("기존 루틴에 기본 설정 일괄 적용") { applyAll = true }
            } header: { Text("기본 알림") } footer: { Text("시간이 지정된 루틴에 적용합니다. 새 루틴은 자동으로 기본값을 따르며, 기존 개별 설정은 일괄 적용 전까지 유지합니다. 알림 설정은 이 기기에 저장됩니다.") }
            Section {
                Toggle("알림을 쉬는 시간 사용", isOn: defaultBinding(\.quietEnabled))
                if model.reminderDefaults.quietEnabled {
                    MinutePicker(title: "시작", minute: defaultBinding(\.quietStart))
                    MinutePicker(title: "종료", minute: defaultBinding(\.quietEnd))
                }
            } header: { Text("알림을 쉬는 시간") } footer: { Text("이 시간대에는 개별 설정을 포함한 루틴 알림을 보내지 않습니다. 시작과 종료가 같으면 제한하지 않습니다.") }
            ForEach(model.snapshot.routines.filter { $0.status == .active && $0.repeatKind != .weeklyGoal && $0.calendarLink == nil }.sorted { $0.sortOrder < $1.sortOrder }) { r in
                let pref = model.snapshot.reminders.first { $0.routineID == r.id }
                Section(r.name) {
                    Picker("알림 설정", selection: Binding(get: { pref.map { $0.enabled ? "custom" : "off" } ?? "default" }, set: { mode in
                        withPermission(required: mode == "custom") {
                            model.perform {
                                if mode == "default" { try $0.useDefaultReminder(routineID: r.id) }
                                else { try $0.saveReminder(routineID: r.id, enabled: mode == "custom", minute: pref?.minute ?? r.minute ?? 540) }
                            }
                        }
                    })) {
                        Text("기본 설정 따르기").tag("default")
                        Text("별도 설정").tag("custom")
                        Text("알림 끄기").tag("off")
                    }.disabled(permissionInFlight)
                    if pref?.enabled == true { MinutePicker(title: "알림 시간", minute: Binding(get: { pref?.minute ?? 540 }, set: { minute in model.perform { try $0.saveReminder(routineID: r.id, enabled: true, minute: minute) } })) }
                }
            }
        }
    }
    private var syncLabel: some View {
        VStack(alignment: .leading) {
            Text("iCloud Drive 폴더")
            if let sync = model.sync { Text(sync.status).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func layoutStepper(_ title: String, key: WritableKeyPath<ListLayoutConfig, Double>, range: ClosedRange<Double>, step: Double = 1) -> some View {
        Stepper(value: Binding(get: { model.listLayout[keyPath: key] }, set: { next in
            var config = model.listLayout
            config[keyPath: key] = next
            Task { await model.saveListLayout(config) }
        }), in: range, step: step) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(model.listLayout[keyPath: key].formatted(.number.precision(.fractionLength(0...1))) + " pt")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        .accessibilityIdentifier("layout-" + title)
    }
    private func defaultBinding<T>(_ key: WritableKeyPath<ReminderDefaults, T>) -> Binding<T> {
        Binding(get: { model.reminderDefaults[keyPath: key] }, set: { newValue in
            var value = model.reminderDefaults; value[keyPath: key] = newValue; model.saveReminderDefaults(value)
        })
    }
    private func withPermission(required: Bool, action: @escaping () -> Void) {
        guard required else { action(); return }
        permissionInFlight = true
        Task {
            do { if try await model.notifications.requestPermission() { action() } else { model.refreshNotifications() } }
            catch { model.error = error.localizedDescription }
            permissionInFlight = false
        }
    }

}
