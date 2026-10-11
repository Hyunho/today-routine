import SwiftUI

struct CalendarRoutineConversionView: View {
    let model: AppModel
    let routineID: UUID
    @State private var calendarID = ""
    @State private var startDay = Date()
    @State private var duration = 30
    @State private var saving = false
    @State private var confirmation = false
    @State private var errorMessage: String?
    @Environment(\.dismiss) private var dismiss
    private var routine: Routine? { model.snapshot.routines.first { $0.id == routineID } }
    private var calendars: [AppleCalendarList] { model.appleCalendar.calendars.filter(\.writable) }
    var body: some View {
        NavigationStack {
            Form {
                if let routine {
                    Section("전환할 루틴") {
                        Text(routine.name).font(.headline)
                        Text(routine.repeatKind == .daily ? "매일" : "선택한 요일마다 반복")
                        Text(routine.minute == nil ? "하루 종일" : RoutineRules.timeLabel(routine.minute))
                    }
                    if !model.appleCalendar.hasAccess {
                        Button("Apple 캘린더 연결") { Task { await model.appleCalendar.connect(); selectInitialCalendar() } }
                            .disabled(model.appleCalendar.isConnecting)
                        if let error = model.appleCalendar.error { Text(error).foregroundStyle(.orange) }
                    } else {
                        Section("새 반복 일정") {
                            if calendars.isEmpty { Text("일정을 추가할 수 있는 캘린더가 없습니다.").foregroundStyle(.secondary) }
                            Picker("저장할 캘린더", selection: $calendarID) {
                                Text("선택해 주세요").tag("")
                                ForEach(calendars) { Text("\($0.title) · \($0.source)").tag($0.id) }
                            }
                            DatePicker("시작일", selection: $startDay, in: RoutineRules.calendar.startOfDay(for: Date())..., displayedComponents: .date)
                            if routine.minute != nil { Stepper("소요 시간 \(duration)분", value: $duration, in: 15...240, step: 15) }
                        }
                    }
                    Section {
                        Text("제목·시간·반복은 Apple 캘린더에서 관리합니다. 하위 목록과 완료 기록은 이 앱에 그대로 남습니다.")
                        Text("일정 알림은 전환 후 Apple 캘린더에서 설정해 주세요.").font(.caption).foregroundStyle(.secondary)
                        Text("다른 기기에서도 연결 정보를 사용하려면 해당 기기의 앱도 업데이트해 주세요.").font(.caption).foregroundStyle(.secondary)
                        Button("캘린더 루틴으로 전환") { confirmation = true }
                            .disabled(saving || calendarID.isEmpty || !model.appleCalendar.hasAccess)
                        if saving { ProgressView("반복 일정 생성 및 연결 중") }
                        if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.orange) }
                    }
                }
            }
            .disabled(saving)
            .navigationTitle("캘린더 루틴으로 전환")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() }.disabled(saving) } }
            .task { await model.appleCalendar.refresh(); selectInitialCalendar() }
            .confirmationDialog("Apple 캘린더에 반복 일정을 만들까요?", isPresented: $confirmation, titleVisibility: .visible) {
                Button("반복 일정 생성 및 전환") {
                    saving = true
                    errorMessage = nil
                    Task {
                        if await model.convertToCalendarRoutine(id: routineID, calendarID: calendarID, startDay: startDay, duration: duration) { dismiss() }
                        else { errorMessage = model.error; model.error = nil }
                        saving = false
                    }
                }
            } message: { Text("선택한 캘린더에 새 일정이 저장됩니다. 하위 목록과 완료 기록은 유지됩니다.") }
        }
        .interactiveDismissDisabled(saving)
        .platformSheetSize()
        .formStyle(.grouped)
    }
    private func selectInitialCalendar() {
        guard calendarID.isEmpty else { return }
        calendarID = calendars.first(where: { model.appleCalendar.selectedIDs.contains($0.id) })?.id ?? calendars.first?.id ?? ""
    }
}
