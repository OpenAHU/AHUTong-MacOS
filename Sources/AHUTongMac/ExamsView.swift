import SwiftUI

struct ExamsView: View {
    @EnvironmentObject private var store: AppStore
    @State private var showsFinishedExams = false
    @State private var finishedExamPage = 0

    private let finishedExamPageSize = 5

    private var upcomingExams: [Exam] {
        store.exams
            .filter { $0.status != "已结束" }
            .sorted { $0.date < $1.date }
    }

    private var finishedExams: [Exam] {
        store.exams
            .filter { $0.status == "已结束" }
            .sorted { $0.date > $1.date }
    }

    private var finishedExamPageCount: Int {
        max(1, (finishedExams.count + finishedExamPageSize - 1) / finishedExamPageSize)
    }

    private var safeFinishedExamPage: Int {
        min(finishedExamPage, finishedExamPageCount - 1)
    }

    private var visibleFinishedExams: [Exam] {
        let start = safeFinishedExamPage * finishedExamPageSize
        guard start < finishedExams.count else { return [] }
        let end = min(start + finishedExamPageSize, finishedExams.count)
        return Array(finishedExams[start..<end])
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "考试安排", subtitle: " ", symbol: "pencil.and.list.clipboard")
                HStack(spacing: 14) {
                    MetricCard(title: "未开始", value: "\(upcomingExams.count) 门", subtitle: " ", symbol: "hourglass", tint: .orange)
                    MetricCard(title: "最近考试", value: upcomingExams.first?.date.formatted(.dateTime.month().day()) ?? "暂无", subtitle: upcomingExams.first?.course ?? "", symbol: "calendar.badge.clock", tint: .purple)
                }

                examSectionHeader(
                    title: "未开始的考试",
                    count: upcomingExams.count,
                    symbol: "clock.badge.checkmark",
                    tint: .orange
                )

                if upcomingExams.isEmpty {
                    ContentUnavailableView("暂无未开始的考试", systemImage: "checkmark.circle")
                        .frame(maxWidth: .infinity)
                        .cardStyle()
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(upcomingExams.enumerated()), id: \.element.id) { index, exam in
                            examCard(exam, index: index, isFinished: false)
                        }
                    }
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showsFinishedExams.toggle()
                    }
                } label: {
                    HStack(spacing: 10) {
                        examSectionHeader(
                            title: "已结束的考试",
                            count: finishedExams.count,
                            symbol: "checkmark.circle",
                            tint: .secondary
                        )
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                            .rotationEffect(.degrees(showsFinishedExams ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if showsFinishedExams {
                    if finishedExams.isEmpty {
                        ContentUnavailableView("暂无已结束的考试", systemImage: "calendar.badge.checkmark")
                            .frame(maxWidth: .infinity)
                            .cardStyle()
                    } else {
                        LazyVStack(spacing: 12) {
                            ForEach(Array(visibleFinishedExams.enumerated()), id: \.element.id) { index, exam in
                                examCard(exam, index: index, isFinished: true)
                            }
                        }

                        if finishedExamPageCount > 1 {
                            finishedExamPagination
                        }
                    }
                }
            }
            .padding(28).frame(maxWidth: 1000, alignment: .leading)
        }
        .onChange(of: finishedExamPageCount) { _, _ in
            finishedExamPage = 0
        }
    }

    private var finishedExamPagination: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    finishedExamPage = max(0, safeFinishedExamPage - 1)
                }
            } label: {
                Label("上一页", systemImage: "chevron.left")
            }
            .disabled(safeFinishedExamPage == 0)

            Text("第 \(safeFinishedExamPage + 1) / \(finishedExamPageCount) 页")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    finishedExamPage = min(finishedExamPageCount - 1, safeFinishedExamPage + 1)
                }
            } label: {
                Label("下一页", systemImage: "chevron.right")
                    .labelStyle(.titleAndIcon)
            }
            .disabled(safeFinishedExamPage >= finishedExamPageCount - 1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func examSectionHeader(
        title: String,
        count: Int,
        symbol: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
            Text(title)
                .font(.headline)
            Text("\(count) 门")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
        }
    }

    private func examCard(_ exam: Exam, index: Int, isFinished: Bool) -> some View {
        let tint: Color = isFinished ? .gray : (index == 0 ? .orange : Brand.blue)

        return HStack(spacing: 18) {
            VStack(spacing: 2) {
                Text(exam.date.formatted(.dateTime.day())).font(.system(size: 22, weight: .bold, design: .rounded))
                Text(exam.date.formatted(.dateTime.month(.abbreviated))).font(.caption).foregroundStyle(.secondary)
            }
            .frame(width: 58, height: 62)
            .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 7) {
                Text(exam.course).font(.title3.bold())
                HStack(spacing: 18) {
                    Label(exam.timeText ?? exam.date.formatted(.dateTime.weekday(.wide).hour().minute()), systemImage: "clock")
                    Label(exam.place, systemImage: "mappin.and.ellipse")
                    Label("座位 \(exam.seat)", systemImage: "chair.lounge")
                }.font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text(isFinished ? "已结束" : "未开始")
                .font(.caption.weight(.medium))
                .foregroundStyle(tint)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(tint.opacity(0.1), in: Capsule())
        }
        .cardStyle()
        .opacity(isFinished ? 0.78 : 1)
    }
}
