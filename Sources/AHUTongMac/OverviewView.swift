import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var store: AppStore

    var todayCourses: [Course] {
        let weekday = Calendar.current.component(.weekday, from: .now)
        let mondayIndex = weekday == 1 ? 7 : weekday - 1
        return store.courses.filter {
            $0.weekday == mondayIndex && $0.isActive(in: store.currentWeek)
        }
    }

    private var currentWeekCourses: [Course] {
        store.courses.filter { $0.isActive(in: store.currentWeek) }
    }

    private var nextExam: Exam? {
        let today = Calendar.current.startOfDay(for: .now)
        return store.exams
            .filter { $0.status != "已结束" && $0.date >= today }
            .min { $0.date < $1.date }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                greeting

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 4), spacing: 14) {
                    MetricCard(title: "校园卡余额", value: "¥\(store.decimal(store.balance))", subtitle: "实时数据", symbol: "creditcard.fill", tint: .blue)
                    MetricCard(title: "本周课程", value: "\(currentWeekCourses.count) 节", subtitle: "第 \(store.currentWeek) 教学周", symbol: "calendar", tint: .purple)
                    MetricCard(title: "平均成绩", value: store.decimal(store.averageScore, digits: 1), subtitle: "已出 \(store.grades.count) 门", symbol: "chart.bar.fill", tint: .orange)
                    MetricCard(title: "平均绩点", value: store.decimal(store.gpa), subtitle: "教务系统绩点", symbol: "graduationcap.fill", tint: .green)
                }

                HStack(alignment: .top, spacing: 16) {
                    todayCard
                    nextExamCard
                }

                quickActions
            }
            .padding(28)
            .frame(maxWidth: 1300, alignment: .leading)
        }
    }

    private var greeting: some View {
        HStack {
            VStack(alignment: .leading, spacing: 7) {
                Text("你好，\(store.profileDisplayName)")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                Text("至诚至坚，博学笃行 · 第 \(store.currentWeek) 教学周")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 5) {
                Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)))
                    .font(.headline)
                Text("更新于 \(store.lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var todayCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("今日课程", systemImage: "clock.fill").font(.headline)
                Spacer()
                Button("查看课表") { store.selection = .schedule }.buttonStyle(.plain).foregroundStyle(Brand.blue)
            }
            ForEach(todayCourses) { course in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(course.color).frame(width: 5, height: 45)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(course.name).font(.subheadline.weight(.semibold))
                        if !course.className.isEmpty {
                            Text("教学班：\(course.className)").font(.caption2).foregroundStyle(.secondary)
                        }
                        Text("\(course.room) · \(course.teacher)").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("第\(course.start)–\(course.end)节")
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if course.id != todayCourses.last?.id { Divider() }
            }
            if todayCourses.isEmpty {
                ContentUnavailableView("今日暂无课程", systemImage: "calendar.badge.checkmark")
                    .frame(maxWidth: .infinity, minHeight: 120)
            }
        }
        .cardStyle()
        .frame(maxWidth: .infinity)
    }

    private var nextExamCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("最近考试", systemImage: "pencil.and.list.clipboard").font(.headline)
                Spacer()
                Button("全部考试") { store.selection = .exams }.buttonStyle(.plain).foregroundStyle(Brand.blue)
            }
            if let exam = nextExam {
                Text(exam.course).font(.title3.bold())
                HStack(spacing: 18) {
                    Label(exam.date.formatted(.dateTime.month().day().hour().minute()), systemImage: "calendar")
                    Label(exam.place, systemImage: "mappin.and.ellipse")
                }
                .font(.subheadline).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                HStack {
                    Text("还有 \(max(0, Calendar.current.dateComponents([.day], from: .now, to: exam.date).day ?? 0)) 天")
                        .font(.title2.bold()).foregroundStyle(.orange)
                    Spacer()
                    Text("座位 \(exam.seat)").font(.subheadline).padding(.horizontal, 12).padding(.vertical, 6).background(.quaternary, in: Capsule())
                }
            }
            else {
                ContentUnavailableView("暂无考试安排", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity, minHeight: 130)
            }
        }
        .cardStyle()
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .top)
    }

    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("快捷入口").font(.headline)
            HStack(spacing: 12) {
                quickButton("校园卡", "creditcard.fill", .blue, .card)
                quickButton("查成绩", "chart.bar.doc.horizontal.fill", .orange, .grades)
                quickButton("考试安排", "pencil.and.list.clipboard", .purple, .exams)
                quickButton("校园服务", "square.grid.2x2.fill", .green, .services)
            }
        }
    }

    private func quickButton(_ title: String, _ symbol: String, _ tint: Color, _ section: AppSection) -> some View {
        Button { store.selection = section } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(tint)
                Text(title).foregroundStyle(.primary)
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
            .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.3)) }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
    }
}
