import Foundation

struct GradeProfile: Identifiable, Equatable, Sendable {
    let id: String
    let trainingType: String
    let department: String
    let major: String

    var displayName: String {
        let parts = [trainingType, major].filter { !$0.isEmpty }
        return parts.isEmpty ? "培养身份 \(id)" : parts.joined(separator: " · ")
    }
}

struct GradeSemester: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
}

struct GradeReport: Sendable {
    let grades: [CampusGrade]
    var semesters: [GradeSemester] {
        var names: [String: String] = [:]
        for grade in grades where !grade.semesterID.isEmpty {
            names[grade.semesterID] = grade.semester.isEmpty ? "学期 \(grade.semesterID)" : grade.semester
        }
        return names.map { GradeSemester(id: $0.key, name: $0.value) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedDescending }
    }
}

struct GradeRank: Sendable {
    struct Term: Identifiable, Sendable {
        let id: String
        let gpa: Double?
        let majorRank: Int?
        let credits: Double?
    }

    let gpa: Double?
    let majorRank: Int?
    let majorHeadCount: Int?
    let credits: Double?
    let updatedAt: String
    let terms: [Term]
}

/// Keep the teaching system's semester and attempt identity instead of flattening
/// every dictionary in the response (which loses semesters and can merge retakes).
enum AcademicPayload {
    static func profiles(_ data: Data) throws -> [GradeProfile] {
        guard let rows = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw CampusClientError.invalidResponse
        }
        var seen = Set<String>()
        return rows.compactMap { row in
            let id = string(row["id"])
            guard !id.isEmpty, seen.insert(id).inserted else { return nil }
            return GradeProfile(id: id, trainingType: string(row["trainingType"]),
                                department: string(row["department"]), major: string(row["major"]))
        }
    }

    static func grades(_ data: Data) throws -> GradeReport {
        let root = try JSONSerialization.jsonObject(with: data)
        var grades: [CampusGrade] = []
        var seen = Set<String>()
        var recognized = false

        func visit(_ value: Any, semesterID: String = "", semesterName: String = "", path: String = "") {
            if let rows = value as? [Any] {
                for (index, row) in rows.enumerated() {
                    visit(row, semesterID: semesterID, semesterName: semesterName, path: "\(path)/\(index)")
                }
                return
            }
            guard let row = value as? [String: Any] else { return }
            if let grouped = row["semesterId2studentGrades"] as? [String: Any] {
                recognized = true
                for key in grouped.keys.sorted() {
                    visit(grouped[key]!, semesterID: key, path: "semester/\(key)")
                }
                return
            }
            let explicitTermID = first(["semesterId", "semesterID"], row)
            let termID = explicitTermID.isEmpty ? semesterID : explicitTermID
            let termName = first(["semesterName", "schoolTerm", "term"], row)
            let resolvedName = termName.isEmpty ? semesterName : termName
            let name = first(["courseName", "courseNameZh", "course", "lessonName"], row)
            let score = first(["gaGrade", "grade", "score"], row)
            if !name.isEmpty && ["gaGrade", "grade", "score", "gradePoint", "gp", "gradeDetail", "detail"].contains(where: { row[$0] != nil }) {
                recognized = true
                let code = first(["courseCode", "lessonCode", "courseNum"], row)
                let attempt = first(["id", "courseGradeId"], row)
                let key = termID.isEmpty ? resolvedName : termID
                let identity = attempt.isEmpty ? "\(code)|\(name)|\(path)" : attempt
                let id = "\(key)|\(identity)"
                guard seen.insert(id).inserted else { return }
                grades.append(CampusGrade(
                    id: id, name: name,
                    credit: number(row["credits"]) ?? number(row["credit"]) ?? 0,
                    score: score,
                    point: number(row["gp"]) ?? number(row["gradePoint"]) ?? 0,
                    type: first(["courseProperty", "courseType", "courseNature"], row),
                    semester: resolvedName, semesterID: key,
                    detail: detailText(first(["gradeDetail", "detail"], row))
                ))
                return
            }
            for key in row.keys.sorted() {
                if row[key] is [String: Any] || row[key] is [Any] {
                    visit(row[key]!, semesterID: termID, semesterName: resolvedName, path: "\(path)/\(key)")
                }
            }
        }

        visit(root)
        guard recognized || (root as? [Any])?.isEmpty == true else {
            throw CampusClientError.invalidResponse
        }
        return GradeReport(grades: grades)
    }

    static func rank(_ data: Data) throws -> GradeRank? {
        guard let row = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CampusClientError.invalidResponse
        }
        let gpa = number(row["gpa"])
        let rank = positiveInt(row["majorRank"])
        let credits = number(row["totalCredits"])
        let terms = (row["gpaSemesterSubs"] as? [[String: Any]] ?? []).compactMap { term -> GradeRank.Term? in
            let id = string(term["semesterId"])
            guard !id.isEmpty else { return nil }
            return GradeRank.Term(id: id, gpa: number(term["gpa"]),
                                  majorRank: positiveInt(term["majorRank"]), credits: number(term["totalCredits"]))
        }
        guard gpa != nil || rank != nil || credits != nil || !terms.isEmpty else { return nil }
        return GradeRank(gpa: gpa, majorRank: rank, majorHeadCount: positiveInt(row["majorHeadCount"]),
                         credits: credits, updatedAt: string(row["updatedDateTimeStr"]), terms: terms)
    }

    static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func detailText(_ value: String) -> String {
        value.replacingOccurrences(of: #"<[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&#160;", with: " ")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = number(value), value > 0, value < Double(Int.max) else { return nil }
        return Int(value)
    }

    private static func string(_ value: Any?) -> String {
        if let value = value as? String { return value.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let value = value as? NSNumber { return value.stringValue }
        if let value = value as? [String: Any] { return first(["nameZh", "name", "value"], value) }
        return ""
    }

    private static func first(_ keys: [String], _ row: [String: Any]) -> String {
        keys.lazy.map { string(row[$0]) }.first { !$0.isEmpty } ?? ""
    }
}
