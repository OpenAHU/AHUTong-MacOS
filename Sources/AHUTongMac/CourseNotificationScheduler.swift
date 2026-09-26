import Foundation
import UserNotifications

enum CourseNotificationScheduleResult: Equatable {
    case scheduled(Int)
    case denied
    case failed(String)
}

@MainActor
final class CourseNotificationScheduler {
    static let shared = CourseNotificationScheduler()

    private let center: UNUserNotificationCenter
    private let identifierPrefix = "org.openahu.ahutong.course-reminder."
    private let maximumPendingReminders = 60

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func replaceScheduledReminders(
        courses: [Course],
        currentWeek: Int,
        referenceDate: Date = .now
    ) async -> CourseNotificationScheduleResult {
        await removePendingCourseReminders()

        guard !courses.isEmpty else { return .scheduled(0) }

        do {
            guard try await ensureAuthorization() else { return .denied }

            let reminders = CourseReminderPlanner.plan(
                courses: courses,
                currentWeek: currentWeek,
                referenceDate: referenceDate
            )
            let selected = reminders.prefix(maximumPendingReminders)

            for reminder in selected {
                let content = UNMutableNotificationContent()
                content.title = "\(reminder.course.name) 还有 30分钟 上课"
                content.body = reminder.course.room
                content.sound = .default
                content.userInfo = [
                    "courseID": reminder.course.id,
                    "week": reminder.week
                ]

                let triggerComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: reminder.fireDate
                )
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: triggerComponents,
                    repeats: false
                )
                let request = UNNotificationRequest(
                    identifier: identifier(for: reminder.course, week: reminder.week),
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
            }

            return .scheduled(selected.count)
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func removePendingCourseReminders() async {
        let identifiers = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(identifierPrefix) }
        guard !identifiers.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private func ensureAuthorization() async throws -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return try await center.requestAuthorization(options: [.alert, .sound])
        case .denied:
            return false
        @unknown default:
            return false
        }
    }

    private func identifier(for course: Course, week: Int) -> String {
        let source = "\(course.id)|\(week)"
        let encoded = Data(source.utf8).base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "=", with: "")
        return identifierPrefix + encoded
    }
}

struct CourseReminderPlanner {
    static func plan(
        courses: [Course],
        currentWeek: Int,
        referenceDate: Date
    ) -> [PlannedReminder] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "zh_CN")
        calendar.timeZone = .current

        let today = calendar.startOfDay(for: referenceDate)
        let weekday = calendar.component(.weekday, from: today)
        let daysSinceMonday = (weekday + 5) % 7
        guard let currentWeekMonday = calendar.date(
            byAdding: .day,
            value: -daysSinceMonday,
            to: today
        ), let semesterMonday = calendar.date(
            byAdding: .day,
            value: -(max(currentWeek, 1) - 1) * 7,
            to: currentWeekMonday
        ) else {
            return []
        }

        return courses.flatMap { course -> [PlannedReminder] in
            guard let startTime = CoursePeriod.startTime(for: course.start) else { return [] }
            return course.weekIndexes.compactMap { week in
                guard week > 0,
                      let courseDay = calendar.date(
                        byAdding: .day,
                        value: (week - 1) * 7 + course.weekday - 1,
                        to: semesterMonday
                      ), let startDate = calendar.date(
                        bySettingHour: startTime.hour ?? 0,
                        minute: startTime.minute ?? 0,
                        second: 0,
                        of: courseDay
                      ), let fireDate = calendar.date(byAdding: .minute, value: -30, to: startDate),
                      fireDate > referenceDate else {
                    return nil
                }
                return PlannedReminder(course: course, week: week, fireDate: fireDate)
            }
        }
        .sorted {
            if $0.fireDate != $1.fireDate { return $0.fireDate < $1.fireDate }
            return $0.course.name < $1.course.name
        }
    }

}

struct PlannedReminder {
    let course: Course
    let week: Int
    let fireDate: Date
}
