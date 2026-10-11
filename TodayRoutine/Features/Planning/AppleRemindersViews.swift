import SwiftUI

struct AppleRemindersConnectionView: View {
    let reminders: AppleRemindersModel
    @Environment(\.dismiss) private var dismiss
    @State private var requesting = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("선택한 목록을 일감 탭에서 볼 수 있습니다. 여기서 저장하거나 완료 체크하면 Apple 미리 알림 원본에도 반영됩니다.")
                    if !reminders.hasAccess {
                        Button("미리 알림 접근 허용") {
                            requesting = true
                            Task { await reminders.connect(); requesting = false }
                        }.disabled(requesting)
                        Text("이미 접근을 거부했다면 시스템 설정에서 오늘의 루틴의 미리 알림 권한을 허용해 주세요.").font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if reminders.hasAccess {
                    Section("연결할 목록") {
                        if reminders.lists.isEmpty { Text("미리 알림 앱에서 목록을 만든 뒤 새로고침해 주세요.").foregroundStyle(.secondary) }
                        ForEach(reminders.lists) { list in
                            Toggle(isOn: Binding(get: { reminders.selectedIDs.contains(list.id) }, set: { enabled in Task { await reminders.select(list.id, enabled: enabled) } })) {
                                VStack(alignment: .leading) {
                                    Text(list.title)
                                    Text("\(list.source)\(list.writable ? "" : " · 읽기 전용")").font(.caption).foregroundStyle(.secondary)
                                }
                            }.disabled(reminders.loading).accessibilityIdentifier("reminder-list-\(list.id)")
                        }
                        if reminders.unavailableListCount > 0 { Text("연결했던 목록 \(reminders.unavailableListCount)개에 접근할 수 없습니다. 계정이나 공유 상태를 확인해 주세요.").font(.footnote).foregroundStyle(.secondary) }
                    }
                }
                Section {
                    Button("목록 새로고침") { Task { await reminders.refresh() } }.disabled(reminders.loading || requesting)
                    if !reminders.selectedIDs.isEmpty { Button("모든 목록 연결 해제") { reminders.disconnect() } }
                } footer: {
                    Text("연결 해제는 원본을 삭제하지 않습니다. 목록 선택은 기기별로 저장됩니다. 앱을 열거나 원본 변경을 감지하면 다시 불러옵니다.")
                }
            }.navigationTitle("미리 알림 연결").platformInlineTitle()
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("완료") { dismiss() } } }
                .task { await reminders.refresh() }
                .modifier(AppleRemindersErrors(reminders: reminders))
        }.platformSheetSize()
    }
}

struct AppleReminderRow: View {
    let item: AppleReminderItem
    let reminders: AppleRemindersModel
    var showsDisclosure = true
    var completionLeading = false
    let edit: () -> Void
    @State private var saving = false
    var body: some View {
        HStack(spacing: 12) {
            if completionLeading { completionControl }
            Button(action: edit) {
                HStack(spacing: 10) {
                    if showsDisclosure { Image(systemName: "chevron.right").foregroundStyle(.secondary) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title).font(.headline)
                        Text("미리 알림 · \(item.listTitle)").font(.caption).foregroundStyle(.secondary)
                        Text(item.dayKey.map { "\($0) · \(item.minute.map { RoutineRules.timeLabel($0) } ?? "종일")" } ?? "날짜 미정").font(.caption).foregroundStyle(.secondary)
                        if !item.writable { Text("읽기 전용").font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("\(item.title) 미리 알림 상세")
            if !completionLeading { completionControl }
        }.padding(.vertical, 5)
    }
    private var completionControl: some View {
            Button {
                saving = true
                Task { _ = await reminders.complete(item); saving = false }
            } label: {
                Image(systemName: item.completed ? "checkmark.circle.fill" : "circle").font(.title2)
                    .foregroundStyle(item.completed ? Color.teal : Color.secondary).frame(width: 44, height: 44)
            }.buttonStyle(.borderless).disabled(saving || !item.writable)
                .accessibilityLabel("\(item.title) 미리 알림 \(item.completed ? "완료 취소" : "완료")")
    }
}

struct AppleReminderEditor: View {
    let reminders: AppleRemindersModel
    @State var draft: AppleReminderDraft
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss
    private var readOnly: Bool { draft.original?.writable == false }
    var body: some View {
        NavigationStack {
            Form {
                Section("미리 알림") {
                    if let original = draft.original {
                        LabeledContent("목록", value: original.listTitle)
                    } else {
                        Picker("목록", selection: $draft.listID) { ForEach(reminders.writableLists) { Text($0.title).tag($0.id) } }
                    }
                    TextField("미리 알림 제목", text: $draft.title)
                    TextField("메모", text: $draft.note, axis: .vertical).lineLimit(2...6)
                }.disabled(readOnly || saving)
                Section("마감일") {
                    Toggle("날짜 지정", isOn: Binding(get: { draft.dayKey != nil }, set: { draft.dayKey = $0 ? RoutineRules.dayKey(Date()) : nil; if !$0 { draft.minute = nil } }))
                    if draft.dayKey != nil {
                        DatePicker("날짜", selection: Binding(get: { RoutineRules.date(for: draft.dayKey ?? "") ?? Date() }, set: { draft.dayKey = RoutineRules.dayKey($0) }), displayedComponents: .date)
                        Toggle("시간 지정", isOn: Binding(get: { draft.minute != nil }, set: { draft.minute = $0 ? 540 : nil }))
                        if draft.minute != nil { MinutePicker(title: "시간", minute: Binding(get: { draft.minute ?? 540 }, set: { draft.minute = $0 })) }
                    }
                }.disabled(readOnly || saving)
                Section {
                    Text(readOnly ? "읽기 전용 목록의 항목입니다." : "저장하면 Apple 미리 알림 원본이 변경됩니다. 시간은 한국 시간 기준입니다.").font(.footnote).foregroundStyle(.secondary)
                }
            }.navigationTitle(draft.original == nil ? "미리 알림 추가" : "미리 알림 상세").platformInlineTitle()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(readOnly ? "닫기" : "취소") { dismiss() }.disabled(saving) }
                    if !readOnly {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("저장") { saving = true; Task { if await reminders.save(draft) { dismiss() }; saving = false } }.disabled(saving)
                        }
                    }
                }
                .modifier(AppleRemindersErrors(reminders: reminders))
        }.interactiveDismissDisabled(saving).platformSheetSize()
    }
}
struct AppleRemindersErrors: ViewModifier {
    let reminders: AppleRemindersModel
    var enabled = true
    func body(content: Content) -> some View {
        content.alert("미리 알림 연동", isPresented: Binding(get: { enabled && reminders.error != nil }, set: { if !$0 { reminders.error = nil } })) {
            Button("확인") { reminders.error = nil }
        } message: { Text(reminders.error ?? "") }
    }
}
