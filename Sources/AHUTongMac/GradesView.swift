import SwiftUI

struct GradesView: View {
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 20) {
                PageHeader(title: "成绩查询", subtitle: " ", symbol: "chart.bar.doc.horizontal.fill")
                HStack(spacing: 14) {
                    MetricCard(title: "加权平均分", value: store.decimal(store.averageScore, digits: 1), subtitle: " ", symbol: "number.circle.fill", tint: .blue)
                    MetricCard(title: "平均绩点", value: store.decimal(store.gpa), subtitle: " ", symbol: "graduationcap.fill", tint: .purple)
                    MetricCard(title: "已获学分", value: store.decimal(store.grades.reduce(0) { $0 + $1.credit }, digits: 1), subtitle: " ", symbol: "checkmark.seal.fill", tint: .green)
                }
            }.padding(26)

            Table(store.grades.sorted { $0.score > $1.score }) {
                TableColumn("课程") { grade in Text(grade.course).fontWeight(.medium) }
                TableColumn("性质") { grade in Text(grade.type).foregroundStyle(.secondary) }.width(80)
                TableColumn("学分") { grade in Text(grade.credit, format: .number.precision(.fractionLength(1))).monospacedDigit() }.width(75)
                TableColumn("成绩") { grade in
                    Text(grade.scoreText ?? grade.score.formatted(.number.precision(.fractionLength(0))))
                        .fontWeight(.semibold).foregroundStyle(grade.score >= 90 ? .green : .primary)
                }.width(80)
                TableColumn("绩点") { grade in Text(grade.point, format: .number.precision(.fractionLength(1))).monospacedDigit() }.width(75)
            }
            .padding(.horizontal, 26).padding(.bottom, 26)
        }
    }
}
