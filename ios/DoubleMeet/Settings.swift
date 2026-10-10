import Foundation

/// App settings. Seeded from Config.plist in the bundle, overridable in the app (stored in UserDefaults).
struct Settings {
    var supabaseURL: String
    var supabaseKey: String
    var room: String
    var meetURL: String
    var guestName: String

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
            room: value("Room", ""),
            meetURL: value("MeetURL", "https://meet.google.com/"),
            guestName: value("GuestName", "Double")
        )
    }

    func save() {
        let d = Settings.defaults
        d.set(supabaseURL, forKey: Settings.prefix + "SupabaseURL")
        d.set(supabaseKey, forKey: Settings.prefix + "SupabaseKey")
        d.set(room, forKey: Settings.prefix + "Room")
        d.set(meetURL, forKey: Settings.prefix + "MeetURL")
        d.set(guestName, forKey: Settings.prefix + "GuestName")
    }

    var isRealtimeConfigured: Bool {
        !supabaseURL.isEmpty && !supabaseKey.isEmpty && !room.isEmpty
            && !supabaseURL.contains("YOUR-PROJECT") && !room.contains("CHANGE-ME")
    }

    private static func bundledConfig() -> [String: Any] {
        guard let url = Bundle.main.url(forResource: "Config", withExtension: "plist"),
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }
}
