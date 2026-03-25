import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            CalendarSettingsView()
                .tabItem { Label("Calendars", systemImage: "calendar") }

            TimerSettingsView()
                .tabItem { Label("Timer", systemImage: "timer") }

            AudioSettingsView()
                .tabItem { Label("Audio", systemImage: "speaker.wave.2") }

            GeneralSettingsView()
                .tabItem { Label("General", systemImage: "gear") }
        }
        .frame(width: 450, height: 320)
    }
}
