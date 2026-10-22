import Foundation
import Testing
@testable import AHUTongMac

struct AcademicFeaturesTests {
    @Test("成绩保留所属学期、非数字成绩及重修记录")
    func preservesSemestersAndAttempts() throws {
        let data = Data(#"""
        {"semesterId2studentGrades": {
          "111": [
            {"id": 1, "courseCode":"A", "courseName":"课程一", "gaGrade":"0", "gp":0, "credits":2},
            {"id": 2, "courseCode":"A", "courseName":"课程一", "gaGrade":"85", "gp":3.5, "credits":2},
            {"id": 3, "courseName":"体育", "gaGrade":"优秀", "gp":4, "credits":1}
          ],
          "222": [{"id": 1, "courseCode":"A", "courseName":"课程一", "gaGrade":"90", "gp":4, "credits":2}]
        }}
        """#.utf8)
        let report = try AcademicPayload.grades(data)
        #expect(report.grades.count == 4)
        #expect(Set(report.grades.map(\.id)).count == 4)
        #expect(report.semesters.count == 2)
        #expect(report.grades.filter { $0.semesterID == "111" }.count == 3)
        #expect(report.grades.contains { $0.score == "优秀" })
        #expect(report.grades.contains { $0.score == "0" })
    }

    @Test("空成绩有效，但错误响应不能当成空成绩")
    func distinguishesEmptyAndMalformedPayloads() throws {
        #expect(try AcademicPayload.grades(Data(#"{"semesterId2studentGrades":{}}"#.utf8)).grades.isEmpty)
        #expect(throws: CampusClientError.self) {
            try AcademicPayload.grades(Data(#"{"error":"unexpected"}"#.utf8))
        }
    }

    @Test("未评教成绩保留教务提示，不执行响应中的 HTML")
    func preservesRestrictedGradeDetails() throws {
        let report = try AcademicPayload.grades(Data(#"{"items":[{"courseName":"课程","gradeDetail":"<a href='/student-summation'>请先完成评教&nbsp;后查看</a>","semesterID":111,"semesterName":"2025-2026-1"}]}"#.utf8))
        let grade = try #require(report.grades.first)
        #expect(grade.score.isEmpty)
        #expect(grade.semesterID == "111")
        #expect(grade.detail == "请先完成评教 后查看")
    }

    @Test("排名保留缺失值，并按真实学期 ID 关联")
    func parsesRankWithoutInventingZeros() throws {
        let data = Data(#"""
        {"gpa":"3.67","majorRank":5,"majorHeadCount":80,"totalCredits":42,
         "gpaSemesterSubs":[{"semesterId":111,"gpa":0,"majorRank":0,"totalCredits":0}]}
        """#.utf8)
        let parsed = try AcademicPayload.rank(data)
        let rank = try #require(parsed)
        #expect(rank.gpa == 3.67)
        #expect(rank.majorRank == 5)
        #expect(rank.terms.first?.id == "111")
        #expect(rank.terms.first?.gpa == 0)
        #expect(rank.terms.first?.majorRank == nil)
        #expect(try AcademicPayload.rank(Data("{}".utf8)) == nil)
        #expect(try AcademicPayload.rank(Data(#"{"totalCredits":0}"#.utf8))?.credits == 0)
    }

    @Test("SDK 请求携带本地 Token、培养身份查询参数及正确 HTTP 方法")
    func usesExistingRustRoutes() async throws {
        let fixture = makeFixture([
            "/grade/profiles": .init(body: #"[{"id":123,"trainingType":"主修","major":"哲学"}]"#),
            "/grade": .init(body: #"{"semesterId2studentGrades":{}}"#),
            "/grade/rank": .init(body: #"{"gpa":3.5,"majorRank":4}"#),
            "/schedule/semesters": .init(body: #"[{"id":120,"name":"2025-2026-2","current":true},{"id":"100","name":"2024-2025-2","current":false}]"#),
            "/schedule": .init(body: #"[{"name":"历史课程","className":"历史班","teacher":"教师","location":"教室","weekday":"2","startTime":"1","length":"2","weekIndexes":[1,2],"courseId":"H"}]"#),
            "/schedule/next": .init(body: #"[{"name":"测试课程","className":"测试班","teacher":"教师","location":"教室","weekday":"1","startTime":"3","length":"2","weekIndexes":[2,1,2],"courseId":"C"}]"#),
            "/ycard/refresh_token": .init(body: #"{"access_token":"fixture-only"}"#)
        ])
        let profiles = try await fixture.client.gradeProfiles()
        #expect(profiles.first?.id == "123")
        #expect(profiles.first?.displayName == "主修 · 哲学")
        _ = try await fixture.client.gradeReport(profileID: "123")
        _ = try await fixture.client.gradeRank(profileID: "123")
        let semesters = try await fixture.client.scheduleSemesters()
        #expect(semesters.map(\.id) == ["120", "100"])
        #expect(semesters.first?.current == true)
        let history = try await fixture.client.courses(semesterID: "100")
        #expect(history.first?.name == "历史课程")
        let courses = try await fixture.client.courses(nextSemester: true)
        #expect(courses.first?.weeks == [1, 2])
        #expect(courses.first?.className == "测试班")
        try await fixture.client.refreshCardAuthorization()
        let requests = AcademicFixtureProtocol.state.requests(for: fixture.host)
        #expect(requests.count == 7)
        #expect(requests.allSatisfy { $0.value(forHTTPHeaderField: "X-AHUTONG-TOKEN") == "fixture-token" })
        let gradeRequest = try #require(requests.first { $0.url?.path == "/grade" })
        #expect(URLComponents(url: gradeRequest.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "123")
        let scheduleRequest = try #require(requests.first { $0.url?.path == "/schedule" })
        #expect(URLComponents(url: scheduleRequest.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value == "100")
        #expect(requests.last?.httpMethod == "POST")
    }

    @Test("过期会话、凭据拒绝和本地服务拒绝访问分别处理")
    func distinguishesAuthenticationFailures() async throws {
        let expired = makeFixture(["/grade": .init(code: 401, body: #"{"error":"campus_session_expired"}"#)])
        do {
            _ = try await expired.client.gradeReport()
            Issue.record("Expected session expiration")
        } catch CampusClientError.sessionExpired { }
        let rejected = makeFixture(["/grade": .init(code: 401, body: #"{"error":"campus_login_rejected"}"#)])
        do {
            _ = try await rejected.client.gradeReport()
            Issue.record("Expected credential rejection")
        } catch CampusClientError.invalidCredentials { }
        let local = makeFixture(["/grade": .init(code: 401, body: "")])
        do {
            _ = try await local.client.gradeReport()
            Issue.record("Expected local authorization failure")
        } catch CampusClientError.service { }
    }

    @Test("快照用明确错误标记会话失效，其余接口成功数据仍保留")
    func snapshotRetainsTypedSessionFailure() async {
        let fixture = makeFixture([
            "/schedule/current-week": .init(body: #"{"week":4}"#),
            "/schedule": .init(body: "[]"),
            "/grade": .init(code: 401, body: #"{"error":"campus_session_expired"}"#),
            "/exam": .init(body: "[]"),
            "/ycard/balance": .init(body: #"{"code":10000,"object":12.34}"#),
            "/ycard/qrcode": .init(body: #"{"code":10000,"object":"fixture-only"}"#)
        ])
        let snapshot = await fixture.client.loadSnapshot()
        #expect(snapshot.sessionExpired)
        #expect(snapshot.currentWeek == 4)
        #expect(snapshot.balance == 12.34)
        #expect(snapshot.warnings.count == 1)
    }

    private func makeFixture(_ replies: [String: AcademicFixtureReply]) -> (client: CampusCoreClient, host: String) {
        let host = UUID().uuidString.lowercased() + ".invalid"
        AcademicFixtureProtocol.state.register(host: host, replies: replies)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AcademicFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        return (CampusCoreClient(session: session, baseURL: URL(string: "https://\(host)")!, token: "fixture-token"), host)
    }
}

private struct AcademicFixtureReply: Sendable {
    var code = 200
    let body: String
}

private final class AcademicFixtureState: @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [String: [String: AcademicFixtureReply]] = [:]
    private var captured: [String: [URLRequest]] = [:]

    func register(host: String, replies: [String: AcademicFixtureReply]) {
        lock.lock()
        defer { lock.unlock() }
        self.replies[host] = replies
    }

    func reply(for request: URLRequest) -> AcademicFixtureReply {
        lock.lock()
        defer { lock.unlock() }
        let host = request.url!.host!
        captured[host, default: []].append(request)
        return replies[host]?[request.url!.path] ?? .init(code: 404, body: "{}")
    }

    func requests(for host: String) -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return captured[host] ?? []
    }
}

private final class AcademicFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let state = AcademicFixtureState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let reply = Self.state.reply(for: request)
        let response = HTTPURLResponse(url: request.url!, statusCode: reply.code, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(reply.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
