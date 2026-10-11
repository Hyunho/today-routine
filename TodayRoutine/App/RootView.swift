import SwiftUI
import EventKit
#if os(macOS)
import Darwin
#endif
private enum AuxiliaryPanel: String, CaseIterable {
    case feed = "피드"
    case logseq = "Logseq"
    case settings = "설정"
}
struct RootView: View {
    @SceneStorage("auxiliaryPanel.width") private var savedPanelWidth = 380.0
    @State private var maximumPanelWidth: CGFloat = 760
    @State private var panelResizeAnchor: CGFloat?
    @State private var panelOpen = false
    @State private var panelSelection: AuxiliaryPanel = .feed
    @State private var feedPanelLoaded = false
    @State private var logseqWindowID = UUID()
    #if os(macOS)
    // Own the editor without invalidating the entire app on every keystroke.
    @State private var sharedDocumentHost = TodayDocumentHost()
    @State private var sharedDocumentDate = Date()
    #endif
    @State private var pageStacks: [String: [String]] = [:]
    @Bindable var model: AppModel
    @StateObject private var valleyBrowser = ValleyBrowserModel()
    @StateObject private var nomadBrowser = ValleyBrowserModel(
        homeURL: URL(string: "https://nomadcoders.co/ax/dashboard")!, title: "노마드코더 AX"
    )
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let error = model.startupError {
                ContentUnavailableView { Label("기록을 열 수 없습니다", systemImage: "externaldrive.badge.exclamationmark") } description: { Text(error) } actions: { Button("다시 시도") { model.open() } }
            } else if let session = model.focusSession {
                FocusSessionView(model: model, session: session)
                #if os(macOS)
                    .frame(minWidth:360,idealWidth:440,maxWidth:480,minHeight:560,idealHeight:760)
                #endif
            } else {
                #if os(macOS)
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        // TabView scopes toolbar preferences to the selected tab. Opacity-hidden
                        // NavigationStacks still contribute their back buttons to the same NSToolbar
                        // and can crash AppKit when both Feed and All have a pushed destination.
                        // Omit tabItem labels: the existing bottom buttons own tab selection.
                        TabView(selection: model.tabSelection) {
                            TodayView(model: model, openSettingsPanel: showSettingsPanel).environment(\.pageStack, ["오늘"])
                                .onPreferenceChange(PageStackPreferenceKey.self) { pageStacks["오늘"] = $0 }
                                .tag("오늘")
                            Group {
                                if panelOpen && panelSelection == .logseq {
                                    ContentUnavailableView("오른쪽 패널에서 편집 중", systemImage: "sidebar.right", description: Text("Logseq 패널을 닫으면 이 탭에서 이어서 편집할 수 있습니다."))
                                } else {
                                    TodayView(model: model, isLogseqReading: true, openSettingsPanel: showSettingsPanel, sharedDocumentHost: sharedDocumentHost, sharedDocumentDate: $sharedDocumentDate)
                                }
                            }.environment(\.pageStack, ["Logseq"])
                                .onPreferenceChange(PageStackPreferenceKey.self) { pageStacks["Logseq"] = $0 }
                                .tag("Logseq")
                            PlanningView(model: model, mode: 0).environment(\.pageStack, ["일감"])
                                .onPreferenceChange(PageStackPreferenceKey.self) { pageStacks["일감"] = $0 }
                                .tag("일감")
                            InboxView(model: model, isActive: model.selectedTab == "피드", presentsErrors: !(panelOpen && panelSelection == .feed)).environment(\.pageStack, ["feed"])
                                .onPreferenceChange(PageStackPreferenceKey.self) { pageStacks["피드"] = $0 }
                                .tag("피드")
                            CalendarView(calendar: model.appleCalendar, routineModel: model).environment(\.pageStack, ["캘린더"])
                                .onPreferenceChange(PageStackPreferenceKey.self) { pageStacks["캘린더"] = $0 }
                                .tag("캘린더")
                            AllNavigationView(model: model, valleyBrowser: valleyBrowser, nomadBrowser: nomadBrowser, openSettingsPanel: showSettingsPanel).environment(\.pageStack, ["전체"])
                                .onPreferenceChange(PageStackPreferenceKey.self) { pageStacks["전체"] = $0 }
                                .tag("전체")
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        Divider()
                        VStack(spacing: 0) {
                            Text(currentPageStack.joined(separator: " → "))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.top, 5)
                                .help(currentPageStack.joined(separator: " → "))
                                .accessibilityIdentifier("app-page-stack")
                            HStack {
                                Button { changePanel(open: !panelOpen, selection: panelSelection) } label: {
                                    Image(systemName: "sidebar.right")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(panelOpen ? "보조 패널 접기" : "보조 패널 펼치기")
                                .accessibilityIdentifier("settings-panel-toggle")
                                .keyboardShortcut(",", modifiers: .command)
                                .help("보조 패널 (⌘,)")
                                Spacer()
                                AppResourceUsageView()
                            }
                                .padding(.horizontal, 12)
                                .padding(.top, 5)
                            HStack(spacing: 0) {
                                mobileTab("오늘", icon: "sun.max", shortcut: "1")
                                mobileTab("Logseq", icon: "doc.text", shortcut: "2")
                                mobileTab("일감", icon: "tray", shortcut: "3")
                                mobileTab("피드", icon: "tray.full", shortcut: "4")
                                mobileTab("캘린더", icon: "calendar", shortcut: "5")
                                mobileTab("전체", icon: "square.grid.2x2", shortcut: "6")
                            }.padding(.vertical, 8)
                        }.background(.bar)
                    }.frame(minWidth: model.selectedTab == "Logseq" ? 0 : 360, idealWidth: model.selectedTab == "Logseq" ? 1120 : 440, maxWidth: model.selectedTab == "Logseq" ? .infinity : 480, minHeight:560,idealHeight:760)
                    if panelOpen {
                        AuxiliaryPanelResizeHandle(width: panelWidth, maximumWidth: maximumPanelWidth) { width, rightEdge in
                            panelResizeAnchor = rightEdge
                            savedPanelWidth = Double(width)
                        }
                            .frame(width: AuxiliaryPanelSizing.dividerWidth)
                            .frame(maxHeight: .infinity)
                            .help("드래그해 패널 너비 조절 · 두 번 클릭해 기본 너비 복원")
                    }
                    VStack(spacing: 0) {
                        HStack {
                            Picker("보조 화면", selection: Binding(get: { panelSelection }, set: { changePanel(open: true, selection: $0) })) {
                                ForEach(AuxiliaryPanel.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.menu).labelsHidden()
                            .accessibilityIdentifier("right-panel-content")
                            Spacer()
                            Button { changePanel(open: false, selection: panelSelection) } label: { Image(systemName: "xmark") }
                                .buttonStyle(.plain)
                                .accessibilityLabel("보조 패널 닫기")
                                .accessibilityIdentifier("settings-panel-close")
                        }.padding()
                        Divider()
                        ZStack {
                            if feedPanelLoaded {
                                InboxView(model: model, isActive: panelOpen && panelSelection == .feed, embedded: true)
                                    .opacity(panelSelection == .feed ? 1 : 0)
                                    .disabled(panelSelection != .feed)
                                    .accessibilityHidden(panelSelection != .feed)
                            }
                            if panelOpen && panelSelection == .logseq {
                                TodayView(model: model, isLogseqReading: true, openSettingsPanel: showSettingsPanel, sharedDocumentHost: sharedDocumentHost, sharedDocumentDate: $sharedDocumentDate)
                                    .accessibilityIdentifier("right-panel-logseq")
                            }
                            if panelOpen && panelSelection == .settings {
                                SettingsView(model: model, embedded: true)
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: panelWidth)
                    .frame(width: panelOpen ? panelWidth : 0)
                    .clipped()
                    .disabled(!panelOpen)
                    .accessibilityHidden(!panelOpen)
                    .accessibilityIdentifier("right-panel")
                }
                .onChange(of: model.selectedTab) { _, _ in panelResizeAnchor = nil }
                .onChange(of: panelOpen) { _, open in
                    panelResizeAnchor = nil
                    if open && panelSelection == .feed { feedPanelLoaded = true }
                }
                .onChange(of: panelSelection) { _, selection in
                    if selection == .feed { feedPanelLoaded = true }
                }
                #else
                TabView(selection: model.tabSelection) {
                    TodayView(model: model).tabItem { Label("오늘", systemImage: "sun.max") } .tag("오늘")
                    TodayView(model: model, isLogseqReading: true).tabItem { Label("Logseq", systemImage: "doc.text") }.tag("Logseq")
                    PlanningView(model: model, mode:0).tabItem { Label("일감", systemImage: "tray") } .tag("일감")
                    InboxView(model: model).tabItem { Label("피드", systemImage: "tray.full") } .tag("피드")
                    CalendarView(calendar: model.appleCalendar, routineModel: model).tabItem { Label("캘린더", systemImage: "calendar") } .tag("캘린더")
                    AllNavigationView(model: model, valleyBrowser: valleyBrowser, nomadBrowser: nomadBrowser).tabItem { Label("전체", systemImage: "square.grid.2x2") }.tag("전체")
                }
                #endif
            }
        }
        #if os(macOS)
        .background(LogseqWindowBridge(host: model.logseq, windowID: logseqWindowID, isLogseq: model.selectedTab == "Logseq" && model.focusSession == nil, closeCoordinator: model.logseqClose, settingsVisible: panelOpen && model.focusSession == nil, panelWidth: panelWidth, resizeAnchorX: panelResizeAnchor, onPanelWidthLimitChange: { maximumPanelWidth = $0; panelResizeAnchor = nil }).frame(width: 0, height: 0))
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            await model.monitorListLayoutChanges()
        }
        .background(FocusWindowLevel(enabled: model.focusSession != nil).frame(width: 0, height: 0))
        #endif
        .alert("저장하지 못했습니다", isPresented: Binding(get: { model.error != nil && model.presentedSheets == 0 }, set: { if !$0 { model.error = nil } })) { Button("확인") { model.error = nil } } message: { Text(model.error ?? "") }
        .task { await model.appleReminders.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in Task { await model.appleReminders.refresh() } }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.appleReminders.refresh() } } }
        .onChange(of: scenePhase) { _, phase in model.sync?.setActive(phase == .active); if phase == .active { model.refreshNotifications() } }
    }
    #if os(macOS)
    private var panelWidth: CGFloat { AuxiliaryPanelSizing.clamped(CGFloat(savedPanelWidth), maximum: maximumPanelWidth) }
    #endif
    private func showSettingsPanel() {
        changePanel(open: true, selection: .settings)
    }
    private func changePanel(open: Bool, selection: AuxiliaryPanel) {
        Task { @MainActor in
            #if os(macOS)
            // Flush the current editor before moving it or removing its panel.
            if (panelOpen && panelSelection == .logseq) || (open && selection == .logseq) {
                for host in model.todayDocumentHosts.values where host.active {
                    guard await host.apply() else { return }
                }
            }
            #endif
            panelSelection = selection
            panelOpen = open
        }
    }
    private var currentPageStack: [String] {
        let path = pageStacks[model.selectedTab] ?? []
        return path.isEmpty ? [model.selectedTab == "피드" ? "feed" : model.selectedTab] : path
    }

    private func mobileTab(_ name: String, icon: String, shortcut: KeyEquivalent) -> some View {
        Button { Task { await model.selectTab(name) } } label: {
            VStack(spacing: 4) { Image(systemName: icon).font(.title3); Text(name).font(.caption) }
                .foregroundStyle(model.selectedTab == name ? Color.teal : Color.secondary)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(name)
        .keyboardShortcut(shortcut, modifiers: .command)
        .help("\(name) (⌘\(shortcut.character))")
        .accessibilityAddTraits(model.selectedTab == name ? [.isSelected] : [])
    }

}
/// The shared navigation hub keeps secondary screens within the All tab.
private struct AllNavigationView: View {
    let model: AppModel
    @ObservedObject var valleyBrowser: ValleyBrowserModel
    @ObservedObject var nomadBrowser: ValleyBrowserModel
    var openSettingsPanel: (() -> Void)? = nil
    @State private var settings = false

    var body: some View {
        NavigationStack {
            List {
                Section("루틴과 기록") {
                    NavigationLink { RoutinesView(model: model).pageStack(["전체", "루틴"]) } label: {
                        Label("루틴", systemImage: "repeat")
                    }.accessibilityIdentifier("all-routines")
                    NavigationLink { HistoryView(model: model).pageStack(["전체", "주간 기록"]) } label: {
                        Label("주간 기록", systemImage: "chart.bar")
                    }
                }
                Section("바로 가기") {
                    tabLink("오늘", icon: "sun.max")
                    tabLink("Logseq", icon: "doc.text")
                    tabLink("일감", icon: "tray")
                    tabLink("피드", icon: "tray.full")
                    tabLink("캘린더", icon: "calendar")
                    NavigationLink {
                        ValleyBrowserView(browser: valleyBrowser).navigationTitle("Valley")
                    } label: {
                        Label("Valley", systemImage: "globe")
                    }
                    NavigationLink {
                        ValleyBrowserView(browser: nomadBrowser).navigationTitle(nomadBrowser.title)
                    } label: {
                        Label(nomadBrowser.title, systemImage: "graduationcap")
                    }.accessibilityIdentifier("all-nomad-ax")
                }
                Section {
                    Button {
                        if let openSettingsPanel { openSettingsPanel() }
                        else { settings = true }
                    } label: {
                        Label("설정", systemImage: "gearshape")
                    }.buttonStyle(.plain)
                }
            }
            .navigationTitle("전체")
            .sheet(isPresented: $settings) { SettingsView(model: model) }
        }
    }

    private func tabLink(_ title: String, icon: String) -> some View {
        Button { Task { await model.selectTab(title) } } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("all-\(title)")
    }
}

#if os(macOS)
private struct AppResourceUsageView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var sampler = AppResourceSampler()
    @State private var usage: AppResourceUsage?

    var body: some View {
        Text(usage.map { String(format: "CPU %.1f%% · 메모리 %.0f MB", $0.cpuPercent, $0.memoryMB) }
             ?? "CPU — · 메모리 —")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.secondary)
            .accessibilityIdentifier("app-resource-usage")
            .help("TodayRoutineMac 앱의 CPU 사용률과 현재 메모리 사용량")
            .task(id: scenePhase) {
                guard scenePhase == .active else { return }
                while !Task.isCancelled {
                    usage = sampler.sample()
                    try? await Task.sleep(for: .seconds(3))
                }
            }
    }
}

private struct AppResourceUsage {
    let cpuPercent: Double
    let memoryMB: Double
}

private final class AppResourceSampler {
    private var previousCPUTime: TimeInterval?
    private var previousUptime: TimeInterval?

    func sample() -> AppResourceUsage? {
        var cpu = rusage()
        guard getrusage(RUSAGE_SELF, &cpu) == 0 else { return nil }

        var memory = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &memory) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        let cpuTime = Double(cpu.ru_utime.tv_sec + cpu.ru_stime.tv_sec)
            + Double(cpu.ru_utime.tv_usec + cpu.ru_stime.tv_usec) / 1_000_000
        let uptime = ProcessInfo.processInfo.systemUptime
        let percentage: Double
        if let previousCPUTime, let previousUptime, uptime > previousUptime {
            percentage = max(0, (cpuTime - previousCPUTime) / (uptime - previousUptime) * 100)
        } else {
            percentage = 0
        }
        previousCPUTime = cpuTime
        previousUptime = uptime
        return AppResourceUsage(cpuPercent: percentage, memoryMB: Double(memory.resident_size) / 1_048_576)
    }
}
#endif
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
    @ViewBuilder private func sized<V: View>(_ view: V) -> some View {
        if embedded { view } else { view.platformSheetSize() }
    }
    let model: AppModel
    var embedded = false
    func body(content: Content) -> some View {
        sized(content.formStyle(.grouped))
            .onAppear { model.presentedSheets += 1 }
            .onDisappear { model.presentedSheets = max(0, model.presentedSheets - 1) }
            .alert("저장하지 못했습니다", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("확인") { model.error = nil }
            } message: { Text(model.error ?? "") }
    }
}
