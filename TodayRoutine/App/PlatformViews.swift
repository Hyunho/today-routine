import SwiftUI
extension View {
    @ViewBuilder func platformInlineTitle() -> some View {
        #if os(iOS)
        self.navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
    @ViewBuilder func platformSheetSize() -> some View {
        #if os(macOS)
        self.frame(minWidth:540,idealWidth:620,minHeight:520,idealHeight:680)
        #else
        self
        #endif
    }
}
struct PlatformEditButton: View {
    var body: some View {
        #if os(iOS)
        EditButton()
        #else
        EmptyView()
        #endif
    }
}
