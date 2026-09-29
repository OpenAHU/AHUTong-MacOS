import SwiftUI

struct ExamsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var isUpcomingExpanded = true
    @State private var isPastExpanded = false

    private var upcomingExams: [Exam] {
        let today = Calendar.current.startOfDay(for: .now)
        return store.exams.filter { $0.status != "已结束" && $0.date >= today }
    }

    private var pastExams: [Exam] {
        let today = Calendar.current.startOfDay(for: .now)
        return store.exams.filter { $0.status == "已结束" || $0.date < today }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "考试安排", subtitle: " ", symbol: "pencil.and.list.clipboard")
                HStack(spacing: 14) {
                    MetricCard(title: "待考试", value: "\(upcomingExams.count) 门", subtitle: " ", symbol: "hourglass", tint: .orange)
                    MetricCard(title: "最近考试", value: upcomingExams.first?.date.formatted(.dateTime.month().day()) ?? "暂无", subtitle: upcomingExams.first?.course ?? "", symbol: "calendar.badge.clock", tint: .purple)
                }

                sectionHeader(title: "未开始的考试", count: upcomingExams.count, icon: "clock", iconColor: .orange, isExpanded: $isUpcomingExpanded)
                if isUpcomingExpanded {
                    if upcomingExams.isEmpty {
                        emptyStateView(message: "暂无未开始的考试")
                    } else {
                        ForEach(Array(upcomingExams.enumerated()), id: \.element.id) { index, exam in
                            examCard(exam, index: index)
                        }
                    }
                }

                sectionHeader(title: "已结束的考试", count: pastExams.count, icon: "checkmark.circle", iconColor: .secondary, isExpanded: $isPastExpanded)
                if isPastExpanded {
                    if pastExams.isEmpty {
                        emptyStateView(message: "暂无已结束的考试")
                    } else {
                        ForEach(pastExams) { exam in
                            examCard(exam)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }

    private func sectionHeader(title: String, count: Int, icon: String, iconColor: Color, isExpanded: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                isExpanded.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon).foregroundStyle(iconColor)
                Text(title).font(.headline).foregroundStyle(.primary)
                Text("\(count) 门")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15), in: Capsule())
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded.wrappedValue ? 180 : 0))
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private func emptyStateView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .cardStyle()
    }

    private func examCard(_ exam: Exam, index: Int? = nil) -> some View {
        let isEnded = exam.status == "已结束"
        let dateBackgroundColor = isEnded ? Color.gray : (index == 0 ? Color.orange : Brand.blue)

        return HStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(exam.date.formatted(.dateTime.day())).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(exam.date.formatted(.dateTime.month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 62)
            .background(dateBackgroundColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(exam.course).font(.title3.bold())
                HStack(spacing: 18) {
                    Label(exam.timeText ?? exam.date.formatted(.dateTime.weekday(.wide).hour().minute()), systemImage: "clock")
                    Label(exam.place, systemImage: "mappin.and.ellipse")
                    Label("座位 \(exam.seat)", systemImage: "chair.lounge")
                }.font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(exam.status)
                .font(.caption.weight(.medium))
                .foregroundStyle(isEnded ? Color.secondary : Color.orange)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background((isEnded ? Color.gray : Color.orange).opacity(0.1), in: Capsule())
        }
        .cardStyle()
    }
}
