import SwiftUI

@main
struct AHUTongApp: App {
    @NSApplicationDelegateAdaptor(ApplicationDelegate.self) private var applicationDelegate
    @StateObject private var store = AppStore()

    var body: some Scene {
        WindowGroup("安大通") {
            RootView()
                .environmentObject(store)
                .frame(minWidth: 980, minHeight: 650)
        }
        .defaultSize(width: 1180, height: 760)
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("刷新数据") { store.refresh() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(store)
                .frame(width: 480, height: 330)
        }
    }
}
