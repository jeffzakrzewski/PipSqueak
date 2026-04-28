import AppKit
import Foundation

enum BrowserType: String, CaseIterable, Identifiable {
    case chrome = "Google Chrome"
    case brave = "Brave Browser"
    case firefox = "Firefox"
    case safari = "Safari"
    case arc = "Arc"
    case unknown = "Unknown"

    var id: String { rawValue }

    var bundleID: String {
        switch self {
        case .chrome: return "com.google.chrome"
        case .brave: return "com.brave.browser"
        case .firefox: return "org.mozilla.firefox"
        case .safari: return "com.apple.safari"
        case .arc: return "company.thebrowser.browser"
        case .unknown: return ""
        }
    }

    var supportsProfiles: Bool {
        switch self {
        case .chrome, .brave, .firefox: return true
        case .safari, .arc, .unknown: return false
        }
    }

    var appSupportSubpath: String? {
        switch self {
        case .chrome: return "Google/Chrome"
        case .brave: return "BraveSoftware/Brave-Browser"
        case .firefox: return "Firefox"
        default: return nil
        }
    }
}

struct BrowserProfile: Identifiable, Hashable {
    let id: String
    let displayName: String
    let email: String?
    let browserType: BrowserType
}

@MainActor
@Observable
final class BrowserProfileManager {
    var defaultBrowser: BrowserType = .unknown
    var profiles: [BrowserProfile] = []

    var profileMappings: [String: String] {
        didSet {
            let data = (try? JSONEncoder().encode(profileMappings)) ?? Data()
            UserDefaults.standard.set(data, forKey: "browserProfileMappings")
        }
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: "browserProfileMappings"),
           let mappings = try? JSONDecoder().decode([String: String].self, from: data) {
            self.profileMappings = mappings
        } else {
            self.profileMappings = [:]
        }
    }

    func detectBrowser() {
        defaultBrowser = detectDefaultBrowser()
        profiles = enumerateProfiles(for: defaultBrowser)
    }

    /// Launch a URL in a specific browser profile, or fall back to default
    func launchInProfile(url: URL, calendarAccountEmail: String?) {
        guard let email = calendarAccountEmail,
              let profileID = profileMappings[email],
              defaultBrowser.supportsProfiles else {
            print("[LiftMe] No profile mapping for '\(calendarAccountEmail ?? "nil")' — mappings: \(profileMappings), browser: \(defaultBrowser.rawValue), supportsProfiles: \(defaultBrowser.supportsProfiles)")
            NSWorkspace.shared.open(url)
            return
        }

        print("[LiftMe] Launching in profile '\(profileID)' for account '\(email)' in \(defaultBrowser.rawValue)")

        switch defaultBrowser {
        case .chrome, .brave:
            launchChromium(url: url, browserName: defaultBrowser.rawValue, profileDirectory: profileID)
        case .firefox:
            launchFirefox(url: url, profileName: profileID)
        default:
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Browser Detection

    private func detectDefaultBrowser() -> BrowserType {
        guard let schemeURL = URL(string: "https:"),
              let browserURL = NSWorkspace.shared.urlForApplication(toOpen: schemeURL),
              let bundle = Bundle(url: browserURL),
              let bundleID = bundle.bundleIdentifier?.lowercased() else {
            return .unknown
        }

        switch bundleID {
        case "com.google.chrome": return .chrome
        case "com.brave.browser": return .brave
        case "org.mozilla.firefox": return .firefox
        case "com.apple.safari": return .safari
        case "company.thebrowser.browser": return .arc
        default: return .unknown
        }
    }

    // MARK: - Profile Enumeration (direct file access, no sandbox)

    private func enumerateProfiles(for browser: BrowserType) -> [BrowserProfile] {
        guard let subpath = browser.appSupportSubpath else { return [] }

        let home = FileManager.default.homeDirectoryForCurrentUser
        let baseURL = home
            .appendingPathComponent("Library/Application Support")
            .appendingPathComponent(subpath)

        switch browser {
        case .chrome, .brave:
            return readChromiumProfiles(baseURL: baseURL, browserType: browser)
        case .firefox:
            return readFirefoxProfiles(baseURL: baseURL)
        default:
            return []
        }
    }

    private func readChromiumProfiles(baseURL: URL, browserType: BrowserType) -> [BrowserProfile] {
        let localStatePath = baseURL.appendingPathComponent("Local State")

        guard let data = try? Data(contentsOf: localStatePath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let profile = json["profile"] as? [String: Any],
              let infoCache = profile["info_cache"] as? [String: [String: Any]] else {
            return []
        }

        return infoCache.compactMap { dirName, info in
            let displayName = info["name"] as? String ?? dirName
            let userName = info["user_name"] as? String ?? ""
            let email = userName.isEmpty ? nil : userName

            return BrowserProfile(
                id: dirName,
                displayName: displayName,
                email: email,
                browserType: browserType
            )
        }
        .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    private func readFirefoxProfiles(baseURL: URL) -> [BrowserProfile] {
        let iniPath = baseURL.appendingPathComponent("profiles.ini")

        guard let content = try? String(contentsOf: iniPath, encoding: .utf8) else {
            return []
        }

        var profiles: [BrowserProfile] = []
        var currentName: String?

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[Profile") {
                if let name = currentName {
                    profiles.append(BrowserProfile(
                        id: name,
                        displayName: name,
                        email: nil,
                        browserType: .firefox
                    ))
                }
                currentName = nil
            } else if trimmed.hasPrefix("Name=") {
                currentName = String(trimmed.dropFirst(5))
            }
        }
        if let name = currentName {
            profiles.append(BrowserProfile(
                id: name,
                displayName: name,
                email: nil,
                browserType: .firefox
            ))
        }

        return profiles
    }

    // MARK: - Profile-Aware Launch

    private func launchChromium(url: URL, browserName: String, profileDirectory: String) {
        // Use direct binary execution for reliable profile targeting
        let binaryPath = "/Applications/\(browserName).app/Contents/MacOS/\(browserName)"
        let args = ["--profile-directory=\(profileDirectory)", url.absoluteString]

        print("[LiftMe] Exec: \(binaryPath) \(args.joined(separator: " "))")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            print("[LiftMe] Direct binary failed: \(error), trying open -na")
            // Fallback to open -na
            let fallback = Process()
            fallback.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            fallback.arguments = ["-na", browserName, "--args", "--profile-directory=\(profileDirectory)", url.absoluteString]
            do {
                try fallback.run()
            } catch {
                print("[LiftMe] open -na also failed: \(error)")
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func launchFirefox(url: URL, profileName: String) {
        let firefoxPath = "/Applications/Firefox.app/Contents/MacOS/firefox"
        guard FileManager.default.fileExists(atPath: firefoxPath) else {
            NSWorkspace.shared.open(url)
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: firefoxPath)
        process.arguments = [
            "-P", profileName,
            "-no-remote",
            url.absoluteString,
        ]
        do {
            try process.run()
        } catch {
            NSWorkspace.shared.open(url)
        }
    }
}
