import Foundation
import UserNotifications

enum NotificationDedupe {
    static let prefix = "arenadesk.notified."
    static let retentionDays = 7

    static func key(scope: String, id: String, day: String = dayKey()) -> String {
        "\(prefix)\(scope).\(id).\(day)"
    }

    static func claim(_ key: String, defaults: UserDefaults = .standard) -> Bool {
        guard !defaults.bool(forKey: key) else { return false }
        defaults.set(true, forKey: key)
        prune(defaults: defaults)
        return true
    }

    static func prune(defaults: UserDefaults = .standard) {
        let live = Set(recentDayKeys())
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            guard let day = key.split(separator: ".").last, live.contains(String(day)) else {
                defaults.removeObject(forKey: key)
                continue
            }
        }
    }

    static func dayKey(for date: Date = Date()) -> String {
        formatter.string(from: date)
    }

    private static func recentDayKeys(from date: Date = Date()) -> [String] {
        (0..<retentionDays).compactMap { offset in
            Calendar.current
                .date(byAdding: .day, value: -offset, to: date)
                .map(dayKey(for:))
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

enum NotificationHooks {
    static func lowStockIfNeeded(item: InventoryItem, crossed: Bool) {
        guard crossed else { return }
        let key = NotificationDedupe.key(scope: "lowStock", id: item.id.uuidString)
        guard NotificationDedupe.claim(key) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Low stock"
        content.body = "\(item.name) is at or below minimum (\(item.quantity) \(item.unit))."
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: "low-stock-\(item.id.uuidString)",
                content: content,
                trigger: nil
            )
        )
    }

    static func scheduleMaintenance(_ task: MaintenanceTask) {
        guard task.status != .completed, task.scheduledFor > Date() else { return }

        var components = Calendar.current.dateComponents(
            [.year, .month, .day],
            from: task.scheduledFor
        )
        components.hour = 10
        components.minute = 0

        let content = UNMutableNotificationContent()
        content.title = "Maintenance due"
        content.body = task.title
        content.sound = .default
        UNUserNotificationCenter.current().add(
            UNNotificationRequest(
                identifier: identifier(forMaintenance: task.id),
                content: content,
                trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            )
        )
    }

    static func cancelMaintenance(_ taskID: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: [identifier(forMaintenance: taskID)]
        )
    }

    static func identifier(forMaintenance id: UUID) -> String {
        "maintenance-\(id.uuidString.lowercased())"
    }
}
