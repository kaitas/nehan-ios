import Foundation

class SyncService {
    static let shared = SyncService()

    private var buffer: [LogEntry] = []
    private let queue = DispatchQueue(label: "ai.aicu.nehan.sync")

    func addEntry(_ entry: LogEntry) {
        queue.async {
            self.buffer.append(entry)
            if self.buffer.count >= AppConfig.batchSize {
                Task { await self.sync() }
            }
        }
    }

    func sync() async {
        let entriesToSync: [LogEntry] = queue.sync {
            let entries = buffer
            buffer = []
            return entries
        }

        guard !entriesToSync.isEmpty else { return }

        let batch = LogBatch(entries: entriesToSync.map { $0.toAPI() })

        guard let url = URL(string: "\(AppConfig.workerURL)/api/log") else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(AppConfig.apiToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            request.httpBody = try JSONEncoder().encode(batch)
            let (_, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                print("[nehan] Synced \(entriesToSync.count) entries")
            } else {
                queue.async { self.buffer.insert(contentsOf: entriesToSync, at: 0) }
                print("[nehan] Sync failed, re-buffered")
            }
        } catch {
            queue.async { self.buffer.insert(contentsOf: entriesToSync, at: 0) }
            print("[nehan] Sync error: \(error)")
        }
    }

    var pendingCount: Int {
        queue.sync { buffer.count }
    }
}
