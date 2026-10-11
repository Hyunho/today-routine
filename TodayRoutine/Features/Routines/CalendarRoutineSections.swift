import SwiftUI

struct CalendarRoutineSections: View {
    let model: AppModel
    let events: [AppleCalendarEvent]
    let loading: Bool
    let status: RoutineStatus
    let edit: (Routine) -> Void
    private var linked: [Routine] { model.snapshot.routines.filter { $0.calendarLink != nil } }
    private func routine(_ event: AppleCalendarEvent) -> Routine? {
        linked.first { CalendarRoutineIdentity.event(for: $0, in: events)?.id == event.id }
    }
    private func items(_ frequency: CalendarRoutineFrequency) -> [AppleCalendarEvent] {
        events.filter { event in
            event.routineFrequency == frequency && (routine(event).map { $0.status == status } ?? (status == .active))
        }
    }
    var body: some View {
        Section {
            if loading { ProgressView("반복 일정을 불러오는 중") }
            else if !model.appleCalendar.hasAccess {
                Button("캘린더 탭에서 Apple 캘린더 연결") { Task { await model.selectTab("캘린더") } }
            } else if model.appleCalendar.selectedIDs.isEmpty {
                Button("캘린더 탭에서 표시할 캘린더 선택") { Task { await model.selectTab("캘린더") } }
            } else if model.appleCalendar.visibleFrequencies.isEmpty {
                Text("설정에서 표시할 반복 빈도를 선택해 주세요.").foregroundStyle(.secondary)
            } else if model.appleCalendar.visibleFrequencies.allSatisfy({ items($0).isEmpty }) {
                Text("앞으로 12개월 안에 표시할 반복 일정이 없습니다.").foregroundStyle(.secondary)
            } else {
                Text("일정은 Apple 캘린더에서 관리합니다. 연결한 루틴을 누르면 앱의 하위 목록을 편집할 수 있습니다.").font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text("캘린더 루틴 · 반복 빈도").accessibilityIdentifier("calendar-recurring-section") }
        if !loading {
            ForEach(CalendarRoutineFrequency.allCases.filter { model.appleCalendar.visibleFrequencies.contains($0) }, id: \.self) { frequency in
                if !items(frequency).isEmpty {
                    Section {
                        ForEach(items(frequency)) { event in
                            if let routine = routine(event) {
                                Button { edit(routine) } label: { row(event, routine: routine) }.buttonStyle(.plain)
                            } else { row(event, routine: nil) }
                        }
                    } header: { Text("\(frequency.label) · \(frequency.detail)") }
                }
            }
            let unlisted = linked.filter { $0.status == status && CalendarRoutineIdentity.event(for: $0, in: events) == nil }
            if !unlisted.isEmpty {
                Section("연결한 루틴 · 상태 확인") {
                    ForEach(unlisted) { routine in
                        Button { edit(routine) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(routine.name).font(.headline).foregroundStyle(.primary)
                                Text(connectionText(routine)).font(.caption).foregroundStyle(.secondary)
                                Text("하위 목록과 완료 기록은 앱에 보관됩니다.").font(.caption).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                    }
                }
            }
        }
    }
    private func row(_ event: AppleCalendarEvent, routine: Routine?) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: routine == nil ? "calendar" : "calendar.badge.checkmark").foregroundStyle(.teal).font(.title2)
            VStack(alignment: .leading, spacing: 5) {
                Text(event.title).font(.headline).foregroundStyle(.primary)
                Text(event.recurrenceDescription.isEmpty ? (event.recurrence?.label ?? "반복 일정") : event.recurrenceDescription).font(.caption).foregroundStyle(.teal)
                Text("\(event.calendarTitle) · 다음 일정 \(event.start.formatted(date: .abbreviated, time: event.allDay ? .omitted : .shortened))\(event.allDay ? " · 하루 종일" : "")").font(.caption).foregroundStyle(.secondary)
                if let routine { Text("하위 목록 \(model.steps(for: routine).count)개 · 앱에 저장").font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
            if routine != nil { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary) }
        }.padding(.vertical, 5).accessibilityIdentifier("calendar-recurring-\(event.id)")
    }
    private func connectionText(_ routine: Routine) -> String {
        switch model.appleCalendar.routineConnections[routine.id] {
        case .connected: return "캘린더 연결됨 · 선택한 캘린더와 향후 일정을 확인해 주세요."
        case .noAccess: return "캘린더 접근 권한 확인 필요"
        case .ambiguous: return "연결 확인 필요 · 일치하는 일정이 여러 개입니다."
        case .missing: return "캘린더 연결 끊김 · 연결된 일정을 찾을 수 없습니다."
        case nil: return "캘린더 연결 확인 중"
        }
    }
}
