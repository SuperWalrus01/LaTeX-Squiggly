import SwiftUI

/// The app that carries the keyboard. iOS only installs a keyboard as part of
/// an app, so this one explains setup, gives a place to try the keyboard, and
/// renders larger pieces of LaTeX than fit above the keys.
@main
struct LaTeXSquigglyApp: App {
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
        TabView {
            SetupView()
                .tabItem { Label("Set up", systemImage: "keyboard") }
            TryView()
                .tabItem { Label("Try it", systemImage: "character.cursor.ibeam") }
            RenderView()
                .tabItem { Label("Render", systemImage: "function") }
        }
        .tint(.squiggle)
    }
}
