import Foundation
import Observation
import OSLog

@MainActor @Observable final class AppleCalendarModel {
    var date = Date()
    var refreshRevision = 0
    private(set) var selectedIDs: Set<String>
    private(set) var completedEventIDs: Set<String>
    private(set) var calendars: [AppleCalendarList] = []
    private(set) var events: [AppleCalendarEvent] = []
    private(set) var hasAccess = false
    private(set) var loading = false
    private(set) var isConnecting = false
    private(set) var visibleFrequencies: Set<CalendarRoutineFrequency>
    private(set) var routineConnections: [UUID: CalendarRoutineConnection] = [:]
    private var connectionGeneration = 0
    var routineCompletion: ((AppleCalendarEvent) -> Bool?)?
    var setRoutineCompletion: ((AppleCalendarEvent, Bool) -> Bool)?
    var error: String?
    private let client: any AppleCalendarAccess
    private let defaults: UserDefaults
    private let key = "appleCalendar.selectedCalendars"
    private var generation = 0
    private let logger = Logger(subsystem: "com.hyunho.TodayRoutine", category: "Calendar")

    init(client: any AppleCalendarAccess = EventKitCalendarAccess(), defaults: UserDefaults = .standard) {
        self.client = client; self.defaults = defaults
        selectedIDs = Set(defaults.stringArray(forKey: key) ?? [])
        completedEventIDs = Set(defaults.stringArray(forKey: "appleCalendar.completedEvents") ?? [])
        visibleFrequencies = defaults.stringArray(forKey: "appleCalendar.routineFrequencies")
            .map { Set($0.compactMap(CalendarRoutineFrequency.init(rawValue:))) } ?? Set(CalendarRoutineFrequency.allCases)
    }
    func setFrequency(_ frequency: CalendarRoutineFrequency, visible: Bool) {
        if visible { visibleFrequencies.insert(frequency) } else { visibleFrequencies.remove(frequency) }
        defaults.set(visibleFrequencies.map(\.rawValue).sorted(), forKey: "appleCalendar.routineFrequencies")
    }
    func createRoutine(_ request: CalendarRoutineCreation) async throws -> CalendarRoutineLink {
        let pendingKey = "appleCalendar.pendingRoutine." + request.routineID.uuidString
        if let data = defaults.data(forKey: pendingKey), let saved = try? JSONDecoder().decode(CalendarRoutineLink.self, from: data) { return saved }
        let link = try await client.createRoutine(request)
        defaults.set(try JSONEncoder().encode(link), forKey: pendingKey)
        return link
    }
    func finishConversion(_ id: UUID) { defaults.removeObject(forKey: "appleCalendar.pendingRoutine." + id.uuidString) }
    func refreshConnections(_ routines: [Routine]) async {
        connectionGeneration += 1
        let generation = connectionGeneration
        let links = routines.compactMap { routine in routine.calendarLink.map { (routine.id, $0) } }
        var result: [UUID: CalendarRoutineConnection] = [:]
        for (id, link) in links {
            result[id] = await client.connection(link: link, routineID: id)
            guard !Task.isCancelled, generation == connectionGeneration else { return }
        }
        routineConnections = result
    }
    func isCompleted(_ event: AppleCalendarEvent) -> Bool { routineCompletion?(event) ?? completedEventIDs.contains(event.id) }
    func setCompleted(_ event: AppleCalendarEvent, completed: Bool) {
        if setRoutineCompletion?(event, completed) == true { return }
        if completed { completedEventIDs.insert(event.id) } else { completedEventIDs.remove(event.id) }
        defaults.set(Array(completedEventIDs).sorted(), forKey: "appleCalendar.completedEvents")
    }
    func connect() async {
        guard !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        do {
            let granted = try await client.requestAccess()
            logger.notice("Calendar request granted: \(granted)")
            error = granted ? nil : "캘린더 접근을 허용해 주세요. 시스템 설정의 개인정보 보호 및 보안 → 캘린더에서 변경할 수 있습니다."
            await refresh()
        } catch { self.error = error.localizedDescription }
    }
    func select(_ id: String, enabled: Bool) async {
        if enabled { selectedIDs.insert(id) } else { selectedIDs.remove(id) }
        defaults.set(Array(selectedIDs).sorted(), forKey: key)
        await refresh()
    }
    func disconnect() {
        generation += 1
        selectedIDs = []; events = []; loading = false; error = nil
        defaults.removeObject(forKey: key)
    }
    /// Independent query: Today uses its own date and Korea-based day boundaries.
    func events(on day: Date, calendar: Calendar) async -> [AppleCalendarEvent] {
        let ids = selectedIDs
        guard !ids.isEmpty else { return [] }
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let snapshot = await client.read(selectedIDs: ids, start: start, end: end)
        guard !Task.isCancelled, ids == selectedIDs, snapshot.hasAccess else { return [] }
        return snapshot.events.filter { ids.contains($0.calendarID) }
    }
    func events(inMonth day: Date) async -> [AppleCalendarEvent] {
        let ids = selectedIDs
        guard !ids.isEmpty, let range = Calendar.current.dateInterval(of: .month, for: day) else { return [] }
        let snapshot = await client.read(selectedIDs: ids, start: range.start, end: range.end)
        guard !Task.isCancelled, ids == selectedIDs, snapshot.hasAccess else { return [] }
        return snapshot.events.filter { ids.contains($0.calendarID) }
    }
    func recurringEvents(from date: Date) async -> [AppleCalendarEvent] {
        let ids = selectedIDs
        guard !ids.isEmpty, let end = Calendar.current.date(byAdding: .year, value: 1, to: date),
              let analysisEnd = Calendar.current.date(byAdding: .year, value: 2, to: date) else { return [] }
        let snapshot = await client.read(selectedIDs: ids, start: date, end: analysisEnd)
        guard !Task.isCancelled, ids == selectedIDs, snapshot.hasAccess else { return [] }
        struct SeriesKey: Hashable { let calendarID: String; let seriesID: String }
        let candidates = snapshot.events.filter { ids.contains($0.calendarID) && $0.end > date && $0.start < analysisEnd && $0.seriesID != nil }
        let series = Dictionary(grouping: candidates) { SeriesKey(calendarID: $0.calendarID, seriesID: $0.seriesID!) }
        return series.values.compactMap { occurrences -> AppleCalendarEvent? in
            let sorted = occurrences.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
            guard var next = sorted.first, next.start < end else { return nil }
            let recurrence = sorted.compactMap(\.recurrence).first
            next.recurrence = recurrence
            next.routineFrequency = recurrence?.frequency
            // Complex rules (e.g. several months in a yearly rule) are grouped by
            // their actual spacing. Ignore moved dates when the original is known.
            let dates = Array(Set(sorted.map { Calendar.current.startOfDay(for: $0.occurrenceDate ?? $0.start) })).sorted()
            let span: (Calendar.Component, Int)
            switch recurrence {
            case .daily(let n): span = (.day, n)
            case .weekly(let n): span = (.weekOfYear, n)
            case .monthly(let n): span = (.month, n)
            case .yearly(let n): span = (.year, n)
            default: span = (.year, 1)
            }
            if dates.count >= 3, span.1 > 0, let first = dates.first, let last = dates.last,
               let cycleEnd = Calendar.current.date(byAdding: span.0, value: span.1, to: first), last >= cycleEnd {
                let gaps = zip(dates, dates.dropFirst()).map { Calendar.current.dateComponents([.day], from: $0, to: $1).day ?? 0 }
                if let maxGap = gaps.max(), maxGap > 0 { next.routineFrequency = AppleCalendarRecurrence.daily(interval: maxGap).frequency }
            }
            guard next.routineFrequency != nil else { return nil }
            return next
        }.sorted { ($0.start, $0.title, $0.id) < ($1.start, $1.title, $1.id) }
    }
    func refresh() async {
        generation += 1
        let token = generation
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }
        loading = true
        events = []
        let snapshot = await client.read(selectedIDs: selectedIDs, start: start, end: end)
        logger.notice("Calendar snapshot access: \(snapshot.hasAccess), calendars: \(snapshot.calendars.count), token: \(token), current: \(self.generation)")
        guard token == generation else { return }
        hasAccess = snapshot.hasAccess
        if snapshot.hasAccess { error = nil }
        calendars = snapshot.hasAccess ? snapshot.calendars : []
        events = snapshot.hasAccess ? snapshot.events.filter { selectedIDs.contains($0.calendarID) } : []
        loading = false
    }
}
