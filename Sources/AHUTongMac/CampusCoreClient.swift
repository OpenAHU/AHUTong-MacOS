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
    case sessionExpired
    case service(String)
    case security(String)

    var errorDescription: String? {
        switch self {
        case let .startup(message): "校园数据服务启动失败：\(message)"
        case .invalidResponse: "学校服务返回了无法识别的数据"
        case .invalidCredentials: "账号、密码或验证码不正确"
        case .sessionExpired: "校园登录已过期，请重新登录"
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

struct CampusScheduleSemester: Identifiable, Decodable, Equatable, Sendable {
    let id: String
    let name: String
    let current: Bool

    private enum CodingKeys: String, CodingKey { case id, name, current }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let numericID = try? container.decode(Int.self, forKey: .id) {
            id = String(numericID)
        } else {
            id = try container.decode(String.self, forKey: .id)
        }
        name = try container.decode(String.self, forKey: .name)
        current = try container.decodeIfPresent(Bool.self, forKey: .current) ?? false
    }
}

struct CampusGrade: Identifiable, Sendable {
    let id: String
    let name: String
    let credit: Double
    let score: String
    let point: Double
    let type: String
    let semester: String
    let semesterID: String
    let detail: String
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
    var sessionExpired = false
}

private struct CampusWebCookie: Decodable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String?
    let secure: Bool?

    func matches(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        let normalizedDomain = domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = host == normalizedDomain || host.hasSuffix(".\(normalizedDomain)")
        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = path.flatMap { $0.isEmpty ? nil : $0 } ?? "/"
        let pathMatches = requestPath == cookiePath
            || (requestPath.hasPrefix(cookiePath)
                && (cookiePath.hasSuffix("/") || requestPath.dropFirst(cookiePath.count).first == "/"))
        return domainMatches && pathMatches && (secure != true || url.scheme == "https")
    }
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

    init(session: URLSession = .shared, baseURL: URL? = nil, token: String? = nil) {
        self.session = session
        self.baseURL = baseURL
        self.token = token
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
        func recordFailure(_ label: String, _ error: Error) {
            snapshot.warnings.append("\(label)：\(safeMessage(error))")
            if let error = error as? CampusClientError, case .sessionExpired = error {
                snapshot.sessionExpired = true
            }
        }

        do { snapshot.currentWeek = try await currentWeek() }
        catch { recordFailure("教学周", error) }
        do { snapshot.courses = try await courses() }
        catch { recordFailure("课表", error) }
        do { snapshot.grades = try await grades() }
        catch { recordFailure("成绩", error) }
        do { snapshot.exams = try await exams() }
        catch { recordFailure("考试", error) }
        do { snapshot.balance = try await balance() }
        catch { recordFailure("校园卡余额", error) }
        do { snapshot.cardQRCode = try await cardQRCode() }
        catch { recordFailure("校园卡二维码", error) }
        return snapshot
    }

    func freeClassroomBuildings(campusID: Int) async throws -> [ClassroomBuilding] {
        guard (1...2).contains(campusID) else {
            throw CampusClientError.service("请选择有效校区")
        }
        var components = URLComponents(string: "https://jw.ahu.edu.cn/student/ws/room/get-buildings")
        components?.queryItems = [
            URLQueryItem(name: "campusId", value: String(campusID)),
            URLQueryItem(name: "hasDataPermission", value: "false")
        ]
        guard let url = components?.url else { throw CampusClientError.invalidResponse }
        let data = try await authenticatedCampusData(url: url)
        return try JSONDecoder().decode([ClassroomBuilding].self, from: data)
            .filter(\.enabled)
            .sorted { $0.nameZh.localizedStandardCompare($1.nameZh) == .orderedAscending }
    }

    func freeClassrooms(query: FreeClassroomQuery) async throws -> [FreeClassroomRoom] {
        guard !query.buildingIDs.isEmpty else {
            throw CampusClientError.service("请选择至少一栋教学楼")
        }
        guard query.endDate >= query.startDate else {
            throw CampusClientError.service("结束日期不能早于开始日期")
        }

        let url = URL(string: "https://jw.ahu.edu.cn/student/ws/room-borrow/free-list")!
        let units = (query.units.isEmpty ? Array(1...13) : query.units).map(String.init)
        var collected: [FreeClassroomRoom] = []
        for buildingID in query.buildingIDs {
            let payload = FreeClassroomRequest(
                buildingId: String(buildingID),
                campusId: String(query.campusID),
                dateTimeSegmentCmd: .init(
                    endDateTime: FreeClassroomQuery.dateString(query.endDate),
                    startDateTime: FreeClassroomQuery.dateString(query.startDate),
                    units: units
                )
            )
            let data = try await authenticatedCampusData(
                url: url,
                method: "POST",
                body: try JSONEncoder().encode(payload),
                contentType: "application/json"
            )
            collected += try JSONDecoder().decode(FreeClassroomEnvelope.self, from: data).roomList
        }

        return Dictionary(grouping: collected, by: \.id)
            .values
            .compactMap(\.first)
            .sorted {
                ($0.building.nameZh, $0.floor, $0.nameZh)
                    < ($1.building.nameZh, $1.floor, $1.nameZh)
            }
    }

    private func currentWeek() async throws -> Int {
        let data = try await request(path: "/schedule/current-week")
        let object = try JSONSerialization.jsonObject(with: data)
        guard let week = findInt(keys: ["week", "weekIndex", "currentWeek", "teachWeek"], in: object) else {
            throw CampusClientError.invalidResponse
        }
        return week
    }

    func courses(nextSemester: Bool = false) async throws -> [CampusCourse] {
        let data = try await request(path: nextSemester ? "/schedule/next" : "/schedule")
        return try parseCourses(data)
    }

    func scheduleSemesters() async throws -> [CampusScheduleSemester] {
        let data = try await request(path: "/schedule/semesters")
        return try JSONDecoder().decode([CampusScheduleSemester].self, from: data)
            .filter { !$0.id.isEmpty && !$0.name.isEmpty }
    }

    func courses(semesterID: String) async throws -> [CampusCourse] {
        guard Int(semesterID) != nil else { throw CampusClientError.invalidResponse }
        let data = try await request(path: "/schedule", queryItems: [
            URLQueryItem(name: "semester_id", value: semesterID)
        ])
        return try parseCourses(data)
    }

    private func parseCourses(_ data: Data) throws -> [CampusCourse] {
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

    func gradeProfiles() async throws -> [GradeProfile] {
        try AcademicPayload.profiles(await request(path: "/grade/profiles"))
    }

    func gradeReport(profileID: String? = nil) async throws -> GradeReport {
        let query = profileID.map { [URLQueryItem(name: "student_id", value: $0)] } ?? []
        return try AcademicPayload.grades(await request(path: "/grade", queryItems: query))
    }

    func gradeRank(profileID: String) async throws -> GradeRank? {
        try AcademicPayload.rank(await request(path: "/grade/rank", queryItems: [
            URLQueryItem(name: "student_id", value: profileID)
        ]))
    }

    private func grades() async throws -> [CampusGrade] {
        try await gradeReport().grades
    }

    func refreshCardAuthorization() async throws {
        // The token remains inside the local service and is never shown or persisted by Swift.
        _ = try await request(path: "/ycard/refresh_token", method: "POST")
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

    func balance() async throws -> Double {
        let data = try await request(path: "/ycard/balance")
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              number(root["code"]).map(Int.init) == 10_000,
              let result = number(root["object"]) else {
            throw CampusClientError.invalidResponse
        }
        return result
    }

    func cardQRCode() async throws -> String {
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
        queryItems: [URLQueryItem] = [],
        timeout: TimeInterval = 60
    ) async throws -> Data {
        try prepare()
        guard let baseURL, let token else { throw CampusClientError.startup("服务未就绪") }
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else { throw CampusClientError.invalidResponse }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.setValue(token, forHTTPHeaderField: "X-AHUTONG-TOKEN")
        if let json {
            request.httpBody = try JSONSerialization.data(withJSONObject: json)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw CampusClientError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            let code = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["error"] as? String
            switch code {
            case "campus_session_expired": throw CampusClientError.sessionExpired
            case "campus_login_rejected": throw CampusClientError.invalidCredentials
            case "campus_service_unavailable", "campus_service_error":
                throw CampusClientError.service("学校服务暂时不可用，请稍后重试")
            default: throw CampusClientError.service("学校服务请求失败（\(response.statusCode)）")
            }
        }
        return data
    }

    private func authenticatedCampusData(
        url: URL,
        method: String = "GET",
        body: Data? = nil,
        contentType: String? = nil
    ) async throws -> Data {
        let cookieData = try await request(path: "/cookies/flat")
        let cookies = try JSONDecoder().decode([CampusWebCookie].self, from: cookieData)

        var webRequest = URLRequest(url: url)
        webRequest.httpMethod = method
        webRequest.httpBody = body
        webRequest.timeoutInterval = 30
        webRequest.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        webRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType {
            webRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        let cookieHeader = cookies
            .filter { $0.matches(url) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        guard !cookieHeader.isEmpty else { throw CampusClientError.sessionExpired }
        webRequest.setValue(cookieHeader, forHTTPHeaderField: "Cookie")

        let (data, response) = try await session.data(for: webRequest)
        guard let response = response as? HTTPURLResponse else {
            throw CampusClientError.invalidResponse
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw CampusClientError.sessionExpired
        }
        if response.url?.host?.lowercased() != url.host?.lowercased()
            || response.url?.path.lowercased().contains("/cas/login") == true {
            throw CampusClientError.sessionExpired
        }
        guard (200..<300).contains(response.statusCode) else {
            throw CampusClientError.service("教务系统请求失败（\(response.statusCode)）")
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
