import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var store: AppStore
    @StateObject private var model = GradePageModel()
    @State private var refreshRevision = 0

    private var loadKey: String {
        "\(store.studentID)|\(model.profilesReady)|\(model.selectedProfileID)|\(store.lastUpdated.timeIntervalSince1970)|\(refreshRevision)"
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    PageHeader(title: "成绩查询", subtitle: "按培养身份与学期查看成绩和教务绩点排名", symbol: "chart.bar.doc.horizontal.fill")
                    Button { refreshRevision += 1 } label: {
                        Label("刷新成绩", systemImage: "arrow.clockwise")
                    }.disabled(model.isLoading || !model.profilesReady)
                }
                filters
                HStack(spacing: 14) {
                    MetricCard(title: "加权平均分", value: format(model.averageScore, digits: 1), subtitle: "所选学期 · 数字成绩", symbol: "number.circle.fill", tint: .blue)
                    MetricCard(title: "教务绩点", value: format(model.displayedGPA), subtitle: model.isLoadingRank ? "正在读取" : "教务系统统计", symbol: "graduationcap.fill", tint: .purple)
                    MetricCard(title: "教务已修学分", value: format(model.displayedCredits, digits: 1), subtitle: "以教务公布为准", symbol: "checkmark.seal.fill", tint: .green)
                }
                rankSummary
                if let message = model.profileError {
                    HStack {
                        Text(message).font(.caption).foregroundStyle(.orange)
                        Button("重试身份查询") { Task { await model.loadProfiles(using: store) } }
                    }
                }
                if let error = model.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                }
            }.padding(26)

            if !model.profilesReady || model.isLoading {
                Spacer()
                ProgressView("正在读取成绩…")
                Spacer()
            } else if model.visibleGrades.isEmpty {
                ContentUnavailableView(
                    model.error == nil ? "暂无符合条件的成绩" : "成绩读取失败",
                    systemImage: "chart.bar.doc.horizontal",
                    description: Text(model.error == nil ? "可切换培养身份、学期或清除搜索条件" : "请点击刷新成绩重试")
                ).frame(maxHeight: .infinity)
            } else {
                Table(model.visibleGrades) {
                    TableColumn("课程") { grade in Text(grade.name).fontWeight(.medium) }
                    TableColumn("学期") { grade in Text(grade.semester.isEmpty ? "学期 \(grade.semesterID)" : grade.semester).foregroundStyle(.secondary) }
                        .width(min: 130, ideal: 180)
                    TableColumn("性质") { grade in Text(grade.type.isEmpty ? "—" : grade.type).foregroundStyle(.secondary) }.width(85)
                    TableColumn("学分") { grade in Text(grade.credit, format: .number.precision(.fractionLength(1))).monospacedDigit() }.width(65)
                    TableColumn("成绩") { grade in
                        Text(grade.score.isEmpty ? (grade.detail.isEmpty ? "—" : grade.detail) : grade.score).fontWeight(.semibold)
                            .foregroundStyle((AcademicPayload.number(grade.score) ?? 0) >= 90 ? .green : .primary)
                            .help(grade.detail.isEmpty ? grade.score : grade.detail)
                    }.width(min: 80, ideal: 115, max: 200)
                    TableColumn("绩点") { grade in Text(grade.point, format: .number.precision(.fractionLength(2))).monospacedDigit() }.width(65)
                }
                .padding(.horizontal, 26).padding(.bottom, 26)
            }
        }
        .task(id: store.studentID) { await model.loadProfiles(using: store) }
        .task(id: loadKey) {
            guard model.profilesReady else { return }
            await model.loadGrades(using: store)
        }
        .task(id: loadKey + "|rank") {
            guard model.profilesReady else { return }
            await model.loadRank(using: store)
        }
    }

    private var filters: some View {
        HStack(spacing: 14) {
            if !model.profiles.isEmpty {
                Picker("培养身份", selection: $model.selectedProfileID) {
                    ForEach(model.profiles) { profile in Text(profile.displayName).tag(profile.id) }
                }.frame(maxWidth: 300)
            }
            Picker("学期", selection: $model.selectedSemesterID) {
                Text("全部学期").tag("")
                ForEach(model.semesters) { semester in Text(semester.name).tag(semester.id) }
            }.frame(maxWidth: 280)
            TextField("搜索课程", text: $model.searchText)
                .textFieldStyle(.roundedBorder).frame(minWidth: 180)
        }
    }

    private var rankSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("专业排名", systemImage: "chart.bar.xaxis")
                if model.isLoadingRank {
                    ProgressView().controlSize(.small)
                } else if let rank = model.displayedRank {
                    Text("第 \(rank) 名").fontWeight(.semibold)
                    if model.selectedSemesterID.isEmpty, let count = model.rank?.majorHeadCount {
                        Text("／\(count) 人").foregroundStyle(.secondary)
                    }
                } else {
                    Text("教务系统暂未提供").foregroundStyle(.secondary)
                }
                Spacer()
                if let updated = model.rank?.updatedAt, !updated.isEmpty {
                    Text("教务更新于 \(updated)").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = model.rankError { Text(error).font(.caption).foregroundStyle(.orange) }
        }.font(.subheadline)
    }

    private func format(_ value: Double?, digits: Int = 2) -> String {
        value.map { store.decimal($0, digits: digits) } ?? "—"
    }
}
