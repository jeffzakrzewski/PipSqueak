import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CalendarSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }

            AudioSettingsView()
                .tabItem { Label("Audio & Timer", systemImage: "speaker.wave.2") }

            ProfileMappingSettingsView()
                .tabItem { Label("Browser", systemImage: "globe") }

            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 520, height: 460)
    }
}
