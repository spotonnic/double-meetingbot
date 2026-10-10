import Foundation

/// App settings. Seeded from Config.plist in the bundle, overridable in the app (stored in UserDefaults).
struct Settings {
    var supabaseURL: String
    var supabaseKey: String
    var room: String
    var robotEmail: String
    var robotPassword: String
    var meetURL: String
    var guestName: String
    var controllerURL: String
    /// "robot" shows the remote person full-screen, "meet" shows Meet's own layout.
    var view: String
    /// "cover" fills the screen, "contain" shows the whole picture (better for screen sharing).
    var videoFit: String

    private static let defaults = UserDefaults.standard
    private static let prefix = "settings."

    static func load() -> Settings {
        let bundled = bundledConfig()
        func value(_ key: String, _ fallback: String) -> String {
            defaults.string(forKey: prefix + key) ?? bundled[key] as? String ?? fallback
        }
        return Settings(
            supabaseURL: value("SupabaseURL", ""),
            supabaseKey: value("SupabaseKey", ""),
            room: value("Room", "double-office"),
            robotEmail: value("RobotEmail", ""),
            robotPassword: value("RobotPassword", ""),
            meetURL: value("MeetURL", "https://meet.google.com/"),
            guestName: value("GuestName", "Double"),
            controllerURL: value("ControllerURL", "double-meetingbot-glanser.vercel.app"),
            view: value("View", "robot"),
            videoFit: value("VideoFit", "cover")
        )
    }

    func save() {
        let d = Settings.defaults
        d.set(supabaseURL, forKey: Settings.prefix + "SupabaseURL")
        d.set(supabaseKey, forKey: Settings.prefix + "SupabaseKey")
        d.set(room, forKey: Settings.prefix + "Room")
        d.set(robotEmail, forKey: Settings.prefix + "RobotEmail")
        d.set(robotPassword, forKey: Settings.prefix + "RobotPassword")
        d.set(meetURL, forKey: Settings.prefix + "MeetURL")
        d.set(guestName, forKey: Settings.prefix + "GuestName")
        d.set(controllerURL, forKey: Settings.prefix + "ControllerURL")
        d.set(view, forKey: Settings.prefix + "View")
        d.set(videoFit, forKey: Settings.prefix + "VideoFit")
    }

    var isRealtimeConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseKey.isEmpty && !room.isEmpty
            && !robotEmail.isEmpty && !robotPassword.isEmpty
            && !supabaseURL.contains("YOUR-PROJECT")
    }

    /// True when meetURL points at a specific meeting rather than the Meet start page.
    var isInMeeting: Bool {
        guard let url = URL(string: meetURL), url.host == "meet.google.com" else { return false }
        return url.path.count > 1
    }

    private static func bundledConfig() -> [String: Any] {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }
}
