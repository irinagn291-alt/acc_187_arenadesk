import Foundation
import UserNotifications

@MainActor
final class NotificationService: ObservableObject {
    @Published var isEnabled: Bool {
        didSet { UserDefaults.standard.set(isEnabled, forKey: UserDefaultsKeys.notificationsEnabled) }
    }

    init() {
        isEnabled = UserDefaults.standard.bool(forKey: UserDefaultsKeys.notificationsEnabled)
    }

    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        isEnabled = granted
    }

    func notifyCriticalSeat(label: String, score: Int) {
        guard isEnabled else { return }
        let key = NotificationDedupe.key(scope: "critical", id: label)
        guard NotificationDedupe.claim(key) else { return }
        post(id: "critical-\(label)", title: "Critical seat", body: "\(label) health is \(score).")
    }

    func notifyTournament(id: UUID, name: String, at date: Date) {
        guard isEnabled, date > Date() else { return }
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: date
        )
        let content = UNMutableNotificationContent()
        content.title = "Tournament"
        content.body = name
        content.sound = .default
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "tournament-\(id.uuidString.lowercased())",
                content: content,
                trigger: trigger
            )
        )
    }

    func scheduleMaintenance(_ tasks: [MaintenanceTask]) {
        guard isEnabled else { return }
        for task in tasks {
            NotificationHooks.scheduleMaintenance(task)
        }
    }

    private func post(id: String, title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: id, content: content, trigger: nil)
        )
    }
}
