import Foundation
import SwiftUI

@MainActor
final class GradePageModel: ObservableObject {
    @Published private(set) var profiles: [GradeProfile] = []
    @Published var selectedProfileID = ""
    @Published var selectedSemesterID = ""
    @Published var searchText = ""
    @Published private(set) var report: GradeReport?
    @Published private(set) var rank: GradeRank?
    @Published private(set) var profilesReady = false
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingRank = false
    @Published private(set) var error: String?
    @Published private(set) var profileError: String?
    @Published private(set) var rankError: String?
    private var profileRevision = UUID()
    private var reportRevision = UUID()
    private var rankRevision = UUID()

    var semesters: [GradeSemester] { report?.semesters ?? [] }
    var semesterGrades: [CampusGrade] {
        (report?.grades ?? []).filter { selectedSemesterID.isEmpty || $0.semesterID == selectedSemesterID }
    }
    var visibleGrades: [CampusGrade] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return semesterGrades.filter {
            query.isEmpty || [$0.name, $0.type, $0.semester].contains { $0.localizedStandardContains(query) }
        }.sorted { lhs, rhs in
            let left = AcademicPayload.number(lhs.score) ?? -1
            let right = AcademicPayload.number(rhs.score) ?? -1
            return left == right ? lhs.id < rhs.id : left > right
        }
    }
    var averageScore: Double? {
        let values = semesterGrades.compactMap { grade -> (Double, Double)? in
            guard let score = AcademicPayload.number(grade.score), grade.credit > 0 else { return nil }
            return (score, grade.credit)
        }
        let weight = values.reduce(0) { $0 + $1.1 }
        return weight > 0 ? values.reduce(0) { $0 + $1.0 * $1.1 } / weight : nil
    }
    var displayedGPA: Double? {
        selectedSemesterID.isEmpty ? rank?.gpa : rank?.terms.first { $0.id == selectedSemesterID }?.gpa
    }
    var displayedRank: Int? {
        selectedSemesterID.isEmpty ? rank?.majorRank : rank?.terms.first { $0.id == selectedSemesterID }?.majorRank
    }
    var displayedCredits: Double? {
        selectedSemesterID.isEmpty ? rank?.credits : rank?.terms.first { $0.id == selectedSemesterID }?.credits
    }

    func loadProfiles(using store: AppStore) async {
        let revision = UUID()
        profileRevision = revision
        profilesReady = false
        profiles = []
        report = nil
        rank = nil
        selectedProfileID = ""
        selectedSemesterID = ""
        searchText = ""
        profileError = nil
        do {
            let values = try await store.performCampusRequest { try await $0.gradeProfiles() }
            guard !Task.isCancelled, profileRevision == revision else { return }
            profiles = values
            selectedProfileID = values.first?.id ?? ""
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, profileRevision == revision else { return }
            profileError = "培养身份读取失败：\(error.localizedDescription)。当前显示默认身份成绩。"
        }
        profilesReady = true
    }

    func loadGrades(using store: AppStore) async {
        let revision = UUID()
        reportRevision = revision
        let profileID = selectedProfileID
        report = nil
        error = nil
        isLoading = true
        defer { if reportRevision == revision { isLoading = false } }
        do {
            let value = try await store.performCampusRequest {
                try await $0.gradeReport(profileID: profileID.isEmpty ? nil : profileID)
            }
            guard !Task.isCancelled, reportRevision == revision else { return }
            report = value
            if !semesters.contains(where: { $0.id == selectedSemesterID }) { selectedSemesterID = "" }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, reportRevision == revision else { return }
            self.error = error.localizedDescription
        }
    }

    func loadRank(using store: AppStore) async {
        let revision = UUID()
        rankRevision = revision
        let profileID = selectedProfileID
        rank = nil
        rankError = nil
        isLoadingRank = false
        guard !profileID.isEmpty else { return }
        isLoadingRank = true
        defer { if rankRevision == revision { isLoadingRank = false } }
        do {
            let value = try await store.performCampusRequest { try await $0.gradeRank(profileID: profileID) }
            guard !Task.isCancelled, rankRevision == revision else { return }
            rank = value
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, rankRevision == revision else { return }
            rankError = "排名暂不可用：\(error.localizedDescription)"
        }
    }
}
