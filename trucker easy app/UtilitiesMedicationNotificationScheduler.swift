import Foundation
import SwiftData
import UserNotifications

enum MedicationNotificationScheduler {
    private static func requestAuthorizationIfNeeded() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .notDetermined else { return }
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
        }
    }

    static func syncAll(medications: [Medication], modelContext: ModelContext) {
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: medications.map { "medication.\($0.id.uuidString)" })
        medications.filter(\.isActive).forEach { med in
            schedule(medication: med)
        }
    }

    static func reschedule(_ medication: Medication) {
        requestAuthorizationIfNeeded()
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["medication.\(medication.id.uuidString)"])
        guard medication.isActive else { return }
        schedule(medication: medication)
    }

    private static func schedule(medication: Medication) {
        let center = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Medication Reminder"
        content.body = "Time to take \(medication.name) (\(medication.dosage))."
        content.sound = .default
        content.categoryIdentifier = "MEDICATION_DUE"
        content.userInfo = [
            "medicationId": medication.id.uuidString,
            "medicationName": medication.name
        ]

        let calendar = Calendar.current
        let reminderTimes = medication.allReminderTimes.isEmpty ? [medication.reminderTime] : medication.allReminderTimes
        for (index, time) in reminderTimes.enumerated() {
            let comps = calendar.dateComponents([.hour, .minute], from: time)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            let request = UNNotificationRequest(
                identifier: "medication.\(medication.id.uuidString).\(index)",
                content: content,
                trigger: trigger
            )
            center.add(request)
        }
    }
}
