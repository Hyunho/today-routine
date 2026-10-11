import SwiftUI
import Combine
private struct TodayEntry: Identifiable {
    let routine: Routine?; var block: TimeBlock? = nil; var dayMinute: Int? = nil; var event: AppleCalendarEvent? = nil; var calendarEndMinute: Int? = nil; var reminder: AppleReminderItem? = nil
    var id: String { routine.map { "routine-\($0.id)" } ?? event.map { "calendar-\($0.id)" } ?? reminder.map { "reminder-\($0.id)" } ?? "block-\(block!.id)" }
    var durationMinutes: Int? {
        if let start = minute, let end = calendarEndMinute ?? block?.endMinute { return max(0, end - start) }
        return routine?.calendarLink == nil ? routine?.durationMinutes : nil
    }
    var endMinute: Int? {
        calendarEndMinute ?? block?.endMinute ?? RoutineRules.endMinute(start: minute, duration: durationMinutes)
    }
    var minute: Int? { routine?.calendarLink != nil ? dayMinute : dayMinute ?? routine?.minute ?? block?.startMinute }
}
struct TodayView: View {
    let model: AppModel
    var isLogseqReading = false
    var openSettingsPanel: (() -> Void)? = nil
    #if os(macOS)
    var sharedDocumentHost: TodayDocumentHost? = nil
    var sharedDocumentDate: Binding<Date>? = nil
    // TodayDocumentEditorView observes changes; this container only owns the host.
    @State private var localDocumentHost = TodayDocumentHost()
    private var documentHost: TodayDocumentHost { sharedDocumentHost ?? localDocumentHost }
    private var documentDate: Binding<Date> {
        Binding(get: { date }, set: { next in Task { if await documentHost.apply() { date = next } } })
    }
    #endif
    private var scheduleView: String { isLogseqReading ? "Logseq 읽기" : "목록" }
    @AppStorage("today.cylinderEffect") private var cylinderEffect = false
    @State private var draggedID: String?
    @State private var dragMinute: Int?
    @State private var dragDay: Date?
    @State private var minuteChoice = 540
    @State private var selectedRoutine: Routine?
    @State private var routineReturnTab: String?
    @State private var detailDraft: RoutineDraft?
    @State private var reminderDraft: AppleReminderDraft?
    @State private var calendarEvents: [AppleCalendarEvent] = []
    @State private var selectedCalendarEvent: AppleCalendarEvent?
    @State private var selectedBlock: BlockDraft?
    @State private var deleteBlock: UUID?
    @State private var localDate = Date()
    private var date: Date {
        get {
            #if os(macOS)
            return sharedDocumentDate?.wrappedValue ?? localDate
            #else
            return localDate
            #endif
        }
        nonmutating set {
            #if os(macOS)
            if let sharedDocumentDate { sharedDocumentDate.wrappedValue = newValue; return }
            #endif
            localDate = newValue
        }
    }
    private var dateSelection: Binding<Date> { Binding(get: { date }, set: { date = $0 }) }
    @State private var lastToday = Date()
    @State private var currentTime = Date()
    @Environment(\.scenePhase) private var scenePhase
    private var isPast: Bool { RoutineRules.dayKey(date) < RoutineRules.dayKey(Date()) }
    private func refreshDay() { let now = Date(); date = RoutineRules.refreshedSelection(date, previousToday: lastToday, now: now); lastToday = now }
    private func floatingWeekly(_ r: Routine) -> Bool { r.repeatKind == .weeklyGoal && model.record(r, date: date)?.minuteOverride == nil }
    private func linkedEvent(_ r: Routine) -> AppleCalendarEvent? { CalendarRoutineIdentity.event(for: r, in: calendarEvents) }
    private func minute(_ r: Routine) -> Int? {
        if r.calendarLink != nil { return linkedEvent(r)?.timelineMinutes(on: date, calendar: RoutineRules.calendar)?.start }
        return RoutineRules.minute(r, records: model.snapshot.records, on: date)
    }
    private func routineEntry(_ r: Routine) -> TodayEntry {
        let event = linkedEvent(r)
        return TodayEntry(routine: r, dayMinute: minute(r), event: event, calendarEndMinute: event?.timelineMinutes(on: date, calendar: RoutineRules.calendar)?.end)
    }
    private var unlinkedCalendarEvents: [AppleCalendarEvent] {
        let linkedIDs = Set(model.snapshot.routines.filter { $0.status == .active }.compactMap { linkedEvent($0)?.id })
        return calendarEvents.filter { !linkedIDs.contains($0.id) }
    }
    private func displayName(_ r: Routine) -> String { isPast ? (model.record(r, date: date)?.nameSnapshot ?? linkedEvent(r)?.title ?? r.name) : (linkedEvent(r)?.title ?? r.name) }
    @State private var aboveViewport: Set<String> = []
    @State private var completingReminderIDs: Set<String> = []
    @State private var expanded: Set<UUID> = []
    @State private var settings = false
    @State private var draft: RoutineDraft?
    private var routines: [Routine] {
        let hidden = model.snapshot.todayDocuments.first { $0.dayKey == RoutineRules.dayKey(date) }?.hiddenRoutineIDs ?? []
        return model.snapshot.routines.filter { !hidden.contains($0.id) && (RoutineRules.visible($0, records: model.snapshot.records, on: date, now: Date()) || ($0.status == .active && linkedEvent($0) != nil)) }
    }
    private func status(_ r: Routine) -> DayStatus { model.record(r, date: date)?.status ?? .pending }
    private var dueReminders: [AppleReminderItem] { model.appleReminders.due(on: date) }
    private var completed: Int { routines.filter { status($0) == .completed }.count + dueReminders.filter { $0.completed }.count + unlinkedCalendarEvents.filter { model.appleCalendar.isCompleted($0) }.count }
    private var calendarEntries: [TodayEntry] {
        unlinkedCalendarEvents.compactMap { event in
            guard let time = event.timelineMinutes(on: date, calendar: RoutineRules.calendar) else { return nil }
            return TodayEntry(routine: nil, dayMinute: time.start, event: event, calendarEndMinute: time.end)
        }
    }
    private var entries: [TodayEntry] {
        let r = routines.filter { !floatingWeekly($0) && linkedEvent($0)?.allDay != true }.map(routineEntry)
        return (r+calendarEntries).sorted { if ($0.minute ?? Int.max) != ($1.minute ?? Int.max) { return ($0.minute ?? Int.max) < ($1.minute ?? Int.max) }; return $0.id < $1.id }
    }
    private var dayBlocks: [TimeBlock] { model.snapshot.blocks.filter { $0.dayKey == RoutineRules.dayKey(date) } }
    private var allTimed: [TodayEntry] {
        (routines.filter { minute($0) != nil && !floatingWeekly($0) }.map(routineEntry)
         + dayBlocks.map { TodayEntry(routine: nil, block: $0) } + calendarEntries)
            .sorted { $0.minute == $1.minute ? $0.id < $1.id : ($0.minute ?? 0) < ($1.minute ?? 0) }
    }
    private var agendaSegments: [AgendaSegment] {
        AgendaLayout.segments(allTimed.map { e in
            TimelineInterval(id: e.id, start: e.minute!, end: e.endMinute ?? e.minute!)
        })
    }
    private var currentMinute: Int? {
        guard RoutineRules.dayKey(date) == RoutineRules.dayKey(currentTime) else { return nil }
        return RoutineRules.calendar.component(.hour, from: currentTime) * 60 + RoutineRules.calendar.component(.minute, from: currentTime)
    }
    private var scrollActivation: String { "\(model.selectedTab)-\(scheduleView)-\(RoutineRules.dayKey(date))" }
    private var outlineSections: [TodayOutlineSection] {
        let allDay = routines.filter { linkedEvent($0)?.allDay == true }.map(routineEntry)
            + unlinkedCalendarEvents.filter(\.allDay).map { TodayEntry(routine: nil, event: $0) }
        let untimed = entries.filter { $0.minute == nil }
        let weekly = RoutineRules.timeSorted(routines.filter { floatingWeekly($0) && linkedEvent($0)?.allDay != true }).map(routineEntry)
        return [
            TodayOutlineSection(title: "미리 알림", rows: dueReminders.map { outlineRow(TodayEntry(routine: nil, reminder: $0)) }),
            TodayOutlineSection(title: "하루 종일", rows: allDay.map(outlineRow)),
            TodayOutlineSection(title: "시간 미정", rows: untimed.map(outlineRow)),
            TodayOutlineSection(title: "시간순", rows: allTimed.map(outlineRow)),
            TodayOutlineSection(title: "이번 주 목표", rows: weekly.map(outlineRow))
        ].filter { !$0.rows.isEmpty }
    }
    private func outlineRow(_ entry: TodayEntry) -> TodayOutlineRow {
        var details: [String] = []
        var time = ""
        var children: [TodayOutlineRow] = []
        let dayStatus: DayStatus?
        if let routine = entry.routine {
            dayStatus = status(routine)
            details.append(routine.calendarLink == nil ? "루틴" : "캘린더 루틴")
            if floatingWeekly(routine) {
                details.append("이번 주 \(RoutineRules.completedCount(routineID: routine.id, records: model.snapshot.records, week: date))/\(routine.weeklyTarget)회")
            }
            let completedSteps = Set(model.record(routine, date: date)?.completedStepIDs ?? [])
            children = model.steps(for: routine).map {
                TodayOutlineRow(id: $0.id.uuidString, title: $0.name,
                                status: completedSteps.contains($0.id) ? .completed : .pending, detail: "")
            }
        } else if let reminder = entry.reminder {
            dayStatus = reminder.completed ? .completed : .pending
            details.append(reminder.listTitle)
        } else if let event = entry.event {
            dayStatus = model.appleCalendar.isCompleted(event) ? .completed : .pending
        } else {
            dayStatus = nil
            details.append("시간 블록")
        }
        if let event = entry.event { details.append(event.calendarTitle) }
        if entry.event?.allDay == true {
            time = "종일"
            details.insert("하루 종일", at: 0)
        } else if let start = entry.reminder?.minute ?? entry.minute {
            time = RoutineRules.timeLabel(start)
            let end = entry.endMinute
            details.insert(RoutineRules.timeLabel(start) + (end.map { "–" + RoutineRules.timeLabel($0) } ?? ""), at: 0)
        }
        return TodayOutlineRow(id: entry.id, title: title(entry), status: dayStatus,
                               detail: details.joined(separator: " · "), time: time, children: children,
                               editable: entry.block != nil || (entry.routine != nil && entry.routine?.calendarLink == nil && !isPast))
    }
    var body: some View {
        NavigationStack {
            #if os(macOS)
            if isLogseqReading {
                VStack(spacing: 0) {
                    DatePicker("날짜", selection: documentDate, displayedComponents: .date).padding(.horizontal).padding(.top)
                    TodayDocumentEditorView(host: documentHost, model: model, day: RoutineRules.dayKey(date))
                }.navigationTitle("Logseq")
            } else { regularContent }
            #else
            regularContent
            #endif
        }
    }
    private var regularContent: some View {
            ScrollViewReader { scroll in
            ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                TodayListSection {
                    DatePicker("날짜", selection: dateSelection, displayedComponents: .date)
                    HStack { VStack(alignment: .leading, spacing: 8) { Text("작은 실천이 만드는 하루").font(.subheadline).foregroundStyle(.secondary); Text("완료 \(completed)개").font(.title2.bold()); Text("남은 항목 \(routines.filter { status($0) == .pending }.count + dueReminders.filter { !$0.completed }.count + unlinkedCalendarEvents.filter { !model.appleCalendar.isCompleted($0) }.count)개").font(.subheadline) }; Spacer(); Image(systemName: "sun.max.fill").font(.largeTitle).foregroundStyle(.orange) }.padding(.vertical,8)
                }
                if isLogseqReading {
                    TodayListSection {
                        LogseqReadingView(heading: RoutineRules.dayKey(date), sections: outlineSections,
                                              isActive: model.selectedTab == "Logseq") { id in
                            scroll.scrollTo("today-outline-" + id, anchor: .center)
                        }
                    }
                } else {
                if !dueReminders.isEmpty {
                    TodayListSection("이 날짜 마감 · 미리 알림") {
                        ForEach(dueReminders) { item in
                            AppleReminderRow(item: item, reminders: model.appleReminders, showsDisclosure: false, completionLeading: false) { reminderDraft = AppleReminderDraft(item) }
                            .modifier(stackTracking("reminder-" + item.id))
                            .modifier(TodayCylinderEffect(enabled: cylinderEffect && scheduleView == "목록"))
                            #if os(macOS)
                            .contextMenu {
                                Button("상세 보기", systemImage: "info.circle") { reminderDraft = AppleReminderDraft(item) }
                                Button(item.completed ? "완료 취소" : "완료", systemImage: "checkmark.circle") {
                                    Task { await model.appleReminders.complete(item) }
                                }
                            }
                            #endif
                        }
                    }
                }
                let allDayEvents = unlinkedCalendarEvents.filter { $0.allDay }
                let allDayRoutines = routines.filter { linkedEvent($0)?.allDay == true }
                if !allDayEvents.isEmpty || !allDayRoutines.isEmpty {
                    TodayListSection("하루 종일") {
                        ForEach(allDayRoutines) { routineRow($0) }
                        ForEach(allDayEvents) { event in calendarRow(TodayEntry(routine: nil, event: event)) }
                    }
                }
                if scheduleView == "시간 블록" {
                    let untimedRoutines = routines.filter { minute($0) == nil && !floatingWeekly($0) && linkedEvent($0)?.allDay != true }
                    if !untimedRoutines.isEmpty { TodayListSection("시간 미정") { ForEach(untimedRoutines) { routineRow($0) } } }
                    TodayListSection {
                        Text("블록을 위아래로 끌어 시간을 변경하세요. 아이폰에서는 길게 누른 뒤 이동하세요.").font(.caption).foregroundStyle(.secondary)
                        timeGrid
                    }
                    let weekly = routines.filter { floatingWeekly($0) }
                    if !weekly.isEmpty { TodayListSection("이번 주 목표") { ForEach(weekly) { routineRow($0) } } }
                } else {
                if routines.isEmpty && dueReminders.isEmpty && calendarEvents.isEmpty { EmptyHint(title: "오늘의 리듬을 시작해요", message: "루틴을 추가하면 이곳에 오늘 할 일이 모입니다.", symbol: "sun.horizon"); Button("첫 루틴 추가", systemImage: "plus") { draft = RoutineDraft() } }
                let untimed = entries.filter { $0.minute == nil }
                if !untimed.isEmpty { TodayListSection("시간 미정 · \(untimed.count)") { ForEach(untimed) { entry($0) } } }
                TodayListSection("시간순 · \(allTimed.count)") {
                    AgendaTimeline(segments: agendaSegments, currentMinute: currentMinute, cylinderEffect: cylinderEffect, layout: model.listLayout) { segment in
                        if let item = allTimed.first(where: { $0.id == segment.id }) {
                            entry(item, minimumHeight: segment.height(using: model.listLayout))
                        }
                    }
                }
                let weekly = routines.filter { floatingWeekly($0) }
                if !weekly.isEmpty { TodayListSection("이번 주 목표") { ForEach(RoutineRules.timeSorted(weekly)) { r in
                    routineRow(r)
                } } }

                }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            }
            .coordinateSpace(name: "todayListViewport")
            .task(id: scrollActivation) {
                guard !isLogseqReading, model.selectedTab == "오늘", RoutineRules.dayKey(date) == RoutineRules.dayKey(Date()) else { return }
                currentTime = Date()
                do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                guard !Task.isCancelled, selectedRoutine == nil, model.todayRoutineRoute == nil else { return }
                scroll.scrollTo("today-current-time", anchor: .center)
            }
            .overlay(alignment: .top) {
                GeometryReader { geometry in
                    pendingStack(scroll: scroll, viewportHeight: geometry.size.height)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
            }
            .coordinateSpace(name: "todayCylinderViewport")
            .onChange(of: RoutineRules.dayKey(date)) { _, _ in aboveViewport = [] }
            .onChange(of: scheduleView) { _, _ in aboveViewport = [] }
            .modifier(MobileSyncRefresh(model: model)).navigationTitle(isLogseqReading ? "Logseq" : "오늘")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button {
                if let openSettingsPanel { openSettingsPanel() }
                else { settings = true }
            } label: { Image(systemName: "gearshape") }.accessibilityLabel("설정") } }
            .toolbar { if !isLogseqReading { ToolbarItem(placement: .primaryAction) { Button { var d = BlockDraft(); d.dayKey = RoutineRules.dayKey(date); selectedBlock = d } label: { Label("시간 블록 추가", systemImage: "plus") } } } }
            .confirmationDialog("이 시간 블록을 삭제할까요?", isPresented: Binding(get: { deleteBlock != nil }, set: { if !$0 { deleteBlock = nil } })) {
                Button("삭제", role: .destructive) { if let id = deleteBlock { model.perform { try $0.deleteBlock(id: id) } }; deleteBlock = nil }
            }
            .modifier(TodayCalendarLoader(calendar: model.appleCalendar, date: date, events: $calendarEvents))
            .sheet(item: $selectedCalendarEvent) { CalendarEventDetail(event: $0, calendar: model.appleCalendar) }
            .sheet(item: $reminderDraft) { AppleReminderEditor(reminders: model.appleReminders, draft: $0) }
            .modifier(AppleRemindersErrors(reminders: model.appleReminders, enabled: reminderDraft == nil && !settings))
            .sheet(item: $selectedBlock) { TimeBlockEditor(model: model, draft: $0) }
            .navigationDestination(isPresented: Binding(
                get: { selectedRoutine != nil },
                set: { if !$0 { dismissRoutineDetail() } }
            )) {
                if let routine = selectedRoutine { routineDetail(routine) }
            }
            .task(id: model.todayRoutineRoute?.id) {
                guard !isLogseqReading, let route = model.todayRoutineRoute,
                      let routine = model.snapshot.routines.first(where: { $0.id == route.routineID }) else { return }
                date = route.date
                minuteChoice = RoutineRules.minute(routine, records: model.snapshot.records, on: route.date) ?? 540
                routineReturnTab = route.returnTab
                selectedRoutine = routine
                model.todayRoutineRoute = nil
            }
            .onChange(of: scenePhase) { _, phase in if phase == .active { refreshDay() } }
            .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in currentTime = Date(); refreshDay() }
            .sheet(isPresented: $settings) { SettingsView(model: model) }
            .sheet(item: $draft) { RoutineEditor(model: model, draft: $0) }
            }
    }
    private func stackTracking(_ id: String) -> PendingStackTracking {
        PendingStackTracking(id: id, enabled: scheduleView == "목록") { id, above in
            if above { aboveViewport.insert(id) } else { aboveViewport.remove(id) }
        }
    }
    private var stackedEntries: [TodayEntry] {
        guard scheduleView == "목록" else { return [] }
        let reminders = dueReminders.map { TodayEntry(routine: nil, reminder: $0) }
        let allDay = unlinkedCalendarEvents.filter { $0.allDay }.map { TodayEntry(routine: nil, event: $0) }
            + routines.filter { linkedEvent($0)?.allDay == true }.map(routineEntry)
        let weekly = RoutineRules.timeSorted(routines.filter { floatingWeekly($0) }).map { TodayEntry(routine: $0) }
        return (reminders + allDay + entries + weekly).filter { aboveViewport.contains($0.id) && !isDone($0) }
    }
    @ViewBuilder private func pendingStack(scroll: ScrollViewProxy, viewportHeight: CGFloat) -> some View {
        let pending = stackedEntries
        if !pending.isEmpty {
            VStack(spacing: 4) {
                ForEach(Array(pending.prefix(3))) { item in
                    HStack(spacing: 8) {
                        Button {
                            withAnimation { scroll.scrollTo(item.id, anchor: .center) }
                        } label: {
                            HStack {
                                if let event = item.event { CalendarColorIndicator(event: event) }
                                durationLabel(item)
                                Text(title(item)).font(.subheadline.weight(.medium)).lineLimit(1)
                                Spacer(minLength: 4)
                                Image(systemName: "arrow.up.to.line").font(.caption)
                            }.frame(maxWidth: .infinity, minHeight: 36).contentShape(Rectangle())
                        }.buttonStyle(.plain).accessibilityLabel("\(title(item)) 원래 위치로 이동")
                        if let reminder = item.reminder {
                            Button {
                                completingReminderIDs.insert(reminder.id)
                                Task { _ = await model.appleReminders.complete(reminder); completingReminderIDs.remove(reminder.id) }
                            } label: { Image(systemName: "circle").font(.title3) }
                                .buttonStyle(.borderless)
                                .disabled(!reminder.writable || completingReminderIDs.contains(reminder.id))
                                .accessibilityLabel("상단 \(title(item)) 완료")
                        } else { completionButton(item).accessibilityLabel("상단 \(title(item)) 완료") }
                    }
                    .padding(.horizontal, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.teal.opacity(0.3)))
                    .modifier(TodayCylinderEffect(enabled: cylinderEffect, fixedViewportHeight: viewportHeight))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("pending-stack-" + item.id)
                }
                if pending.count > 3 {
                    Menu("미완료 \(pending.count - 3)개 더 보기") {
                        ForEach(Array(pending.dropFirst(3))) { item in
                            Button(title(item)) { withAnimation { scroll.scrollTo(item.id, anchor: .center) } }
                        }
                    }.font(.caption).padding(6).background(.regularMaterial, in: Capsule())
                        .modifier(TodayCylinderEffect(enabled: cylinderEffect, fixedViewportHeight: viewportHeight))
                }
            }.padding(.horizontal, 12).padding(.top, 4)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("지나간 미완료 작업")
        }
    }
    private func title(_ e: TodayEntry) -> String { e.routine.map(displayName) ?? e.block?.title ?? e.event?.title ?? e.reminder?.title ?? "" }
    private func saveDayTime(_ r: Routine) {
        if model.perform({ try $0.setDayMinute(routineID: r.id, date: date, minute: minuteChoice) }) { dismissRoutineDetail() }
    }
    private func dismissRoutineDetail() {
        selectedRoutine = nil
        let returnTab = routineReturnTab
        routineReturnTab = nil
        if let returnTab, model.selectedTab == "오늘" { Task { await model.selectTab(returnTab) } }
    }
    private func showDayTime(_ r: Routine) { minuteChoice = minute(r) ?? 540; selectedRoutine = r }
    private func open(_ e: TodayEntry) {
        if let r = e.routine { showDayTime(r) }
        else if let b = e.block { selectedBlock = BlockDraft(b) }
        else if let event = e.event { selectedCalendarEvent = event }
    }
    private func isDone(_ e: TodayEntry) -> Bool { e.routine.map { status($0) != .pending } ?? e.event.map { model.appleCalendar.isCompleted($0) } ?? e.reminder?.completed ?? false }
    private func updateDrag(_ e: TodayEntry, translation: CGFloat) {
        guard let start = e.minute else { return }
        if draggedID == nil { dragDay = date }
        draggedID = e.id
        dragMinute = TimelineLayout.movedStart(start: start, duration: e.block.map { $0.endMinute - $0.startMinute } ?? 0, translation: Double(translation))
    }
    private func finishDrag(_ e: TodayEntry) {
        defer { draggedID = nil; dragMinute = nil; dragDay = nil }
        guard let newMinute = dragMinute, newMinute != e.minute, let targetDay = dragDay else { return }
        if let r = e.routine {
            model.perform { try $0.setDayMinute(routineID: r.id, date: targetDay, minute: newMinute) }
        } else if let b = e.block {
            var d = BlockDraft(b); let duration = d.endMinute - d.startMinute
            d.startMinute = newMinute; d.endMinute = newMinute + duration
            model.perform { try $0.upsertBlock(d) }
        }
    }
    private func dragGesture(_ e: TodayEntry) -> some Gesture {
        #if os(macOS)
        DragGesture(minimumDistance: 8, coordinateSpace: .named("dayTimeline"))
            .onChanged { updateDrag(e, translation: $0.translation.height) }
            .onEnded { value in updateDrag(e, translation: value.translation.height); finishDrag(e) }
        #else
        LongPressGesture(minimumDuration: 0.35).sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("dayTimeline")))
            .onChanged { value in if case .second(true, let drag?) = value { updateDrag(e, translation: drag.translation.height) } }
            .onEnded { value in
                if case .second(true, let drag?) = value { updateDrag(e, translation: drag.translation.height); finishDrag(e) }
                else { draggedID = nil; dragMinute = nil; dragDay = nil }
            }
        #endif
    }
    private var timeGrid: some View {
        let entries = allTimed
        let placements = TimelineLayout.place(entries.map { e in
            TimelineInterval(id: e.id, start: e.minute!, end: e.endMinute ?? e.minute!)
        }, startMinute: 0, endMinute: 1440)
        return GeometryReader { geometry in
            let width = max(100, geometry.size.width - 58)
            ZStack(alignment: .topLeading) {
                ForEach(0...24, id: \.self) { hour in
                    HStack(spacing: 10) { Text(String(format: "%02d:00", hour)).font(.caption).monospacedDigit().foregroundStyle(.secondary).frame(width: 46); Rectangle().fill(Color.secondary.opacity(0.2)).frame(height: 1) }
                        .offset(y: CGFloat(hour * 60) * 2)
                }
                ForEach(placements) { p in
                    if let e = entries.first(where: { $0.id == p.id }) {
                        HStack(spacing: 2) {
                            if e.event != nil { detailButton(e) }
                            else { detailButton(e).simultaneousGesture(dragGesture(e)) }
                            completionButton(e)
                        }
                        .padding(.horizontal, 4)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background((e.event?.calendarColor ?? (e.block == nil ? Color.orange : Color.teal)).opacity(isDone(e) ? 0.08 : 0.18), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(alignment: .bottomTrailing) {
                            if draggedID == e.id, let proposed = dragMinute {
                                Text(RoutineRules.timeLabel(proposed)).font(.caption.bold()).padding(3).background(.regularMaterial, in: Capsule()).allowsHitTesting(false)
                            }
                        }
                        .contextMenu { entryMenu(e) }
                        .frame(width: width / CGFloat(p.columns) - 4, height: max(18, CGFloat(p.end - p.start) * 2 - 2))
                        .clipped()
                        .offset(x: 58 + CGFloat(p.column) * width / CGFloat(p.columns), y: CGFloat(p.start) * 2 + (draggedID == e.id ? CGFloat((dragMinute ?? e.minute!) - e.minute!) * 2 : 0))
                        .zIndex(draggedID == e.id ? 2 : 0)
                    }
                }
                if let minute = currentMinute {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(0, CGFloat(minute) * 2 - 8))
                        HStack(spacing: 0) {
                            Text(RoutineRules.timeLabel(minute)).font(.caption2.bold())
                                .foregroundStyle(.red).padding(.horizontal, 3).background(.background, in: Capsule())
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Rectangle().fill(.red).frame(height: 2)
                        }
                        .frame(height: 16)
                        .id("today-current-time")
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("현재 시간 \(RoutineRules.timeLabel(minute))")
                        .accessibilityIdentifier("today-current-time")
                        Spacer(minLength: 0)
                    }.allowsHitTesting(false)
                }
            }
        }.frame(height: 2895).coordinateSpace(name: "dayTimeline")
        .onChange(of: date) { _, _ in draggedID = nil; dragMinute = nil; dragDay = nil }
    }
    @ViewBuilder private func entry(_ e: TodayEntry, minimumHeight: CGFloat = 0) -> some View {
        if let r = e.routine { routineRow(r, minimumHeight: minimumHeight) }
        else if e.event != nil { calendarRow(e, minimumHeight: minimumHeight) }
        else if e.block != nil {
            detailButton(e, showsTime: false).padding(12).frame(minHeight: minimumHeight)
                .modifier(TodayCylinderEffect(enabled: cylinderEffect && scheduleView == "목록" && minimumHeight == 0))
                .contextMenu { entryMenu(e) }
        }
    }
    private func routineRow(_ r: Routine, minimumHeight: CGFloat = 0) -> some View {
        let canExpand = !isPast && !model.steps(for: r).isEmpty
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                if let event = linkedEvent(r) { CalendarColorIndicator(event: event) }
                Button { showDayTime(r) } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            if linkedEvent(r)?.allDay != true { durationLabel(routineEntry(r)) }
                            Text(displayName(r)).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        }
                        if minimumHeight == 0 { Text(linkedEvent(r)?.allDay == true ? "하루 종일 · 캘린더 루틴" : floatingWeekly(r) ? "이번 주 \(RoutineRules.completedCount(routineID: r.id, records: model.snapshot.records, week: date))/\(r.weeklyTarget)회" : RoutineRules.timeLabel(minute(r))).font(.caption).foregroundStyle(.secondary) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(r.name) 상세 보기")
                if canExpand {
                    Button {
                        if expanded.contains(r.id) { expanded.remove(r.id) } else { expanded.insert(r.id) }
                    } label: {
                        HStack(spacing: 5) {
                            Text("\(model.record(r, date: date)?.completedStepIDs.count ?? 0)/\(model.steps(for: r).count)")
                                .font(.caption).monospacedDigit().fixedSize()
                            Image(systemName: expanded.contains(r.id) ? "chevron.down" : "chevron.right")
                                .font(.caption)
                        }
                        .foregroundStyle(.secondary).frame(minWidth: 44, minHeight: 44)
                        .padding(.trailing, 8).contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel("\(r.name) 단계 보기")
                        .accessibilityValue(expanded.contains(r.id) ? "펼침" : "접힘")
                }
                completionButton(TodayEntry(routine: r))
            }
            if canExpand && expanded.contains(r.id) {
                VStack(alignment: .leading, spacing: 4) { routineSteps(r) }
                    .padding(.leading, 12)
                    .padding(.trailing, 58)
            }
        }.padding(.vertical,5)
        .frame(minHeight: minimumHeight)
        .modifier(stackTracking("routine-" + r.id.uuidString))
        .modifier(TodayCylinderEffect(enabled: cylinderEffect && scheduleView == "목록" && minimumHeight == 0))
        #if os(macOS)
        .contextMenu { entryMenu(TodayEntry(routine: r)) }
        #endif
    }
    private func startFocus(_ entry: TodayEntry) {
        let target: FocusSession.Target
        if let r = entry.routine { target = .routine(r.id) }
        else if let b = entry.block { target = .block(b.id) }
        else { return }
        dismissRoutineDetail()
        Task { await model.setFocusSession(FocusSession(target: target, title: title(entry), day: date)) }
    }
    private func routineSteps(_ r: Routine) -> some View {
        ForEach(model.steps(for: r)) { step in
            Button { model.perform { try $0.toggleStep(routineID: r.id, stepID: step.id, date: date) } } label: {
                Label(step.name, systemImage: model.record(r, date: date)?.completedStepIDs.contains(step.id) == true ? "checkmark.square.fill" : "square")
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 6)
            }.buttonStyle(.borderless)
        }
    }
    private func routineDetail(_ original: Routine) -> some View {
        let r = model.snapshot.routines.first { $0.id == original.id } ?? original
        return List {
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(displayName(r)).font(.title2.bold())
                            Text("\(RoutineRules.dayKey(date)) · \(linkedEvent(r)?.allDay == true ? "하루 종일" : RoutineRules.timeLabel(minute(r)))").foregroundStyle(.secondary)
                        }
                        Spacer()
                        completionButton(TodayEntry(routine: r))
                    }
                    if !isPast && !r.note.isEmpty { Text(r.note) }
                }
                if !isPast && !model.steps(for: r).isEmpty { Section("하위 단계") { routineSteps(r) } }
                if r.calendarLink != nil {
                    Section("캘린더 루틴") { Text("시간과 반복은 Apple 캘린더에서 변경해 주세요. 하위 목록과 완료 상태는 앱에 저장됩니다.") }
                } else { Section("이 날짜의 시간 변경") {
                    Text("이 날짜에만 적용됩니다. 기본 반복 시간은 바뀌지 않습니다.").font(.caption).foregroundStyle(.secondary)
                    MinutePicker(title: "시작 시간", minute: $minuteChoice)
                    Button("이 날짜의 시간 저장") { saveDayTime(r) }
                    if model.record(r, date: date)?.minuteOverride != nil {
                        Button("기본 시간으로 복원 (\(RoutineRules.timeLabel(r.minute)))") {
                            if model.perform({ try $0.setDayMinute(routineID: r.id, date: date, minute: nil) }) { minuteChoice = r.minute ?? 540 }
                        }
                    }
                }
                }
                Section {
                    if status(r) == .pending {
                        Button("이 작업에 집중") {
                            startFocus(TodayEntry(routine: r))
                        }
                    }
                    Button(status(r) == .skipped ? "되돌리기" : "오늘 건너뛰기") {
                        model.perform { try $0.setStatus(routineID: r.id, date: date, status: status(r) == .skipped ? .pending : .skipped) }
                    }
                    Button("루틴 수정") { detailDraft = RoutineDraft(r, steps: model.snapshot.steps) }
                }
            }.navigationTitle("루틴 상세").platformInlineTitle()
                .sheet(item: $detailDraft) { RoutineEditor(model: model, draft: $0) }
                .formStyle(.grouped)
    }
    private func calendarRow(_ e: TodayEntry, minimumHeight: CGFloat = 0) -> some View {
        HStack(spacing: 14) { detailButton(e, showsTime: minimumHeight == 0); completionButton(e) }
            .padding(.vertical, 5)
            .frame(minHeight: minimumHeight)
            .modifier(stackTracking(e.id))
            .modifier(TodayCylinderEffect(enabled: cylinderEffect && scheduleView == "목록" && minimumHeight == 0))
            .contextMenu { entryMenu(e) }
    }
    private func durationText(_ e: TodayEntry) -> String? {
        guard e.event?.allDay != true else { return nil }
        return RoutineRules.durationLabel(e.durationMinutes)
    }
    @ViewBuilder private func durationLabel(_ e: TodayEntry) -> some View {
        if let duration = durationText(e) {
            Text(duration).font(.caption).monospacedDigit().foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
                .accessibilityLabel("소요시간 \(duration)")
        }
    }
    private func detailButton(_ e: TodayEntry, showsTime: Bool = true) -> some View {
        Button { open(e) } label: {
            HStack(spacing: 8) {
                if let event = e.event { CalendarColorIndicator(event: event) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        if !showsTime { durationLabel(e) }
                        Text(title(e)).font(.callout.bold()).lineLimit(2)
                            .strikethrough(e.event != nil && isDone(e))
                    }
                    if showsTime, let event = e.event {
                        Text(event.allDay ? "하루 종일 · \(event.calendarTitle)" : "\(RoutineRules.timeLabel(e.minute))–\(RoutineRules.timeLabel(e.calendarEndMinute)) · \(event.calendarTitle)")
                            .font(.caption2).foregroundStyle(.secondary)
                    } else if showsTime { Text(e.block.map { "\(RoutineRules.timeLabel($0.startMinute))–\(RoutineRules.timeLabel($0.endMinute))" } ?? RoutineRules.timeLabel(e.minute)).font(.caption2).foregroundStyle(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("\(title(e)) 상세 보기")
            .contextMenu { entryMenu(e) }
    }
    @ViewBuilder private func entryMenu(_ e: TodayEntry) -> some View {
        #if os(macOS)
        Button("상세 보기") { open(e) }
        if e.event == nil && e.routine?.calendarLink == nil { Button("시간 변경", systemImage: "clock") { open(e) } }
        Divider()
        if let r = e.routine {
            Button(status(r) == .completed ? "완료 취소" : "완료", systemImage: "checkmark.circle") {
                model.perform { try $0.setStatus(routineID: r.id, date: date, status: status(r) == .completed ? .pending : .completed) }
            }
            Button(status(r) == .skipped ? "건너뛰기 취소" : "이 날짜 건너뛰기", systemImage: "forward.end") {
                model.perform { try $0.setStatus(routineID: r.id, date: date, status: status(r) == .skipped ? .pending : .skipped) }
            }
            Button("루틴 수정", systemImage: "pencil") { draft = RoutineDraft(r, steps: model.snapshot.steps) }
        }
        #endif
        if let event = e.event, e.routine == nil {
            Button(model.appleCalendar.isCompleted(event) ? "완료 취소" : "완료", systemImage: "checkmark.circle") {
                model.appleCalendar.setCompleted(event, completed: !model.appleCalendar.isCompleted(event))
            }
        }
        if e.event == nil && !isDone(e) {
            Button("이 작업에 집중", systemImage: "scope") { startFocus(e) }
        }
        if let b = e.block {
            Divider()
            Button("시간 블록 삭제", role: .destructive) { deleteBlock = b.id }
        }
    }
    @ViewBuilder private func completionButton(_ e: TodayEntry) -> some View {
        if e.routine != nil || e.event != nil {
            let completed = e.routine.map { status($0) == .completed } ?? e.event.map { model.appleCalendar.isCompleted($0) } ?? false
            let skipped = e.routine.map { status($0) == .skipped } ?? false
            Button {
                if let r = e.routine {
                    model.perform { try $0.setStatus(routineID: r.id, date: date, status: completed || skipped ? .pending : .completed) }
                } else if let event = e.event {
                    model.appleCalendar.setCompleted(event, completed: !completed)
                }
            } label: {
                Image(systemName: skipped ? "minus.circle.fill" : completed ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(skipped ? Color.orange : completed ? Color.teal : Color.secondary)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }.buttonStyle(.borderless)
                .accessibilityLabel("\(title(e)) \(skipped ? "건너뛰기 취소" : completed ? "완료 취소" : "완료")")
                .accessibilityValue(skipped ? "건너뜀" : completed ? "완료" : "미완료")
        }
    }
}
