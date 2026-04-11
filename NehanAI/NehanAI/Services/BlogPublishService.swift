import Foundation
import UIKit

enum BlogPublishService {

    private static let blogEntryKey = "nehan_pending_blog"
    private static let blogTitleKey = "nehan_pending_blog_title"

    struct RequestBody: Encodable {
        let username: String
        let date: String
        let title: String
        let body: String
        let cover_url: String?
        let is_draft: Bool
    }

    // MARK: - Local persistence

    /// Save blog entry locally (auto-save, called frequently)
    static func saveLocal(_ entry: BlogEntry) {
        UserDefaults.standard.set(entry.fullText, forKey: blogEntryKey)
        UserDefaults.standard.set(entry.title, forKey: blogTitleKey)
    }

    // MARK: - Cloud operations

    /// Save as draft to cloud
    static func saveDraft(entry: BlogEntry) async throws {
        try await send(entry: entry, isDraft: true)
    }

    /// Publish to cloud (public)
    static func publish(entry: BlogEntry) async throws {
        try await send(entry: entry, isDraft: false)
        UserDefaults.standard.removeObject(forKey: blogEntryKey)
        UserDefaults.standard.removeObject(forKey: blogTitleKey)
    }

    private static func send(entry: BlogEntry, isDraft: Bool) async throws {
        let jstFormatter = DateFormatter()
        jstFormatter.dateFormat = "yyyy-MM-dd"
        jstFormatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        let dateString = jstFormatter.string(from: Date())

        // Username comes from server auth context for registered users
        let username = AuthService.shared.currentUser?.username
            ?? UserProfileStore.shared.profile.displayName

        // Upload cover image to R2 if available
        var coverURL = entry.coverURL
        if let image = entry.coverImage {
            if let uploaded = try? await uploadCover(image: image, username: username, date: dateString) {
                coverURL = uploaded
            }
        }

        guard let url = URL(string: "\(AppConfig.workerURL)/api/blog") else {
            throw URLError(.badURL)
        }

        let title = entry.title.isEmpty ? entry.autoTitle : entry.title

        let payload = RequestBody(
            username: username,
            date: dateString,
            title: title,
            body: entry.fullText,
            cover_url: coverURL.isEmpty ? nil : coverURL,
            is_draft: isDraft
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AuthService.shared.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        print("[nehan] Blog \(isDraft ? "draft saved" : "published") for \(dateString)")
    }

    // MARK: - Cover image upload

    /// Upload cover art PNG to R2 via Worker
    private static func uploadCover(image: UIImage, username: String, date: String) async throws -> String {
        guard let pngData = image.pngData() else {
            throw URLError(.cannotDecodeContentData)
        }

        guard let url = URL(string: "\(AppConfig.workerURL)/api/blog/cover") else {
            throw URLError(.badURL)
        }

        let boundary = UUID().uuidString
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AuthService.shared.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        // username field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"username\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(username)\r\n".data(using: .utf8)!)
        // date field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"date\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(date)\r\n".data(using: .utf8)!)
        // image field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"cover.png\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/png\r\n\r\n".data(using: .utf8)!)
        body.append(pngData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        // Parse response to get cover_url
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let coverUrl = json["cover_url"] as? String {
            print("[nehan] Cover uploaded: \(coverUrl) (\(pngData.count) bytes)")
            return coverUrl
        }

        return ""
    }

    /// Auto-publish pending blog (called from BGTask)
    static func scheduledPublish() async {
        guard let text = UserDefaults.standard.string(forKey: blogEntryKey), !text.isEmpty else {
            print("[nehan] No pending blog to publish")
            return
        }

        var entry = BlogEntry()
        entry.dateWeatherHealth = text
        entry.title = UserDefaults.standard.string(forKey: blogTitleKey) ?? entry.autoTitle
        do {
            try await publish(entry: entry)
            UserProfileStore.shared.recordBlogPost()
        } catch {
            print("[nehan] Scheduled blog publish failed: \(error)")
        }
    }
}
