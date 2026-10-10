import Foundation

/// Signs the robot's service account in to Supabase Auth (email + password) and keeps the
/// access token fresh. The token is what lets the robot join the private Realtime channel.
/// All callbacks run on the main queue.
final class AuthSession {
    var onToken: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private(set) var accessToken: String?

    private let baseURL: URL
    private let apiKey: String
    private let email: String
    private let password: String
    private var refreshToken: String?
    private var refreshTimer: Timer?
    private var retryDelay: TimeInterval = 5

    init?(projectURL: String, apiKey: String, email: String, password: String) {
        guard let url = URL(string: projectURL.trimmingCharacters(in: .whitespaces)), url.host != nil,
              !email.isEmpty, !password.isEmpty else { return nil }
        baseURL = url
        self.apiKey = apiKey
        self.email = email
        self.password = password
    }

    func start() {
        signIn()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func signIn() {
        request(grantType: "password", body: ["email": email, "password": password])
    }

    private func refresh() {
        guard let token = refreshToken else { return signIn() }
        request(grantType: "refresh_token", body: ["refresh_token": token])
    }

    private func request(grantType: String, body: [String: String]) {
        var components = URLComponents(url: baseURL.appendingPathComponent("auth/v1/token"),
                                       resolvingAgainstBaseURL: false)!
        components.queryItems = [URLQueryItem(name: "grant_type", value: grantType)]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                self?.handle(grantType: grantType, data: data, response: response, error: error)
            }
        }.resume()
    }

    private func handle(grantType: String, data: Data?, response: URLResponse?, error: Error?) {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]

        guard status == 200,
              let access = json["access_token"] as? String,
              let refresh = json["refresh_token"] as? String else {
            let message = (json["error_description"] as? String) ?? (json["msg"] as? String)
                ?? error?.localizedDescription ?? "HTTP \(status)"
            NSLog("[auth] \(grantType) failed: \(message)")
            onError?(message)
            // A rejected refresh token means start over with the password.
            if grantType == "refresh_token" && (400..<500).contains(status) { refreshToken = nil }
            schedule(after: retryDelay)
            retryDelay = min(retryDelay * 2, 300)
            return
        }

        retryDelay = 5
        accessToken = access
        refreshToken = refresh
        let expiresIn = (json["expires_in"] as? NSNumber)?.doubleValue ?? 3600
        schedule(after: max(expiresIn - 300, 60))
        onToken?(access)
    }

    private func schedule(after delay: TimeInterval) {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            self?.refresh()
        }
    }
}
