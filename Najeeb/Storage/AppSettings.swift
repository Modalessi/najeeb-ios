import Foundation

struct AppSettings: Codable, Equatable {
    var agentID = "agent_0701m4jn0m0ffbb9wr52bf76m447"
    var tokenEndpoint = ""

    static var saved: AppSettings {
        guard let data = UserDefaults.standard.data(forKey: "najeeb.settings"),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data) else {
            return AppSettings()
        }
        return settings
    }

    func save() throws {
        UserDefaults.standard.set(try JSONEncoder().encode(self), forKey: "najeeb.settings")
    }
}
