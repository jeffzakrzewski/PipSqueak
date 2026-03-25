import SwiftUI

struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack(spacing: 0) {
            Image(systemName: appState.menuBarIcon)
            if !appState.menuBarTitle.isEmpty {
                Text(" \(appState.menuBarTitle)")
                    .monospacedDigit()
            }
        }
    }
}
