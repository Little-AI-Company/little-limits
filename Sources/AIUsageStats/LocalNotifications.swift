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
    var onPermissionChange: (() -> Void)?
    private(set) var permission: Permission = .notAsked

    func start() {
        center.delegate = self
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

    func post(identifier: String, title: String, body: String, category: String? = nil, userInfo: [String: String] = [:]) async {
        if permission != .allowed { _ = await requestPermission() }
        guard permission == .allowed else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.userInfo = userInfo
        if let category { content.categoryIdentifier = category }
        do {
            try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        } catch {
            Self.logger.error("Could not post a notification: \(error.localizedDescription, privacy: .public)")
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
