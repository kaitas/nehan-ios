import SwiftUI
import BackgroundTasks

@main
struct NehanAIApp: App {
    init() {
        registerBackgroundTasks()
        scheduleSync()
        scheduleSleepFetch()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.aicu.nehan.sync", using: nil) { task in
            self.handleSync(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.aicu.nehan.sleep", using: nil) { task in
            self.handleSleepFetch(task: task as! BGProcessingTask)
        }
    }

    private func handleSync(task: BGProcessingTask) {
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            await SyncService.shared.sync()
            task.setTaskCompleted(success: true)
            scheduleSync()
        }
    }

    private func handleSleepFetch(task: BGProcessingTask) {
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            let hk = HealthKitService.shared
            do {
                if let sleepEntry = try await hk.fetchSleepData(for: Date()) {
                    SyncService.shared.addEntry(sleepEntry)
                }
                if let healthEntry = try await hk.fetchDailyHealthData(for: Date()) {
                    SyncService.shared.addEntry(healthEntry)
                }
                await SyncService.shared.sync()
            } catch {
                print("[nehan] Health fetch error: \(error)")
            }
            task.setTaskCompleted(success: true)
            scheduleSleepFetch()
        }
    }

    func scheduleSync() {
        let request = BGProcessingTaskRequest(identifier: "ai.aicu.nehan.sync")
        request.earliestBeginDate = Date(timeIntervalSinceNow: AppConfig.syncIntervalMinutes * 60)
        request.requiresNetworkConnectivity = true
        try? BGTaskScheduler.shared.submit(request)
    }

    func scheduleSleepFetch() {
        let request = BGProcessingTaskRequest(identifier: "ai.aicu.nehan.sleep")
        let calendar = Calendar.current
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: Date()) {
            var components = calendar.dateComponents([.year, .month, .day], from: tomorrow)
            components.hour = 7
            components.minute = 0
            request.earliestBeginDate = calendar.date(from: components)
        }
        try? BGTaskScheduler.shared.submit(request)
    }
}
