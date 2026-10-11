import Foundation

extension AppModel {
    func configureCalendarRoutineCompletion() {
        appleCalendar.routineCompletion = { [weak self] event in
            guard let self, let routine = self.routine(for: event) else { return nil }
            return self.record(routine, date: event.start)?.status == .completed
        }
        appleCalendar.setRoutineCompletion = { [weak self] event, completed in
            guard let self, let routine = self.routine(for: event) else { return false }
            self.perform { try $0.setStatus(routineID: routine.id, date: event.start, status: completed ? .completed : .pending) }
            return true
        }
    }
    func routine(for event: AppleCalendarEvent) -> Routine? {
        let candidates = appleCalendar.events.contains(where: { $0.id == event.id }) ? appleCalendar.events : [event]
        let matches = snapshot.routines.filter { CalendarRoutineIdentity.event(for: $0, in: candidates)?.id == event.id }
        return matches.count == 1 ? matches.first : nil
    }
    func convertToCalendarRoutine(id: UUID, calendarID: String, startDay: Date, duration: Int) async -> Bool {
        guard let store, let routine = snapshot.routines.first(where: { $0.id == id }) else { return false }
        var calendarSaved = false
        do {
            let request = try CalendarRoutineCreation(routine: routine, calendarID: calendarID, startDay: startDay, duration: duration)
            let link = try await appleCalendar.createRoutine(request)
            calendarSaved = true
            try store.linkCalendarRoutine(id: id, link: link)
            try reload()
            appleCalendar.finishConversion(id)
            sync?.localDataDidChange()
            refreshNotifications()
            await appleCalendar.select(link.calendarID, enabled: true)
            await appleCalendar.refreshConnections(snapshot.routines)
            return true
        } catch {
            self.error = calendarSaved
                ? "캘린더 일정은 생성됐지만 앱 연결을 저장하지 못했습니다. 다시 전환하면 생성된 일정에 연결합니다. \(error.localizedDescription)"
                : error.localizedDescription
            return false
        }
    }
}
