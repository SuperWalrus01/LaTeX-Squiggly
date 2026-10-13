import SwiftUI

/// The app that carries the keyboard. iOS only installs a keyboard as part of
/// an app, so this one teaches it in short lessons, renders larger pieces of
/// LaTeX than fit above the keys, and holds the keyboard's settings.
@main
struct LaTeXSquigglyApp: App {
    @StateObject private var progress = GuideProgress()
    /// PREVIEW_TAB=1 or 2 opens Render or Settings, in debug builds.
    @State private var tab = Int(ProcessInfo.processInfo.environment["PREVIEW_TAB"] ?? "") ?? 0

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            if let screen = DebugScreen.requested {
                DebugScreenView(screen: screen)
            } else {
                tabs
            }
            #else
            tabs
            #endif
        }
    }

    init() {
        SquigglyAppearance.apply()
    }

    private var tabs: some View {
        TabView(selection: $tab) {
            GuideView()
                .tabItem { Label("Guide", systemImage: "graduationcap") }
                .tag(0)
            RenderView()
                .tabItem { Label("Render", systemImage: "function") }
                .tag(1)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(2)
        }
        .environmentObject(progress)
        .tint(.squiggle)
    }
}
