import Foundation
import SwiftUI

enum CoursePeriod {
    static let startTimes: [DateComponents] = [
        DateComponents(hour: 8, minute: 0),
        DateComponents(hour: 8, minute: 50),
        DateComponents(hour: 9, minute: 50),
        DateComponents(hour: 10, minute: 40),
        DateComponents(hour: 11, minute: 30),
        DateComponents(hour: 14, minute: 0),
        DateComponents(hour: 14, minute: 50),
        DateComponents(hour: 15, minute: 50),
        DateComponents(hour: 16, minute: 40),
        DateComponents(hour: 17, minute: 30),
        DateComponents(hour: 19, minute: 0),
        DateComponents(hour: 19, minute: 50),
        DateComponents(hour: 20, minute: 40)
    ]

    static var labels: [String] {
        startTimes.map {
            String(format: "%02d:%02d", $0.hour ?? 0, $0.minute ?? 0)
        }
    }

    static func startTime(for period: Int) -> DateComponents? {
        guard startTimes.indices.contains(period - 1) else { return nil }
        return startTimes[period - 1]
    }
}

enum AppSection: String, CaseIterable, Identifiable {
    case overview = "概览"
    case schedule = "课表"
    case card = "校园卡"
    case grades = "成绩"
    case exams = "考试"
    case freeClassroom = "空闲教室"
    case services = "校园服务"
    case about = "关于"

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .overview: "square.grid.2x2.fill"
        case .schedule: "calendar.day.timeline.left"
        case .card: "creditcard.fill"
        case .grades: "chart.bar.doc.horizontal.fill"
        case .exams: "pencil.and.list.clipboard"
        case .freeClassroom: "door.left.hand.open"
        case .services: "sparkles.square.filled.on.square"
        case .about: "info.circle.fill"
        }
    }
}

struct Course: Identifiable, Hashable {
    let id: String
    let name: String
    let className: String
    let teacher: String
    let room: String
    let weekday: Int
    let start: Int
    let length: Int
    let weekIndexes: [Int]
    let color: Color

    var end: Int { start + length - 1 }
    var weeks: String { Self.compactWeeks(weekIndexes) }

    func isActive(in week: Int) -> Bool {
        weekIndexes.contains(week)
    }

    static func compactWeeks(_ values: [Int]) -> String {
        let weeks = Array(Set(values.filter { $0 > 0 })).sorted()
        guard let first = weeks.first else { return "" }

        var ranges: [String] = []
        var rangeStart = first
        var previous = first
        for week in weeks.dropFirst() {
            if week == previous + 1 {
                previous = week
                continue
            }
            ranges.append(rangeStart == previous ? "\(rangeStart)" : "\(rangeStart)-\(previous)")
            rangeStart = week
            previous = week
        }
        ranges.append(rangeStart == previous ? "\(rangeStart)" : "\(rangeStart)-\(previous)")
        return ranges.joined(separator: ",")
    }
}

struct Grade: Identifiable {
    let id = UUID()
    let course: String
    let credit: Double
    let score: Double
    let type: String
    let reportedPoint: Double?
    let scoreText: String?

    init(
        course: String,
        credit: Double,
        score: Double,
        type: String,
        reportedPoint: Double? = nil,
        scoreText: String? = nil
    ) {
        self.course = course
        self.credit = credit
        self.score = score
        self.type = type
        self.reportedPoint = reportedPoint
        self.scoreText = scoreText
    }

    var point: Double {
        if let reportedPoint { return reportedPoint }
        return switch score {
        case 90...: 4.0
        case 85..<90: 3.7
        case 82..<85: 3.3
        case 78..<82: 3.0
        case 75..<78: 2.7
        case 72..<75: 2.3
        case 68..<72: 2.0
        case 64..<68: 1.5
        case 60..<64: 1.0
        default: 0
        }
    }
}

struct Exam: Identifiable {
    let id = UUID()
    let course: String
    let date: Date
    let place: String
    let seat: String
    let status: String
    let timeText: String?

    init(
        course: String,
        date: Date,
        place: String,
        seat: String,
        status: String,
        timeText: String? = nil
    ) {
        self.course = course
        self.date = date
        self.place = place
        self.seat = seat
        self.status = status
        self.timeText = timeText
    }
}

struct CardTransaction: Identifiable {
    let id = UUID()
    let title: String
    let place: String
    let amount: Double
    let date: Date
    let symbol: String
}

struct CampusService: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let color: Color
    let url: URL?
}

extension Date {
    static func demo(daysFromNow days: Int, hour: Int = 9, minute: Int = 0) -> Date {
        var components = DateComponents()
        components.day = days
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(byAdding: components, to: Calendar.current.startOfDay(for: .now)) ?? .now
    }
}
