#if os(macOS)
import AppKit
import SwiftUI

/// Changes only the window hosting this view, preserving its original level.
struct FocusWindowLevel: NSViewRepresentable {
    var enabled: Bool

    func makeNSView(context: Context) -> FocusWindowLevelView {
        FocusWindowLevelView()
    }

    func updateNSView(_ view: FocusWindowLevelView, context: Context) {
        view.enabled = enabled
    }

    static func dismantleNSView(_ view: FocusWindowLevelView, coordinator: ()) {
        view.restore()
    }
}

final class FocusWindowLevelView: NSView {
    var enabled = false { didSet { updateLevel() } }
    private weak var managedWindow: NSWindow?
    private var originalLevel: NSWindow.Level?

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if window !== newWindow { restore() }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateLevel()
    }

    private func updateLevel() {
        guard enabled, let window else { restore(); return }
        if managedWindow !== window {
            restore()
            managedWindow = window
            originalLevel = window.level
            window.level = .floating
        }
    }

    func restore() {
        if let managedWindow, let originalLevel { managedWindow.level = originalLevel }
        managedWindow = nil
        originalLevel = nil
    }
}
#endif
