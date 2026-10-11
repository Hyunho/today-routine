import SwiftUI
import EventKit

extension AppleCalendarEvent {
    var calendarColor: Color {
        let rgb = colorComponents
        return rgb.count >= 3 ? Color(red: rgb[0], green: rgb[1], blue: rgb[2]) : .teal
    }
}

struct CalendarColorIndicator: View {
    let event: AppleCalendarEvent

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(event.calendarColor)
            .frame(width: 4, height: 28)
            .accessibilityHidden(true)
    }
}

struct TodayCalendarLoader: ViewModifier {
    let calendar: AppleCalendarModel
    let date: Date
    @Binding var events: [AppleCalendarEvent]
    @State private var revision = 0
    @Environment(\.scenePhase) private var phase
    private struct Query: Hashable {
        let day: Date
        let ids: Set<String>
        let revision: Int
        let manualRevision: Int
        let active: Bool
    }
    func body(content: Content) -> some View {
        content
        .task(id: Query(day: RoutineRules.calendar.startOfDay(for: date), ids: calendar.selectedIDs, revision: revision, manualRevision: calendar.refreshRevision, active: phase == .active)) {
            guard phase == .active else { return }
            events = []
            let result = await calendar.events(on: date, calendar: RoutineRules.calendar)
            guard !Task.isCancelled else { return }
            events = result
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in revision += 1 }
    }
}
