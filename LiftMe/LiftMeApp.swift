import SwiftUI

@main
struct LiftMeApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            PopoverView()
                .environment(appState)
        } label: {
            MenuBarLabel()
                .environment(appState)
        }
        .menuBarExtraStyle(.window)

        Window("LiftMe Settings", id: "settings") {
            SettingsView()
                .environment(appState)
        }
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}
