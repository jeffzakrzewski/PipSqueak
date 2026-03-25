import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CalendarSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }

            AudioSettingsView()
                .tabItem { Label("Audio & Timer", systemImage: "speaker.wave.2") }

            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 500, height: 460)
    }
}
