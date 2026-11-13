import Foundation
import OSLog
import UserNotifications

@MainActor
final class LocalNotifications: NSObject, UNUserNotificationCenterDelegate {
    enum Permission: Equatable {
        case allowed
        case denied
        case notAsked
    }

    nonisolated private static let logger = Logger(subsystem: "com.parkerrex.ai-usage-stats", category: "Notifications")
    private var center: UNUserNotificationCenter { .current() }
    static let nudgeCategory = "nudge"
    static let nudgeWithBurnItemCategory = "nudge-with-burn-item"
    static let copyBurnItemAction = "copy-burn-item"
    static let snoozeAction = "snooze"
    static let notThisWeekAction = "not-this-week"

    var onPermissionChange: (() -> Void)?
    var onAction: ((_ action: String, _ userInfo: [String: String]) -> Void)?
    private(set) var permission: Permission = .notAsked

    func start() {
        center.delegate = self
        let copy = UNNotificationAction(identifier: Self.copyBurnItemAction, title: "Copy Task")
        let snooze = UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze 3 Hours")
        let notThisWeek = UNNotificationAction(identifier: Self.notThisWeekAction, title: "Not This Week")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.nudgeCategory, actions: [snooze, notThisWeek], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.nudgeWithBurnItemCategory, actions: [copy, snooze, notThisWeek],
                                   intentIdentifiers: [])
        ])
        refreshPermission()
    }

    func refreshPermission() {
        Task {
            let settings = await center.notificationSettings()
            update(settings.authorizationStatus)
        }
    }

    func requestPermission() async -> Bool {
        do {
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            update(granted ? .authorized : .denied)
            return granted
        } catch {
            Self.logger.error("Could not ask for notification permission: \(error.localizedDescription, privacy: .public)")
            refreshPermission()
            return false
        }
    }

    private func update(_ status: UNAuthorizationStatus) {
        let next: Permission = switch status {
        case .authorized, .provisional, .ephemeral: .allowed
        case .denied: .denied
        case .notDetermined: .notAsked
        @unknown default: .denied
        }
        guard next != permission else { return }
        permission = next
        onPermissionChange?()
    }

    @discardableResult
    func post(identifier: String, title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) async -> Bool {
        if permission != .allowed { _ = await requestPermission() }
        if CommandLine.arguments.contains("--notification-diagnostics") {
            let outcome = permission == .allowed ? "posted" : "not shown, notifications are not allowed for Little Limits"
            FileHandle.standardError.write(Data("Little Limits notification (\(outcome)) at \(Date().formatted(date: .omitted, time: .standard)):\n\(title)\n\(body)\n\n".utf8))
        }
        guard permission == .allowed else { return false }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let category { content.categoryIdentifier = category }
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            return true
        } catch {
            Self.logger.error("Could not post a notification: \(error.localizedDescription, privacy: .public)")
            return false
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let userInfo = response.notification.request.content.userInfo.reduce(into: [String: String]()) { result, entry in
            if let key = entry.key as? String, let value = entry.value as? String { result[key] = value }
        }
        await MainActor.run { onAction?(action, userInfo) }
    }
}
