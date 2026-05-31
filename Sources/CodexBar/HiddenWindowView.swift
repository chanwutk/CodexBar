import AppKit
import SwiftUI

struct HiddenWindowView: View {
    var body: some View {
        Color.clear
            .frame(width: 20, height: 20)
            .onReceive(NotificationCenter.default.publisher(for: .codexbarOpenSettings)) { _ in
                Task { @MainActor in
                    Self.openSettingsWindow()
                }
            }
            .task {
                // Migrate keychain items to reduce permission prompts during development (runs off main thread)
                await Task.detached(priority: .userInitiated) {
                    KeychainMigration.migrateIfNeeded()
                }.value
            }
            .onAppear {
                if let window = NSApp.windows.first(where: { $0.title == "CodexBarLifecycleKeepalive" }) {
                    // Make the keepalive window truly invisible and non-interactive.
                    window.styleMask = [.borderless]
                    window.collectionBehavior = [.auxiliary, .ignoresCycle, .transient, .canJoinAllSpaces]
                    window.isExcludedFromWindowsMenu = true
                    window.level = .floating
                    window.isOpaque = false
                    window.alphaValue = 0
                    window.backgroundColor = .clear
                    window.hasShadow = false
                    window.ignoresMouseEvents = true
                    window.canHide = false
                    window.setContentSize(NSSize(width: 1, height: 1))
                    window.setFrameOrigin(NSPoint(x: -5000, y: -5000))
                }
            }
    }

    /// Opens the Settings window via AppKit. SwiftUI's `openSettings` environment action is
    /// macOS 14+ only and usable solely inside a View, so we use the responder-chain selector,
    /// which works on macOS 13 (`showSettingsWindow:`) and falls back for older naming.
    @MainActor
    private static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
}
