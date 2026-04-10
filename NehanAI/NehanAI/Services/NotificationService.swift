import Foundation
import UserNotifications

enum NotificationService {

    private static let blogReminderId = "ai.aicu.nehan.blog-reminder"
    private static let wakeUpReminderId = "ai.aicu.nehan.wakeup-dream"

    /// Request notification permission
    static func requestPermission() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            print("[nehan] Notification permission error: \(error)")
            return false
        }
    }

    // MARK: - Blog Reminder

    /// Schedule daily blog reminder at the user's configured publish hour.
    static func scheduleBlogReminder(hour: Int) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [blogReminderId])

        let content = UNMutableNotificationContent()
        content.title = "nehan.ai"
        content.body = String(localized: "notification_blog_reminder",
                              defaultValue: "今日のブログを書き忘れているよ！")
        content.sound = .default

        var dateComponents = DateComponents()
        dateComponents.hour = hour
        dateComponents.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
        let request = UNNotificationRequest(identifier: blogReminderId, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("[nehan] Failed to schedule blog reminder: \(error)")
            }
        }
    }

    /// Cancel blog reminder (e.g. when today's blog is already written)
    static func cancelBlogReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [blogReminderId])
    }

    // MARK: - Wake-up Dream Diary Reminder

    /// Schedule a notification when the user wakes up to remind about dream diary.
    /// Called when we detect a wake-up event from HealthKit sleep data.
    static func scheduleWakeUpReminder(wakeTime: Date) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [wakeUpReminderId])

        // Don't schedule if wake time is in the past by more than 5 minutes
        let fiveMinutesAfterWake = wakeTime.addingTimeInterval(5 * 60)
        guard fiveMinutesAfterWake > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "nehan.ai"
        content.body = String(localized: "notification_wakeup_dream",
                              defaultValue: "起きた？夢を見たら夢日記を書こう")
        content.sound = .default
        content.categoryIdentifier = "DREAM_DIARY"

        // Fire 5 minutes after detected wake time
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(fiveMinutesAfterWake.timeIntervalSinceNow, 1),
            repeats: false
        )

        let request = UNNotificationRequest(identifier: wakeUpReminderId, content: content, trigger: trigger)

        center.add(request) { error in
            if let error {
                print("[nehan] Failed to schedule wake-up reminder: \(error)")
            }
        }
    }

    /// Cancel wake-up reminder
    static func cancelWakeUpReminder() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [wakeUpReminderId])
    }

    // MARK: - Notification Actions

    /// Register notification categories (call once at app launch)
    static func registerCategories() {
        let openBlogAction = UNNotificationAction(
            identifier: "OPEN_BLOG_EDITOR",
            title: String(localized: "notification_action_write_dream",
                          defaultValue: "夢日記を書く"),
            options: [.foreground]
        )

        let dreamCategory = UNNotificationCategory(
            identifier: "DREAM_DIARY",
            actions: [openBlogAction],
            intentIdentifiers: []
        )

        UNUserNotificationCenter.current().setNotificationCategories([dreamCategory])
    }
}
