import SwiftUI
import EventKit
#if os(macOS)
import AppKit
#endif

struct MonthCalendarContent: View {
    @Bindable var calendar: AppleCalendarModel
    let openConnections: () -> Void
    let openEvent: (AppleCalendarEvent) -> Void
    @State private var monthEvents: [AppleCalendarEvent] = []
    @State private var monthGeneration = 0
    @Environment(\.scenePhase) private var phase
    @Environment(\.openURL) private var openURL
    @State private var calendarOpenFailed = false
    private let systemCalendar = Calendar.current
    private var month: Date { systemCalendar.dateInterval(of: .month, for: calendar.date)!.start }
    private var queryKey: String { "\(month.timeIntervalSince1970)-\(calendar.selectedIDs.sorted())-\(calendar.hasAccess)" }
    private var days: [Date?] {
        let count = systemCalendar.range(of: .day, in: .month, for: month)!.count
        let leading = systemCalendar.component(.weekday, from: month) - 1
        var result: [Date?] = Array(repeating: nil, count: leading)
        result += (0..<count).map { systemCalendar.date(byAdding: .day, value: $0, to: month) }
        result += Array(repeating: nil, count: (7 - result.count % 7) % 7)
        return result
    }

    var body: some View {
        GeometryReader { geometry in
            let rowHeight = max(44, min(50, geometry.size.height * 0.42 / Double(days.count / 7)))
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(calendar.date, format: .dateTime.year()).font(.subheadline).foregroundStyle(.secondary)
                        Text(calendar.date, format: .dateTime.month(.wide)).font(.largeTitle.bold())
                    }
                    Spacer()
                    Button("Apple 캘린더 열기", systemImage: "arrow.up.right.square") {
                        openAppleCalendar()
                    }
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("openAppleCalendar")
                    Button("이전 달", systemImage: "chevron.left") { moveMonth(-1) }
                    Button("다음 달", systemImage: "chevron.right") { moveMonth(1) }
                }
                .labelStyle(.iconOnly).buttonStyle(.plain)
                .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 10)

                HStack(spacing: 0) {
                    ForEach(Array(["일", "월", "화", "수", "목", "금", "토"].enumerated()), id: \.offset) { index, name in
                        Text(name).font(.caption.weight(.semibold))
                            .foregroundStyle(index == 0 || index == 6 ? .secondary : .primary)
                            .frame(maxWidth: .infinity)
                    }
                }.padding(.bottom, 8)
                ForEach(0..<(days.count / 7), id: \.self) { week in
                    Divider()
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { column in
                            if let date = days[week * 7 + column] { dayCell(date, weekend: column == 0 || column == 6, height: rowHeight) }
                            else { Color.clear.frame(maxWidth: .infinity).frame(height: rowHeight).accessibilityHidden(true) }
                        }
                    }
                }
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        dayAgenda
                    }.frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16).padding(.top, 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .refreshable { await calendar.refresh(); await loadMonth() }
            }
        }
        .background(calendarBackground)
        .toolbar {
            #if os(macOS)
            ToolbarItem(placement: .navigation) {
                Button("오늘") { calendar.date = Date() }
                    .accessibilityIdentifier("calendarToday")
            }
            #else
            ToolbarItem(placement: .topBarLeading) {
                Button("오늘") { calendar.date = Date() }
                    .accessibilityIdentifier("calendarToday")
            }
            #endif
        }
        .alert("Apple 캘린더를 열 수 없습니다", isPresented: $calendarOpenFailed) {
            Button("확인", role: .cancel) { }
        } message: {
            Text("Apple 캘린더 앱이 설치되어 있는지 확인해 주세요.")
        }
        .task(id: queryKey) { await loadMonth() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await loadMonth() } }
        .onChange(of: phase) { _, value in if value == .active { Task { await loadMonth() } } }
    }

    private func dayCell(_ day: Date, weekend: Bool, height: CGFloat) -> some View {
        let selected = systemCalendar.isDate(day, inSameDayAs: calendar.date)
        let today = systemCalendar.isDateInToday(day)
        let next = systemCalendar.date(byAdding: .day, value: 1, to: day)!
        let events = monthEvents.filter { $0.start < next && ($0.end > day || ($0.start == $0.end && $0.start >= day)) }
        return Button { calendar.date = day } label: {
            VStack(spacing: 3) {
                Text("\(systemCalendar.component(.day, from: day))")
                    .font(.system(size: 20, weight: selected || today ? .semibold : .regular))
                    .foregroundStyle(today ? Color.white : weekend ? Color.secondary : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(today ? Color.red : selected ? Color.primary.opacity(0.1) : Color.clear, in: Circle())
                    .overlay { if selected && today { Circle().strokeBorder(.red.opacity(0.35), lineWidth: 2).padding(-3) } }
                HStack(spacing: 0) {
                    ForEach(Array(events.prefix(6).enumerated()), id: \.offset) { _, event in
                        event.calendarColor.frame(width: 6, height: 5)
                    }
                }.clipShape(Capsule()).frame(height: 5)
            }.frame(maxWidth: .infinity).frame(height: height).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(day.formatted(date: .complete, time: .omitted))
        .accessibilityValue("일정 \(events.count)개\(today ? ", 오늘" : "")")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var dayAgenda: some View {
        if !calendar.hasAccess {
            ContentUnavailableView("캘린더를 연결해 주세요", systemImage: "calendar", description: Text("Apple 캘린더의 일정을 볼 수 있습니다."))
            Button("캘린더 연결", action: openConnections).padding(.bottom)
        } else if calendar.selectedIDs.isEmpty {
            Button("표시할 캘린더 선택", action: openConnections).padding(.vertical, 24)
        } else if calendar.loading { ProgressView("일정을 불러오는 중").padding(.vertical, 24) }
        else if calendar.events.isEmpty {
            Text("선택한 날짜에 일정이 없습니다.").foregroundStyle(.secondary).padding(.vertical, 28)
        } else {
            ForEach(calendar.events) { event in
                HStack(spacing: 12) {
                    CompletionCheckButton(title: event.title, status: calendar.isCompleted(event) ? .completed : .pending) {
                        calendar.setCompleted(event, completed: !calendar.isCompleted(event))
                    }
                Button { openEvent(event) } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 2).fill(event.calendarColor).frame(width: 4, height: 38)
                        Text(event.title).font(.headline).lineLimit(2).foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .trailing, spacing: 3) {
                            if event.allDay { Text("하루 종일") }
                            else {
                                Text(event.start, format: .dateTime.hour().minute())
                                if event.end != event.start { Text(event.end, format: .dateTime.hour().minute()).foregroundStyle(.tertiary) }
                            }
                        }.font(.subheadline).monospacedDigit().foregroundStyle(.secondary)
                    }.padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain)
                }
                Divider()
            }
        }
    }
    private var calendarBackground: Color {
        #if os(macOS)
        Color(nsColor: .windowBackgroundColor)
        #else
        Color(uiColor: .systemBackground)
        #endif
    }
    private func openAppleCalendar() {
        #if os(macOS)
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") else {
            calendarOpenFailed = true
            return
        }
        calendarOpenFailed = !NSWorkspace.shared.open(url)
        #else
        openURL(URL(string: "calshow://")!) { accepted in calendarOpenFailed = !accepted }
        #endif
    }
    private func moveMonth(_ offset: Int) {
        if let next = systemCalendar.date(byAdding: .month, value: offset, to: calendar.date) { calendar.date = next }
    }
    private func loadMonth() async {
        monthGeneration += 1
        let token = monthGeneration
        let requestedMonth = month
        let ids = calendar.selectedIDs
        let events = await calendar.events(inMonth: requestedMonth)
        guard !Task.isCancelled, token == monthGeneration, requestedMonth == month, ids == calendar.selectedIDs else { return }
        monthEvents = events
    }
}
