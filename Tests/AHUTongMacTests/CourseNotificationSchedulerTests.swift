import Foundation
import SwiftUI
import Testing
@testable import AHUTongMac

struct CourseNotificationSchedulerTests {
    @Test("根据当前教学周计算课前 30 分钟的提醒时间")
    func computesReminderFromTeachingWeek() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21,
            hour: 12
        )))
        let course = Course(
            id: "course-1",
            name: "测试课程",
            className: "测试班级",
            teacher: "测试教师",
            room: "龙河校区 测试教室",
            weekday: 2,
            start: 1,
            length: 2,
            weekIndexes: [4],
            color: .blue
        )

        let reminders = CourseReminderPlanner.plan(
            courses: [course],
            currentWeek: 4,
            referenceDate: referenceDate
        )

        let reminder = try #require(reminders.first)
        let components = calendar.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: reminder.fireDate
        )
        #expect(reminders.count == 1)
        #expect(components.year == 2026)
        #expect(components.month == 9)
        #expect(components.day == 22)
        #expect(components.hour == 7)
        #expect(components.minute == 30)
    }

    @Test("第 13 节课程在 20:10 提醒")
    func computesLastPeriodReminder() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 21,
            hour: 12
        )))
        let course = Course(
            id: "course-13",
            name: "晚间课程",
            className: "",
            teacher: "",
            room: "教室 13",
            weekday: 1,
            start: 13,
            length: 1,
            weekIndexes: [4],
            color: .purple
        )

        let reminders = CourseReminderPlanner.plan(
            courses: [course],
            currentWeek: 4,
            referenceDate: referenceDate
        )

        let reminder = try #require(reminders.first)
        let components = calendar.dateComponents([.hour, .minute], from: reminder.fireDate)
        #expect(components.hour == 20)
        #expect(components.minute == 10)
    }

    @Test("不会为已经过去的课程安排提醒")
    func excludesPastReminders() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let referenceDate = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 9,
            day: 23,
            hour: 12
        )))
        let course = Course(
            id: "past-course",
            name: "过去的课程",
            className: "",
            teacher: "",
            room: "测试教室",
            weekday: 2,
            start: 1,
            length: 2,
            weekIndexes: [4],
            color: .orange
        )

        let reminders = CourseReminderPlanner.plan(
            courses: [course],
            currentWeek: 4,
            referenceDate: referenceDate
        )

        #expect(reminders.isEmpty)
    }
}
