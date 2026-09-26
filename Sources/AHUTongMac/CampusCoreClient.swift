import Foundation

@_silgen_name("ahutong_start_server")
private func ahutong_start_server(_ port: UInt16) -> UnsafeMutablePointer<CChar>?

@_silgen_name("ahutong_free_string")
private func ahutong_free_string(_ pointer: UnsafeMutablePointer<CChar>?)

@_silgen_name("ahutong_init_persistence")
private func ahutong_init_persistence(
    _ storagePath: UnsafePointer<CChar>,
    _ seedCookiesJSON: UnsafePointer<CChar>,
    _ persistSession: UInt8
) -> UnsafeMutablePointer<CChar>?

enum CampusClientError: LocalizedError, Sendable {
    case startup(String)
    case invalidResponse
    case invalidCredentials
    case service(String)
    case security(String)

    var errorDescription: String? {
        switch self {
        case let .startup(message): "校园数据服务启动失败：\(message)"
        case .invalidResponse: "学校服务返回了无法识别的数据"
        case .invalidCredentials: "账号、密码或验证码不正确"
        case let .service(message): message
        case let .security(message): message
        }
    }
}

struct CampusUser: Sendable {
    let name: String
    let studentID: String
}

struct CampusCourse: Identifiable, Sendable {
    let id: String
    let name: String
    let className: String
    let teacher: String
    let location: String
    let weekday: Int
    let startPeriod: Int
    let duration: Int
    let weeks: [Int]
}

struct CampusGrade: Identifiable, Sendable {
    let id: String
    let name: String
    let credit: Double
    let score: String
    let point: Double
    let type: String
    let semester: String
}

struct CampusExamItem: Identifiable, Sendable {
    let id: String
    let course: String
    let time: String
    let location: String
    let seat: String
    let finished: Bool
}

struct CampusSnapshot: Sendable {
    var currentWeek: Int?
    var courses: [CampusCourse]
    var grades: [CampusGrade]
    var exams: [CampusExamItem]
    var balance: Double?
    var cardQRCode: String?
    var warnings: [String]
}

actor CampusCoreClient {
    static let shared = CampusCoreClient()

    private struct ServerDescriptor: Decodable {
        let ok: Bool
        let port: UInt16?
        let token: String?
        let error: String?
    }

    private var baseURL: URL?
    private var token: String?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func prepare() throws {
        guard baseURL == nil else { return }
        let fileManager = FileManager.default
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ).appendingPathComponent("AHUTong", isDirectory: true)
        try fileManager.createDirectory(at: support, withIntermediateDirectories: true)
        let databasePath = support.appendingPathComponent("campus.guixu").path

        let persistenceResponse: String = databasePath.withCString { path in
            "".withCString { cookies in
                consume(ahutong_init_persistence(path, cookies, 0))
            }
        }
        guard let persistenceData = persistenceResponse.data(using: .utf8),
              let persistence = try? JSONSerialization.jsonObject(with: persistenceData) as? [String: Any],
              persistence["ok"] as? Bool == true else {
            throw CampusClientError.startup("本地安全存储初始化失败")
        }

        let descriptorString = consume(ahutong_start_server(0))
        guard let descriptorData = descriptorString.data(using: .utf8),
              let descriptor = try? JSONDecoder().decode(ServerDescriptor.self, from: descriptorData),
              descriptor.ok,
              let port = descriptor.port,
              let token = descriptor.token,
              let url = URL(string: "http://127.0.0.1:\(port)") else {
            throw CampusClientError.startup("本地接口未能启动")
        }
        baseURL = url
        self.token = token
    }

    func login(studentID: String, password: String) async throws -> CampusUser {
        try prepare()
        _ = try await request(path: "/init", method: "POST", json: ["cookies_json": ""])
        let data = try await request(
            path: "/login",
            method: "POST",
            json: ["username": studentID, "password": password],
            timeout: 330
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CampusClientError.invalidResponse
        }
        let name = scalar(object["name"])
        let returnedID = scalar(object["xh"])
        guard !returnedID.isEmpty else { throw CampusClientError.invalidResponse }
        return CampusUser(name: name.isEmpty ? "安大学生" : name, studentID: returnedID)
    }

    func loadSnapshot() async -> CampusSnapshot {
        var snapshot = CampusSnapshot(
            currentWeek: nil,
            courses: [],
            grades: [],
            exams: [],
            balance: nil,
            cardQRCode: nil,
            warnings: []
        )

        do { snapshot.currentWeek = try await currentWeek() }
        catch { snapshot.warnings.append("教学周：\(safeMessage(error))") }
        do { snapshot.courses = try await courses() }
        catch { snapshot.warnings.append("课表：\(safeMessage(error))") }
        do { snapshot.grades = try await grades() }
        catch { snapshot.warnings.append("成绩：\(safeMessage(error))") }
        do { snapshot.exams = try await exams() }
        catch { snapshot.warnings.append("考试：\(safeMessage(error))") }
        do { snapshot.balance = try await balance() }
        catch { snapshot.warnings.append("校园卡余额：\(safeMessage(error))") }
        do { snapshot.cardQRCode = try await cardQRCode() }
        catch { snapshot.warnings.append("校园卡二维码：\(safeMessage(error))") }
        return snapshot
    }

    private func currentWeek() async throws -> Int {
        let data = try await request(path: "/schedule/current-week")
        let object = try JSONSerialization.jsonObject(with: data)
        guard let week = findInt(keys: ["week", "weekIndex", "currentWeek", "teachWeek"], in: object) else {
            throw CampusClientError.invalidResponse
        }
        return week
    }

    private func courses() async throws -> [CampusCourse] {
        let data = try await request(path: "/schedule")
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CampusClientError.invalidResponse
        }
        return array.compactMap { item in
            let name = scalar(item["name"])
            let weekday = number(item["weekday"]).map(Int.init) ?? 0
            let start = number(item["startTime"]).map(Int.init) ?? 0
            let length = number(item["length"]).map(Int.init) ?? 0
            guard !name.isEmpty, (1...7).contains(weekday), start > 0, length > 0 else { return nil }
            let weeks = (item["weekIndexes"] as? [Any])?.compactMap { number($0).map(Int.init) } ?? []
            let courseID = scalar(item["courseId"])
            let teacher = scalar(item["teacher"])
            let normalizedWeeks = Array(Set(weeks.filter { $0 > 0 })).sorted()
            return CampusCourse(
                id: [courseID, name, String(weekday), String(start), normalizedWeeks.map(String.init).joined(separator: ","), teacher].joined(separator: "|"),
                name: name,
                className: scalar(item["className"]),
                teacher: teacher,
                location: scalar(item["location"]),
                weekday: weekday,
                startPeriod: start,
                duration: length,
                weeks: normalizedWeeks
            )
        }
    }

    private func grades() async throws -> [CampusGrade] {
        let data = try await request(path: "/grade")
        let object = try JSONSerialization.jsonObject(with: data)
        let candidates = dictionaries(in: object).filter { item in
            let keys = Set(item.keys)
            return !keys.isDisjoint(with: ["courseName", "courseNameZh", "lessonName", "course"])
                && !keys.isDisjoint(with: ["grade", "score", "gaGrade", "gradePoint"])
        }
        var seen = Set<String>()
        return candidates.compactMap { item in
            let name = firstString(["courseName", "courseNameZh", "lessonName", "course"], in: item)
            guard !name.isEmpty else { return nil }
            let code = firstString(["courseCode", "lessonCode", "courseNum"], in: item)
            let semester = firstString(["semesterName", "term"], in: item)
            let id = "\(code)|\(name)|\(semester)"
            guard seen.insert(id).inserted else { return nil }
            return CampusGrade(
                id: id,
                name: name,
                credit: firstNumber(["credit", "credits"], in: item) ?? 0,
                score: firstString(["grade", "score", "gaGrade"], in: item),
                point: firstNumber(["gradePoint", "gp"], in: item) ?? 0,
                type: firstString(["courseProperty", "courseType", "courseNature"], in: item),
                semester: semester
            )
        }
    }

    private func exams() async throws -> [CampusExamItem] {
        let data = try await request(path: "/exam")
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CampusClientError.invalidResponse
        }
        return array.map { item in
            let course = scalar(item["course"])
            let time = scalar(item["time"])
            let seat = scalar(item["seatNum"])
            return CampusExamItem(
                id: "\(course)|\(time)|\(seat)",
                course: course,
                time: time,
                location: scalar(item["location"]),
                seat: seat,
                finished: (item["finished"] as? Bool) ?? number(item["finished"]).map { $0 != 0 } ?? false
            )
        }
    }

    private func balance() async throws -> Double {
        let data = try await request(path: "/ycard/balance")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["code"]).map(Int.init) == 10_000,
              let result = number(root["object"]) else {
            throw CampusClientError.invalidResponse
        }
        return result
    }

    private func cardQRCode() async throws -> String {
        let data = try await request(path: "/ycard/qrcode")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["code"]).map(Int.init) == 10_000 else {
            throw CampusClientError.invalidResponse
        }
        let payload = scalar(root["object"])
        guard !payload.isEmpty else { throw CampusClientError.invalidResponse }
        return payload
    }

    private func request(
        path: String,
        method: String = "GET",
        json: [String: String]? = nil,
        timeout: TimeInterval = 60
    ) async throws -> Data {
        try prepare()
        guard let baseURL, let token else { throw CampusClientError.startup("服务未就绪") }
        var request = URLRequest(url: baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(token, forHTTPHeaderField: "X-AHUTONG-TOKEN")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CampusClientError.invalidResponse }
        if response.statusCode == 401 { throw CampusClientError.invalidCredentials }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            switch code {
            case "campus_login_rejected": throw CampusClientError.invalidCredentials
            case "campus_service_unavailable", "campus_service_error":
                throw CampusClientError.service("学校服务暂时不可用，请稍后重试")
            default: throw CampusClientError.service("学校服务请求失败（\(response.statusCode)）")
            }
        }
        return data
    }

    private func consume(_ pointer: UnsafeMutablePointer<CChar>?) -> String {
        guard let pointer else { return "" }
        defer { ahutong_free_string(pointer) }
        return String(cString: pointer)
    }

    private func safeMessage(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? "暂时不可用"
    }

    private func scalar(_ value: Any?) -> String {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        if let object = value as? [String: Any] {
            return firstString(["nameZh", "name", "value"], in: object)
        }
        return ""
    }

    private func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private func firstString(_ keys: [String], in object: [String: Any]) -> String {
        for key in keys {
            let value = scalar(object[key])
            if !value.isEmpty { return value }
        }
        return ""
    }

    private func firstNumber(_ keys: [String], in object: [String: Any]) -> Double? {
        for key in keys where number(object[key]) != nil { return number(object[key]) }
        return nil
    }

    private func dictionaries(in value: Any) -> [[String: Any]] {
        if let object = value as? [String: Any] {
            return [object] + object.values.flatMap(dictionaries)
        }
        if let array = value as? [Any] { return array.flatMap(dictionaries) }
        return []
    }

    private func findInt(keys: [String], in value: Any) -> Int? {
        if let direct = number(value).map(Int.init) { return direct }
        if let object = value as? [String: Any] {
            for key in keys {
                if let result = number(object[key]).map(Int.init) { return result }
            }
            for nested in object.values {
                if let result = findInt(keys: keys, in: nested) { return result }
            }
        }
        if let array = value as? [Any] {
            for nested in array {
                if let result = findInt(keys: keys, in: nested) { return result }
            }
        }
        return nil
    }
}
