import SwiftUI
struct RootView: View {
    @Bindable var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let error = model.startupError {
                ContentUnavailableView { Label("기록을 열 수 없습니다", systemImage: "externaldrive.badge.exclamationmark") } description: { Text(error) } actions: { Button("다시 시도") { model.open() } }
            } else {
                TabView {
                    TodayView(model: model).tabItem { Label("오늘", systemImage: "sun.max") }
                    PlanningView(model: model).tabItem { Label("계획", systemImage: "calendar") }
                    RoutinesView(model: model).tabItem { Label("루틴", systemImage: "repeat") }
                    HistoryView(model: model).tabItem { Label("기록", systemImage: "chart.bar") }
                }
            }
        }
        .alert("저장하지 못했습니다", isPresented: Binding(get: { model.error != nil && model.presentedSheets == 0 }, set: { if !$0 { model.error = nil } })) { Button("확인") { model.error = nil } } message: { Text(model.error ?? "") }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refreshNotifications() } }
    }
}
struct MinutePicker: View {
    var title: String
    @Binding var minute: Int
    var body: some View {
        DatePicker(title, selection: Binding(get: { RoutineRules.calendar.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: minute/60, minute: minute%60))! }, set: { minute = RoutineRules.calendar.component(.hour, from: $0)*60 + RoutineRules.calendar.component(.minute, from: $0) }), displayedComponents: .hourAndMinute)
    }
}
struct EmptyHint: View {
    var title: String; var message: String; var symbol: String
    var body: some View { ContentUnavailableView(title, systemImage: symbol, description: Text(message)).listRowBackground(Color.clear) }
}

struct SheetSaveErrors: ViewModifier {
    let model: AppModel
    func body(content: Content) -> some View {
        content
            .onAppear { model.presentedSheets += 1 }
            .onDisappear { model.presentedSheets = max(0, model.presentedSheets - 1) }
            .alert("저장하지 못했습니다", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("확인") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
