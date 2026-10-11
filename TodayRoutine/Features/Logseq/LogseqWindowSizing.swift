#if os(macOS)
import AppKit
import SwiftUI

enum AuxiliaryPanelSizing {
    static let defaultWidth: CGFloat = 380
    static let minimumWidth: CGFloat = 320
    static let maximumWidth: CGFloat = 760
    static let dividerWidth: CGFloat = 8

    static func clamped(_ width: CGFloat, maximum: CGFloat = maximumWidth) -> CGFloat {
        guard width.isFinite else { return min(defaultWidth, maximum) }
        return min(maximum, max(minimumWidth, width))
    }
}

struct AuxiliaryPanelResizeHandle: NSViewRepresentable {
    var width: CGFloat
    var maximumWidth: CGFloat
    var onChange: (CGFloat, CGFloat?) -> Void
    func makeNSView(context: Context) -> AuxiliaryPanelResizeView { AuxiliaryPanelResizeView() }
    func updateNSView(_ view: AuxiliaryPanelResizeView, context: Context) {
        view.panelWidth = width
        view.maximumWidth = maximumWidth
        view.onChange = onChange
        view.setAccessibilityValue("\(Int(width)) pt")
    }
}

final class AuxiliaryPanelResizeView: NSView {
    var panelWidth: CGFloat = AuxiliaryPanelSizing.defaultWidth
    var maximumWidth: CGFloat = AuxiliaryPanelSizing.maximumWidth
    var onChange: ((CGFloat, CGFloat?) -> Void)?
    private var dragStart: (x: CGFloat, width: CGFloat, rightEdge: CGFloat?)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true)
        setAccessibilityRole(.splitter)
        setAccessibilityLabel("보조 패널 너비")
        setAccessibilityIdentifier("panel-resize-handle")
        setAccessibilityHelp("왼쪽으로 끌면 넓어지고, 오른쪽으로 끌면 좁아집니다. 두 번 클릭하면 기본 너비로 돌아갑니다.")
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .resizeLeftRight) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height).fill()
        NSColor.secondaryLabelColor.withAlphaComponent(0.5).setFill()
        NSBezierPath(roundedRect: NSRect(x: bounds.midX - 1.5, y: bounds.midY - 16, width: 3, height: 32), xRadius: 1.5, yRadius: 1.5).fill()
    }
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            dragStart = nil
            changeWidth(AuxiliaryPanelSizing.defaultWidth)
        } else {
            // Screen coordinates stay stable while the window expands to the left.
            dragStart = (NSEvent.mouseLocation.x, panelWidth, window?.frame.maxX)
        }
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start = dragStart else { return }
        changeWidth(start.width + start.x - NSEvent.mouseLocation.x)
    }
    override func mouseUp(with event: NSEvent) { dragStart = nil }
    override func accessibilityPerformIncrement() -> Bool { changeWidth(panelWidth + 20); return true }
    override func accessibilityPerformDecrement() -> Bool { changeWidth(panelWidth - 20); return true }
    private func changeWidth(_ value: CGFloat) { onChange?(AuxiliaryPanelSizing.clamped(value, maximum: maximumWidth), dragStart?.rightEdge ?? window?.frame.maxX) }
}

struct LogseqWindowBridge: NSViewRepresentable {
    @ObservedObject var host: LogseqHost
    let windowID: UUID
    let isLogseq: Bool
    let closeCoordinator: LogseqCloseCoordinator
    var settingsVisible = false
    var panelWidth: CGFloat = AuxiliaryPanelSizing.defaultWidth
    var resizeAnchorX: CGFloat?
    var onPanelWidthLimitChange: ((CGFloat) -> Void)?
    func makeNSView(context: Context) -> LogseqWindowView {
        let view = LogseqWindowView()
        view.configure(host: host, id: windowID, active: isLogseq, close: closeCoordinator, settingsVisible: settingsVisible, panelWidth: panelWidth, resizeAnchorX: resizeAnchorX, onPanelWidthLimitChange: onPanelWidthLimitChange)
        return view
    }
    func updateNSView(_ view: LogseqWindowView, context: Context) {
        view.configure(host: host, id: windowID, active: isLogseq, close: closeCoordinator, settingsVisible: settingsVisible, panelWidth: panelWidth, resizeAnchorX: resizeAnchorX, onPanelWidthLimitChange: onPanelWidthLimitChange)
    }
}

@MainActor final class LogseqWindowView: NSView, NSWindowDelegate {
    private weak var host: LogseqHost?
    private var id = UUID()
    private var active = false
    private var closeCoordinator: LogseqCloseCoordinator?
    private weak var previousDelegate: (any NSWindowDelegate)?
    private weak var managedWindow: NSWindow?
    private var lastActive: Bool?
    private var settingsVisible = false
    private var lastSettingsVisible = false
    private var panelWidth = AuxiliaryPanelSizing.defaultWidth
    private var resizeAnchorX: CGFloat?
    private var lastPanelExtent: CGFloat = 0
    private var lastPanelLimit: CGFloat?
    private var lastAvailableFrame: NSRect?
    private var onPanelWidthLimitChange: ((CGFloat) -> Void)?
    private var compactSize: NSSize?
    private var editorSize: NSSize?
    private var closing = false
    private var transferring = false

    func configure(host: LogseqHost, id: UUID, active: Bool, close: LogseqCloseCoordinator, settingsVisible: Bool = false, panelWidth: CGFloat = AuxiliaryPanelSizing.defaultWidth, resizeAnchorX: CGFloat? = nil, onPanelWidthLimitChange: ((CGFloat) -> Void)? = nil) {
        self.panelWidth = panelWidth
        self.resizeAnchorX = resizeAnchorX
        self.onPanelWidthLimitChange = onPanelWidthLimitChange
        self.settingsVisible = settingsVisible
        self.host = host; self.id = id; self.active = active; closeCoordinator = close
        // SwiftUI may still be laying out the new selected tab.
        DispatchQueue.main.async { [weak self] in self?.updateWindow() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let old = managedWindow, old !== window, old.delegate === self { old.delegate = previousDelegate }
        guard let window else { return }
        if managedWindow !== window {
            managedWindow = window
            previousDelegate = window.delegate
            window.delegate = self
        }
        DispatchQueue.main.async { [weak self] in self?.updateWindow() }
    }
    override func responds(to selector: Selector!) -> Bool {
        super.responds(to: selector) || (previousDelegate?.responds(to: selector) ?? false)
    }
    override func forwardingTarget(for selector: Selector!) -> Any? {
        if previousDelegate?.responds(to: selector) == true { return previousDelegate }
        return super.forwardingTarget(for: selector)
    }
    private func updateWindow() {
        guard let window, let host else { return }
        let available = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? window.frame
        let mainMinimum: CGFloat = active ? min(760, max(360, available.width - AuxiliaryPanelSizing.minimumWidth - AuxiliaryPanelSizing.dividerWidth)) : 360
        let panelLimit = min(AuxiliaryPanelSizing.maximumWidth, max(0, available.width - mainMinimum - AuxiliaryPanelSizing.dividerWidth))
        if lastPanelLimit != panelLimit {
            lastPanelLimit = panelLimit
            onPanelWidthLimitChange?(panelLimit)
        }
        let panelExtent = settingsVisible ? AuxiliaryPanelSizing.clamped(panelWidth, maximum: panelLimit) + AuxiliaryPanelSizing.dividerWidth : 0
        if lastActive != active || lastSettingsVisible != settingsVisible || lastPanelExtent != panelExtent || lastAvailableFrame != available {
            let resizingPanel = lastActive == active && lastSettingsVisible && settingsVisible && lastPanelExtent != panelExtent
            var current = window.contentRect(forFrameRect: window.frame).size
            let titleHeight = window.frame.height - current.height
            // Stored sizes describe the content area without the settings panel.
            current.width -= lastPanelExtent
            // SwiftUI can already have constrained the window for the new panel.
            // Do not record that transitional width as the previous content size.
            if lastSettingsVisible == settingsVisible && lastPanelExtent == panelExtent && (lastAvailableFrame == nil || lastAvailableFrame == available) {
                if lastActive == true { editorSize = current }
                else if lastActive == false || compactSize == nil { compactSize = current }
            }
            var size = active ? (editorSize ?? NSSize(width: 1120, height: max(760, current.height))) : (compactSize ?? NSSize(width: 440, height: 760))
            let minWidth = min(available.width, (settingsVisible ? mainMinimum : (active ? min(760, available.width) : 360)) + panelExtent)
            size.width = min(available.width, max(minWidth, (active ? size.width : min(480, size.width)) + panelExtent))
            size.height = min(available.height - titleHeight, max(560, size.height))
            window.contentMinSize = NSSize(width: minWidth, height: min(560, available.height - titleHeight))
            window.contentMaxSize = NSSize(width: active ? CGFloat.greatestFiniteMagnitude : 480 + panelExtent, height: CGFloat.greatestFiniteMagnitude)
            let top = window.frame.maxY
            // SwiftUI may have grown the frame before this deferred update.
            // Keep the edge captured by the handle before layout began.
            let right = (resizingPanel && lastAvailableFrame == available ? resizeAnchorX : nil) ?? window.frame.maxX
            window.setContentSize(size)
            var frame = window.frame
            frame.origin.y = min(available.maxY, top) - frame.height
            if resizingPanel { frame.origin.x = right - frame.width }
            frame.origin.x = max(available.minX, min(frame.origin.x, available.maxX - frame.width))
            frame.origin.y = max(available.minY, frame.origin.y)
            window.setFrame(frame, display: true)
            lastActive = active
            lastSettingsVisible = settingsVisible
            lastPanelExtent = panelExtent
            lastAvailableFrame = available
        }
        if window.isKeyWindow {
            if active, host.ownerID != id, !transferring {
                transferring = true
                Task { [weak self, weak window] in
                    guard let self, let window else { return }
                    await host.claimWindow(window, id: self.id)
                    self.transferring = false
                    let enabled = self.active && window.isKeyWindow && host.ownerID == self.id
                    if host.commandsActive != enabled { host.commandsActive = enabled }
                }
            } else {
                let enabled = active && host.ownerID == id
                if host.commandsActive != enabled { host.commandsActive = enabled }
            }
        }
    }
    func windowDidEndLiveResize(_ notification: Notification) {
        previousDelegate?.windowDidEndLiveResize?(notification)
        guard let window, lastActive == active, lastSettingsVisible == settingsVisible else { return }
        var size = window.contentRect(forFrameRect: window.frame).size
        size.width -= lastPanelExtent
        if active { editorSize = size } else { compactSize = size }
    }
    func windowDidChangeScreen(_ notification: Notification) {
        previousDelegate?.windowDidChangeScreen?(notification)
        DispatchQueue.main.async { [weak self] in self?.updateWindow() }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        previousDelegate?.windowDidBecomeKey?(notification)
        updateWindow()
    }
    func windowDidResignKey(_ notification: Notification) {
        previousDelegate?.windowDidResignKey?(notification)
        if host?.ownerID == id { host?.commandsActive = false }
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !closing, let closeCoordinator else { return false }
        closing = true
        Task { [weak self, weak sender] in
            guard let self, let sender else { return }
            defer { self.closing = false }
            guard await closeCoordinator.prepareToClose(), self.previousDelegate?.windowShouldClose?(sender) != false else { return }
            sender.close()
        }
        return false
    }
    func windowWillClose(_ notification: Notification) {
        host?.releaseWindow(id: id)
        previousDelegate?.windowWillClose?(notification)
    }
}
#endif
