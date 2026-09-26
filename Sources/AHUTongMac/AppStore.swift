import Foundation
import SwiftUI

enum SessionPhase: Equatable {
    case signedOut
    case signingIn
    case authenticated
}

@MainActor
final class AppStore: ObservableObject {
    @Published var selection: AppSection? = .overview
    @Published var selectedWeek = 1
    @Published private(set) var currentWeek = 1
    @Published var balance = 0.0
    @Published var showMapNotice = false
    @Published var isRefreshing = false
    @Published var lastUpdated = Date.now
    @Published var sessionPhase: SessionPhase = .signedOut
    @Published var loginStudentID = UserDefaults.standard.string(forKey: "lastStudentID") ?? ""
    @Published var loginPassword = ""
    @Published var loginError: String?
    @Published var dataWarnings: [String] = []
    @Published var cardQRCode: String?
    @Published var courses: [Course] = []
    @Published var grades: [Grade] = []
    @Published var exams: [Exam] = []
    @Published var studentName = "安大学生"
    @Published var studentID = ""
    @Published var showProfileSettings = false
    @Published private(set) var localProfileName = ""
    @Published private(set) var profileAvatarData: Data?
    @Published private(set) var courseNotificationStatus = "登录后将根据课表自动安排"
    @AppStorage("rememberCredentials") var rememberCredentials = true

    let totalWeeks = 20
    let totalPeriods = 13

    private let campusClient: CampusCoreClient
    private let keychain: KeychainVault
    private let notificationScheduler: CourseNotificationScheduler

    let transactions: [CardTransaction] = []
    let services: [CampusService] = [
        CampusService(title: "安徽大学官网", subtitle: "学校通知与新闻", symbol: "building.columns.fill", color: .blue, url: URL(string: "https://www.ahu.edu.cn")),
        CampusService(title: "安徽大学教务处", subtitle: "教学通知与教务信息", symbol: "graduationcap.fill", color: .orange, url: URL(string: "https://jwc.ahu.edu.cn/")),
        CampusService(title: "超星学习通", subtitle: "在线课程与学习资源", symbol: "books.vertical.fill", color: .green, url: URL(string: "https://www.chaoxing.com/")),
        CampusService(title: "安大通项目", subtitle: "查看开源代码", symbol: "chevron.left.forwardslash.chevron.right", color: .purple, url: URL(string: "https://github.com/OpenAHU/AHUTong")),
        CampusService(title: "智慧安大", subtitle: "统一身份认证与校园服务", symbol: "person.badge.key.fill", color: .teal, url: URL(string: "https://one.ahu.edu.cn")),
        CampusService(title: "反馈建议", subtitle: "前往项目 Issues", symbol: "bubble.left.and.bubble.right.fill", color: .pink, url: URL(string: "https://github.com/OpenAHU/AHUTong/issues"))
    ]

    init(
        campusClient: CampusCoreClient = .shared,
        keychain: KeychainVault = .shared,
        notificationScheduler: CourseNotificationScheduler = .shared
    ) {
        self.campusClient = campusClient
        self.keychain = keychain
        self.notificationScheduler = notificationScheduler
        if let lastAccountID = UserDefaults.standard.string(forKey: "lastStudentID") {
            try? LocalProfileStorage.migrateLegacyProfile(to: lastAccountID)
        }
    }

    var gpa: Double {
        let total = grades.reduce(0) { $0 + $1.point * $1.credit }
        let credits = grades.reduce(0) { $0 + $1.credit }
        return credits == 0 ? 0 : total / credits
    }

    var averageScore: Double {
        let numeric = grades.filter { $0.score > 0 }
        let credits = numeric.reduce(0) { $0 + $1.credit }
        return credits == 0 ? 0 : numeric.reduce(0) { $0 + $1.score * $1.credit } / credits
    }

    var rememberBinding: Binding<Bool> {
        Binding(get: { self.rememberCredentials }, set: { self.rememberCredentials = $0 })
    }

    var profileDisplayName: String {
        let localName = localProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return localName.isEmpty ? studentName : localName
    }

    func updateLocalProfile(displayName: String, avatarData: Data?) throws {
        let normalizedName = String(
            displayName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(32)
        )
        try LocalProfileStorage.saveProfile(
            displayName: normalizedName,
            avatarData: avatarData,
            for: studentID
        )
        localProfileName = normalizedName
        profileAvatarData = avatarData
    }

    func decimal(_ value: Double, digits: Int = 2) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    func loadSavedCredentials() async {
        do {
            if let saved = try await keychain.load() {
                loginStudentID = saved.studentID
                loginPassword = saved.password
            }
        } catch {
            loginError = error.localizedDescription
        }
    }

    func prepareCampusService() async {
        do {
            try await campusClient.prepare()
        } catch {
            loginError = error.localizedDescription
        }
    }

    func login() {
        guard sessionPhase != .signingIn else { return }
        let normalizedID = loginStudentID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalizedID.isEmpty, !loginPassword.isEmpty else {
            loginError = "请填写智慧安大账号和密码"
            return
        }
        sessionPhase = .signingIn
        loginError = nil
        Task {
            do {
                let password = loginPassword
                let user = try await campusClient.login(studentID: normalizedID, password: password)
                studentName = user.name
                studentID = user.studentID
                loadLocalProfile(for: user.studentID)
                loginStudentID = user.studentID
                UserDefaults.standard.set(user.studentID, forKey: "lastStudentID")
                if rememberCredentials {
                    try await keychain.save(StoredCredentials(studentID: user.studentID, password: password))
                } else {
                    try await keychain.clear()
                }
                loginPassword = ""
                sessionPhase = .authenticated
                await refreshData()
            } catch {
                sessionPhase = .signedOut
                loginError = error.localizedDescription
            }
        }
    }

    func refresh() {
        guard sessionPhase == .authenticated, !isRefreshing else { return }
        Task { await refreshData() }
    }

    func signOut() {
        Task {
            try? await keychain.clear()
            courses = []
            grades = []
            exams = []
            balance = 0
            cardQRCode = nil
            dataWarnings = []
            studentName = "安大学生"
            studentID = ""
            localProfileName = ""
            profileAvatarData = nil
            loginPassword = ""
            selectedWeek = 1
            currentWeek = 1
            courseNotificationStatus = "登录后将根据课表自动安排"
            sessionPhase = .signedOut
            await notificationScheduler.removePendingCourseReminders()
        }
    }

    private func loadLocalProfile(for accountID: String) {
        let profile = LocalProfileStorage.loadProfile(for: accountID)
        localProfileName = profile.displayName
        profileAvatarData = profile.avatarData
    }

    private func refreshData() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        let snapshot = await campusClient.loadSnapshot()
        let shouldFollowCurrentWeek = courses.isEmpty || selectedWeek == currentWeek
        if let week = snapshot.currentWeek, (1...totalWeeks).contains(week) {
            currentWeek = week
            if shouldFollowCurrentWeek { selectedWeek = week }
        }
        courses = mapCourses(snapshot.courses)
        grades = snapshot.grades.map(mapGrade)
        let today = Calendar.current.startOfDay(for: .now)
        exams = snapshot.exams.map(mapExam).sorted { lhs, rhs in
            let lhsUpcoming = lhs.status != "已结束" && lhs.date >= today
            let rhsUpcoming = rhs.status != "已结束" && rhs.date >= today
            if lhsUpcoming != rhsUpcoming { return lhsUpcoming }
            return lhsUpcoming ? lhs.date < rhs.date : lhs.date > rhs.date
        }
        if let liveBalance = snapshot.balance { balance = liveBalance }
        cardQRCode = snapshot.cardQRCode
        dataWarnings = snapshot.warnings
        lastUpdated = .now
        isRefreshing = false

        let courseLoadFailed = snapshot.warnings.contains { $0.hasPrefix("课表：") }
        if courseLoadFailed || snapshot.currentWeek == nil {
            courseNotificationStatus = "课表或教学周获取失败，已保留原有提醒"
        } else {
            let result = await notificationScheduler.replaceScheduledReminders(
                courses: courses,
                currentWeek: currentWeek
            )
            switch result {
            case let .scheduled(count):
                courseNotificationStatus = count == 0
                    ? "当前没有可安排的后续课程"
                    : "已安排最近 \(count) 次上课提醒"
            case .denied:
                courseNotificationStatus = "通知权限未开启，请前往系统设置允许通知"
            case let .failed(message):
                courseNotificationStatus = "通知安排失败：\(message)"
            }
        }
    }

    private func mapCourses(_ live: [CampusCourse]) -> [Course] {
        let colors: [Color] = [.blue, .purple, .orange, .green, .pink, .indigo, .teal, .mint]
        return live.map { item in
            let colorIndex = item.name.unicodeScalars.reduce(0) { ($0 + Int($1.value)) % colors.count }
            return Course(
                id: item.id,
                name: item.name,
                className: item.className,
                teacher: item.teacher,
                room: item.location.isEmpty ? "地点待公布" : item.location,
                weekday: item.weekday,
                start: item.startPeriod,
                length: item.duration,
                weekIndexes: item.weeks,
                color: colors[colorIndex]
            )
        }
        .sorted {
            ($0.weekday, $0.start, $0.name, $0.weeks, $0.teacher) <
            ($1.weekday, $1.start, $1.name, $1.weeks, $1.teacher)
        }
    }

    private func mapGrade(_ item: CampusGrade) -> Grade {
        let normalized = item.score.replacingOccurrences(of: "分", with: "")
        return Grade(
            course: item.name,
            credit: item.credit,
            score: Double(normalized) ?? 0,
            type: item.type.isEmpty ? "—" : item.type,
            reportedPoint: item.point,
            scoreText: item.score.isEmpty ? "—" : item.score
        )
    }

    private func mapExam(_ item: CampusExamItem) -> Exam {
        Exam(
            course: item.course,
            date: parseExamDate(item.time) ?? .now,
            place: item.location.isEmpty ? "待公布" : item.location,
            seat: item.seat.isEmpty ? "—" : item.seat,
            status: item.finished ? "已结束" : "待考试",
            timeText: item.time
        )
    }

    private func parseExamDate(_ value: String) -> Date? {
        let prefix = String(value.prefix(16))
        for format in ["yyyy-MM-dd HH:mm", "yyyy/MM/dd HH:mm", "yyyy年MM月dd日 HH:mm"] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "zh_CN")
            formatter.dateFormat = format
            if let date = formatter.date(from: prefix) { return date }
        }
        return nil
    }
}
