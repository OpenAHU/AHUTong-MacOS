import Foundation

struct ClassroomCampus: Identifiable, Equatable, Sendable {
    let id: Int
    let name: String

    static let all = [
        ClassroomCampus(id: 1, name: "磬苑校区"),
        ClassroomCampus(id: 2, name: "龙河校区")
    ]
}

struct ClassroomBuilding: Decodable, Identifiable, Equatable, Sendable {
    let code: String
    let enabled: Bool
    let id: Int
    let nameZh: String
}

struct FreeClassroomRoom: Decodable, Identifiable, Equatable, Sendable {
    struct Building: Decodable, Equatable, Sendable {
        let id: Int
        let nameZh: String
    }

    let building: Building
    let code: String
    let floor: Int
    let id: Int
    let nameZh: String
    let remark: String?
    let seats: Int
}

struct FreeClassroomQuery: Equatable, Sendable {
    let campusID: Int
    let buildingIDs: [Int]
    let units: [Int]
    let startDate: Date
    let endDate: Date
}

struct FreeClassroomEnvelope: Decodable, Sendable {
    let roomList: [FreeClassroomRoom]
}

struct FreeClassroomRequest: Encodable, Sendable {
    struct Segment: Encodable, Sendable {
        let endDateTime: String
        let endTime = ""
        let startDateTime: String
        let startTime = ""
        let units: [String]
        let weekdays: [String] = []
    }

    let buildingId: String
    let campusId: String
    let dateTimeSegmentCmd: Segment
    let hasDataPermission = false
    let roomId = ""
    let seatsForLessonGte = ""
}

extension FreeClassroomQuery {
    static func dateString(_ value: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: value)
    }
}
