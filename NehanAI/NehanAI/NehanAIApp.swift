import SwiftUI
import BackgroundTasks

/// Shared flag: when true, ContentView opens the blog editor (dream diary focus)
@Observable
class AppState {
    static let shared = AppState()
    var shouldOpenBlogEditor = false
}

@main
struct NehanAIApp: App {
    @State private var profileStore = UserProfileStore.shared
    @State private var showIntelligenceAlert = false
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        NotificationService.registerCategories()
        registerBackgroundTasks()
        scheduleSync()
        scheduleSleepFetch()
        scheduleBlogPublish()
    }

    /// Show FTUE if: profile not completed OR auth not established (no API key in Keychain)
    private var needsFTUE: Bool {
        !profileStore.profile.onboardingCompleted || !AuthService.shared.isRegistered
    }

    var body: some Scene {
        WindowGroup {
            if needsFTUE {
                OnboardingView(profileStore: profileStore)
            } else {
                ContentView()
                    .task {
                        // Re-register if needed (e.g. key was cleared)
                        if !AuthService.shared.isRegistered {
                            await AuthService.shared.register()
                        }
                        await AuthService.shared.fetchMe()
                        await AuthService.shared.syncDemographics(profile: profileStore.profile)
                        await setupNotifications()
                    }
                    .onAppear { checkAppleIntelligence() }
                    .alert("Apple Intelligence", isPresented: $showIntelligenceAlert) {
                        Button("OK", role: .cancel) {}
                    } message: {
                        Text("お使いの端末ではApple Intelligence機能が利用できません。一部の機能が制限されます。")
                    }
            }
        }
    }

    /// Show a one-time alert when Apple Intelligence is not available on this device.
    private func checkAppleIntelligence() {
        let key = "hasShownIntelligenceAlert"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        var available = false
        if #available(iOS 26.0, *) {
            available = FoundationModelService.isAvailable
        }

        if !available {
            showIntelligenceAlert = true
            UserDefaults.standard.set(true, forKey: key)
        }
    }
}

// MARK: - Notification Delegate

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    /// Handle notification tap
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        if response.actionIdentifier == "OPEN_BLOG_EDITOR"
            || response.notification.request.content.categoryIdentifier == "DREAM_DIARY" {
            await MainActor.run {
                AppState.shared.shouldOpenBlogEditor = true
            }
        }
    }

    /// Show notification even when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

extension NehanAIApp {

    private func setupNotifications() async {
        let granted = await NotificationService.requestPermission()
        if granted {
            let hour = profileStore.profile.blogPublishHour
            let todayStr = {
                let f = DateFormatter()
                f.dateFormat = "yyyy-MM-dd"
                f.timeZone = TimeZone(identifier: "Asia/Tokyo")
                return f.string(from: Date())
            }()
            if profileStore.profile.lastBlogDate == todayStr {
                NotificationService.cancelBlogReminder()
            } else {
                NotificationService.scheduleBlogReminder(hour: hour)
            }

            // Check if user just woke up → schedule dream diary reminder
            if let summary = try? await HealthKitService.shared.fetchSleepSummary(for: Date()),
               let awake = summary.awake {
                NotificationService.scheduleWakeUpReminder(wakeTime: awake)
            }
        }
    }

    private func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.aicu.nehan.sync", using: nil) { task in
            self.handleSync(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.aicu.nehan.sleep", using: nil) { task in
            self.handleSleepFetch(task: task as! BGProcessingTask)
        }

        BGTaskScheduler.shared.register(forTaskWithIdentifier: "ai.aicu.nehan.blogpublish", using: nil) { task in
            self.handleBlogPublish(task: task as! BGProcessingTask)
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

                // Schedule wake-up notification if we detected a wake time
                if let summary = try await hk.fetchSleepSummary(for: Date()),
                   let awake = summary.awake {
                    NotificationService.scheduleWakeUpReminder(wakeTime: awake)
                }
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

    private func handleBlogPublish(task: BGProcessingTask) {
        task.expirationHandler = { task.setTaskCompleted(success: false) }
        Task {
            await BlogPublishService.scheduledPublish()
            task.setTaskCompleted(success: true)
            scheduleBlogPublish()
        }
    }

    func scheduleBlogPublish() {
        let request = BGProcessingTaskRequest(identifier: "ai.aicu.nehan.blogpublish")
        request.requiresNetworkConnectivity = true

        // Schedule at the user's publish hour
        let calendar = Calendar.current
        let now = Date()
        let hour = profileStore.profile.blogPublishHour
        var components = calendar.dateComponents([.year, .month, .day], from: now)
        components.hour = hour
        components.minute = 0

        if let targetDate = calendar.date(from: components) {
            // If already past today's publish hour, schedule for tomorrow
            if targetDate <= now {
                request.earliestBeginDate = calendar.date(byAdding: .day, value: 1, to: targetDate)
            } else {
                request.earliestBeginDate = targetDate
            }
        }
        try? BGTaskScheduler.shared.submit(request)
    }
}
