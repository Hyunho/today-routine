import SwiftUI
import EventKit

struct CalendarView: View {
    @Bindable var calendar: AppleCalendarModel
    var routineModel: AppModel? = nil
    @State private var connections = false
    @State private var selectedEvent: AppleCalendarEvent?
    @Environment(\.scenePhase) private var phase
    var body: some View {
        NavigationStack {
            MonthCalendarContent(calendar: calendar, openConnections: { connections = true }, openEvent: { selectedEvent = $0 })
            .navigationTitle("캘린더")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("캘린더 관리", systemImage: "calendar") { connections = true }
                }
                ToolbarItem { Button("새로고침", systemImage: "arrow.clockwise") { Task { await calendar.refresh() } }.disabled(calendar.loading) }
            }
            .refreshable { await calendar.refresh() }
            .sheet(isPresented: $connections) { CalendarConnectionsView(calendar: calendar) }
            .sheet(item: $selectedEvent) { CalendarEventDetail(event: $0, calendar: calendar, routineModel: routineModel) }
            .task(id: calendar.date) { await calendar.refresh() }
            .onChange(of: phase) { _, phase in if phase == .active { Task { await calendar.refresh() } } }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await calendar.refresh() } }
        }
        .environment(\.calendar, Calendar.current)
        .environment(\.timeZone, TimeZone.current)
    }
}

private struct CalendarConnectionsView: View {
    @Bindable var calendar: AppleCalendarModel
    @Environment(\.scenePhase) private var phase
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("표시할 캘린더를 선택하세요. 선택은 이 기기에만 저장됩니다.").font(.subheadline)
                    if !calendar.hasAccess {
                        Button("Apple 캘린더 접근 허용") { Task { await calendar.connect() } }
                            .buttonStyle(.borderedProminent)
                            .disabled(calendar.isConnecting)
                        if calendar.isConnecting { ProgressView("접근 권한 확인 중") }
                        Text("일정을 읽고 루틴을 반복 일정으로 전환하려면 캘린더 전체 접근 권한이 필요합니다. 일정 생성은 전환 화면에서 확인한 경우에만 진행됩니다.").font(.caption).foregroundStyle(.secondary)
                    }
                    if let error = calendar.error { Text(error).foregroundStyle(.orange).font(.caption) }
                }
                if calendar.hasAccess {
                    if calendar.calendars.isEmpty { Text("사용 가능한 캘린더가 없습니다. Apple 캘린더 앱에서 계정을 확인해 주세요.") }
                    ForEach(calendar.calendars) { list in
                        Toggle(isOn: Binding(get: { calendar.selectedIDs.contains(list.id) }, set: { enabled in Task { await calendar.select(list.id, enabled: enabled) } })) {
                            VStack(alignment: .leading) { Text(list.title); Text(list.source).font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if !calendar.selectedIDs.isEmpty { Button("모든 캘린더 연결 해제") { calendar.disconnect() } }
                }
            }
            .navigationTitle("캘린더 연결")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("목록 새로고침", systemImage: "arrow.clockwise") { Task { await calendar.refresh() } }
                        .disabled(calendar.isConnecting || calendar.loading)
                }
            }
            .task { await calendar.refresh() }
            .onChange(of: phase) { _, phase in if phase == .active { Task { await calendar.refresh() } } }
            .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await calendar.refresh() } }
        }.platformSheetSize()
    }
}

struct CalendarEventDetail: View {
    let event: AppleCalendarEvent
    let calendar: AppleCalendarModel
    var routineModel: AppModel? = nil
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(event.title).font(.title2.bold()).textSelection(.enabled)
                    CompletionStatusLabel(status: calendar.isCompleted(event) ? .completed : .pending)
                    Label(event.calendarTitle, systemImage: "calendar").foregroundStyle(.teal)
                    if event.allDay {
                        Text("하루 종일")
                        Text(event.start, format: .dateTime.year().month().day())
                        if Calendar.current.dateComponents([.day], from: event.start, to: event.end).day ?? 0 > 1 {
                            Text("마지막 날: \(event.end.addingTimeInterval(-1).formatted(date: .abbreviated, time: .omitted))")
                        }
                    } else {
                        Text("시작: \(event.start.formatted(date: .abbreviated, time: .shortened))")
                        Text("종료: \(event.end.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
                if !event.location.isEmpty { Section("장소") { Text(event.location).textSelection(.enabled) } }
                if !event.note.isEmpty { Section("메모") { Text(event.note).textSelection(.enabled) } }
                if let model = routineModel, let routine = model.routine(for: event) {
                    Section("하위 목록 · 앱에 저장") {
                        ForEach(model.steps(for: routine)) { step in
                            Button {
                                model.perform { try $0.toggleStep(routineID: routine.id, stepID: step.id, date: event.start) }
                            } label: {
                                Label(step.name, systemImage: model.record(routine, date: event.start)?.completedStepIDs.contains(step.id) == true ? "checkmark.square.fill" : "square")
                            }.buttonStyle(.borderless)
                        }
                        Button(calendar.isCompleted(event) ? "완료 취소" : "루틴 완료") { calendar.setCompleted(event, completed: !calendar.isCompleted(event)) }
                    }
                }
                if let url = event.url, ["https", "http"].contains(url.scheme?.lowercased() ?? "") { Link("일정 링크 열기", destination: url) }
            }.navigationTitle("일정 상세")
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }.platformSheetSize()
    }
}
