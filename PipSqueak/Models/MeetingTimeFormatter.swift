import Foundation

/// Shared time-formatting helper for countdown displays.
enum MeetingTimeFormatter {
    enum Style {
        /// Compact form used in the menu bar: "5m", "30s", "1h 15m".
        case compact
        /// Colon form used in the popover card: "0:30", "5:00", "1h 5m".
        case colon
    }

    static func format(_ totalSeconds: Int, style: Style) -> String {
        switch style {
        case .compact:
            return formatCompact(totalSeconds)
        case .colon:
            return formatColon(totalSeconds)
        }
    }

    private static func formatCompact(_ totalSeconds: Int) -> String {
        if totalSeconds <= 0 { return "0s" }

        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            if minutes == 0 {
                return "\(hours)h"
            }
            return "\(hours)h \(minutes)m"
        }

        if minutes > 0 {
            return "\(minutes)m"
        }

        return "\(seconds)s"
    }

    private static func formatColon(_ totalSeconds: Int) -> String {
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%dh %dm", hours, minutes)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}
