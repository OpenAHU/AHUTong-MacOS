import SwiftUI

struct ExamsView: View {
    @EnvironmentObject private var store: AppStore

    private var upcomingExams: [Exam] {
        let today = Calendar.current.startOfDay(for: .now)
        return store.exams.filter { $0.status != "已结束" && $0.date >= today }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "考试安排", subtitle: " ", symbol: "pencil.and.list.clipboard")
                HStack(spacing: 14) {
                    MetricCard(title: "待考试", value: "\(upcomingExams.count) 门", subtitle: " ", symbol: "hourglass", tint: .orange)
                    MetricCard(title: "最近考试", value: upcomingExams.first?.date.formatted(.dateTime.month().day()) ?? "暂无", subtitle: upcomingExams.first?.course ?? "", symbol: "calendar.badge.clock", tint: .purple)
                }
                ForEach(Array(store.exams.enumerated()), id: \.element.id) { index, exam in
                    examCard(exam, index: index)
                }
            }
            .padding(28).frame(maxWidth: 1000, alignment: .leading)
        }
    }

    private func examCard(_ exam: Exam, index: Int) -> some View {
        HStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(exam.date.formatted(.dateTime.day())).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(exam.date.formatted(.dateTime.month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 62)
            .background((index == 0 ? Color.orange : Brand.blue).opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(exam.course).font(.title3.bold())
                HStack(spacing: 18) {
                    Label(exam.timeText ?? exam.date.formatted(.dateTime.weekday(.wide).hour().minute()), systemImage: "clock")
                    Label(exam.place, systemImage: "mappin.and.ellipse")
                    Label("座位 \(exam.seat)", systemImage: "chair.lounge")
                }.font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(exam.status).font(.caption.weight(.medium)).foregroundStyle(.orange)
                .padding(.horizontal, 11).padding(.vertical, 6).background(.orange.opacity(0.1), in: Capsule())
        }
        .cardStyle()
    }
}
