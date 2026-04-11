import Foundation

/// Handles device registration, API key management, and user profile sync
@MainActor
class AuthService {
    static let shared = AuthService()

    /// Current user profile from server
    private(set) var currentUser: UserInfo?

    struct UserInfo: Codable {
        let id: Int
        let username: String?
        let tier: Int
        let email: String?
        let email_verified_at: String?
        let tos_accepted_at: String?
        let device_id: String
    }

    struct RegisterResponse: Codable {
        let ok: Bool
        let api_key: String
        let user_id: Int
        let tier: Int?
    }

    // MARK: - API Key Access

    /// Returns the per-user API key (Keychain), falling back to legacy AppConfig token
    var apiKey: String {
        if let key = KeychainService.load(key: .apiKey) {
            return key
        }
        // Legacy fallback: use build-time token
        return AppConfig.apiToken
    }

    /// Whether this device has registered and obtained a per-user API key
    var isRegistered: Bool {
        KeychainService.load(key: .apiKey) != nil
    }

    // MARK: - Device ID

    /// Stable device identifier stored in Keychain (survives app reinstall on same device)
    var deviceId: String {
        if let existing = KeychainService.load(key: .deviceId) {
            return existing
        }
        let newId = UUID().uuidString
        _ = KeychainService.save(key: .deviceId, value: newId)
        return newId
    }

    // MARK: - Registration

    /// Register this device as a guest (Tier 0). Called on first launch.
    func register() async {
        guard !isRegistered else {
            print("[nehan] Already registered, skipping")
            await fetchMe()
            return
        }

        let urlString = "\(AppConfig.workerURL)/api/register"
        print("[nehan] Register URL: \(urlString)")
        guard let url = URL(string: urlString) else {
            print("[nehan] Invalid register URL")
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["device_id": deviceId]
        request.httpBody = try? JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[nehan] Registration failed: \((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return
            }

            let result = try JSONDecoder().decode(RegisterResponse.self, from: data)
            _ = KeychainService.save(key: .apiKey, value: result.api_key)
            print("[nehan] Registered: user_id=\(result.user_id)")

            await fetchMe()
        } catch {
            print("[nehan] Registration error: \(error)")
        }
    }

    // MARK: - Profile

    /// Fetch current user profile from server
    func fetchMe() async {
        guard let url = URL(string: "\(AppConfig.workerURL)/api/me") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            currentUser = try JSONDecoder().decode(UserInfo.self, from: data)
        } catch {
            print("[nehan] fetchMe error: \(error)")
        }
    }

    // MARK: - Demographics Sync

    struct DemographicsPayload: Encodable {
        let language: String
        let gender: String
        let birth_year: Int
    }

    /// Sync user demographics (language, gender, birth year) to server
    func syncDemographics(profile: UserProfile) async {
        guard isRegistered else { return }
        guard let url = URL(string: "\(AppConfig.workerURL)/api/me/demographics") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = DemographicsPayload(
            language: profile.language.rawValue,
            gender: profile.biologicalSex.rawValue,
            birth_year: profile.birthYear
        )
        request.httpBody = try? JSONEncoder().encode(payload)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(status) {
                print("[nehan] Demographics synced")
            } else {
                print("[nehan] Demographics sync failed: \(status)")
            }
        } catch {
            print("[nehan] Demographics sync error: \(error)")
        }
    }

    // MARK: - Email Verification

    /// Send verification email
    func sendVerificationEmail(_ email: String) async throws {
        guard let url = URL(string: "\(AppConfig.workerURL)/api/verify-email/send") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["email": email])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            print("[nehan] Email send failed: HTTP \(status) — \(body)")
            throw URLError(.badServerResponse)
        }
    }

    /// Confirm verification code
    func confirmVerificationCode(_ code: String) async throws {
        guard let url = URL(string: "\(AppConfig.workerURL)/api/verify-email/confirm") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["code": code])

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Upgrade to Tier 1

    struct UpgradeRequest: Encodable {
        let username: String
        let tos_version: String
    }

    /// Upgrade from guest to registered user (Tier 1)
    func upgrade(username: String, tosVersion: String = "2026-04-11") async throws {
        guard let url = URL(string: "\(AppConfig.workerURL)/api/upgrade") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(UpgradeRequest(username: username, tos_version: tosVersion))

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        await fetchMe()
    }

    // MARK: - Account Deletion

    /// Delete account and all data
    func deleteAccount() async throws {
        guard let url = URL(string: "\(AppConfig.workerURL)/api/account") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Clear local state
        KeychainService.deleteAll()
        currentUser = nil
    }

    // MARK: - Username Check

    struct UsernameCheckResult: Codable {
        let available: Bool
        let reason: String?
    }

    func checkUsername(_ name: String) async throws -> UsernameCheckResult {
        guard let url = URL(string: "\(AppConfig.workerURL)/api/username/check?name=\(name)") else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try JSONDecoder().decode(UsernameCheckResult.self, from: data)
    }
}
