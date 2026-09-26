import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore

    private let days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private let periods = CoursePeriod.labels

    private var visibleCourses: [Course] {
        store.courses.filter { $0.isActive(in: store.selectedWeek) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            GeometryReader { geo in
                let timeWidth: CGFloat = 72
                let dayWidth = max(132, (geo.size.width - timeWidth - 24) / CGFloat(days.count))
                let rowHeight: CGFloat = max(58, (geo.size.height - 54) / CGFloat(store.totalPeriods))
                ScrollView([.vertical, .horizontal]) {
                    ZStack(alignment: .topLeading) {
                        timetableGrid(timeWidth: timeWidth, dayWidth: dayWidth, rowHeight: rowHeight)
                        ForEach(visibleCourses) { course in
                            courseBlock(course, timeWidth: timeWidth, dayWidth: dayWidth, rowHeight: rowHeight)
                        }
                    }
                    .frame(
                        width: timeWidth + dayWidth * CGFloat(days.count),
                        height: 54 + rowHeight * CGFloat(store.totalPeriods)
                    )
                    .padding(.horizontal, 12)
                }
                .overlay {
                    if visibleCourses.isEmpty {
                        ContentUnavailableView(
                            "第 \(store.selectedWeek) 周暂无课程",
                            systemImage: "calendar.badge.checkmark",
                            description: Text("可切换教学周查看其他安排")
                        )
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PageHeader(
                title: "电子课表",
                subtitle: "共 \(store.totalWeeks) 周 · 当前第 \(store.currentWeek) 周",
                symbol: "calendar.day.timeline.left"
            )
            Spacer()
            Button {
                store.selectedWeek = max(1, store.selectedWeek - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(store.selectedWeek == 1)

            VStack(spacing: 1) {
                Text("第 \(store.selectedWeek) 周")
                    .font(.headline)
                if store.selectedWeek == store.currentWeek {
                    Text("当前周").font(.caption2).foregroundStyle(.tint)
                }
            }
            .frame(minWidth: 78)

            Button {
                store.selectedWeek = min(store.totalWeeks, store.selectedWeek + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(store.selectedWeek == store.totalWeeks)

            Button("本周") {
                store.selectedWeek = store.currentWeek
            }
            .buttonStyle(.bordered)
            .disabled(store.selectedWeek == store.currentWeek)
        }
        .padding(26)
    }

    private func timetableGrid(timeWidth: CGFloat, dayWidth: CGFloat, rowHeight: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(0...days.count, id: \.self) { column in
                Path { path in
                    let x = timeWidth + CGFloat(column) * dayWidth
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: 54 + rowHeight * CGFloat(store.totalPeriods)))
                }
                .stroke(.separator.opacity(0.35), lineWidth: 1)
            }
            ForEach(0...store.totalPeriods, id: \.self) { row in
                Path { path in
                    let y = 54 + CGFloat(row) * rowHeight
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: timeWidth + dayWidth * CGFloat(days.count), y: y))
                }
                .stroke(.separator.opacity(0.35), lineWidth: 1)
            }
            ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                Text(day)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: dayWidth, height: 54)
                    .offset(x: timeWidth + CGFloat(index) * dayWidth)
            }
            ForEach(Array(periods.prefix(store.totalPeriods).enumerated()), id: \.offset) { index, time in
                VStack(spacing: 2) {
                    Text("\(index + 1)").font(.caption.bold())
                    Text(time).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                }
                .frame(width: timeWidth, height: rowHeight)
                .offset(y: 54 + CGFloat(index) * rowHeight)
            }
        }
    }

    private func courseBlock(_ course: Course, timeWidth: CGFloat, dayWidth: CGFloat, rowHeight: CGFloat) -> some View {
        let border = RoundedRectangle(cornerRadius: 10)
        let xOffset = timeWidth + CGFloat(course.weekday - 1) * dayWidth + 4
        let yOffset = 54 + CGFloat(course.start - 1) * rowHeight + 4
        return VStack(alignment: .leading, spacing: 3) {
            Text(course.name).font(.caption.weight(.bold)).lineLimit(2)
            if !course.className.isEmpty {
                Text("班级 · \(course.className)")
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
            }
            Text(course.room).font(.caption2).lineLimit(1)
            Spacer(minLength: 1)
            Text(course.teacher.isEmpty ? "教师待公布" : course.teacher)
                .font(.caption2)
                .opacity(0.82)
        }
        .foregroundStyle(course.color)
        .padding(7)
        .frame(width: dayWidth - 8, height: rowHeight * CGFloat(course.length) - 8, alignment: .topLeading)
        .background(course.color.opacity(0.13), in: border)
        .overlay(border.stroke(course.color.opacity(0.25)))
        .offset(x: xOffset, y: yOffset)
        .help(courseHelp(course))
    }

    private func courseHelp(_ course: Course) -> String {
        var lines = [course.name]
        if !course.className.isEmpty { lines.append("班级：\(course.className)") }
        lines.append("教师：\(course.teacher.isEmpty ? "待公布" : course.teacher)")
        lines.append("地点：\(course.room)")
        lines.append("周次：\(course.weeks.isEmpty ? "待公布" : course.weeks)")
        lines.append("节次：\(course.start)-\(course.end)")
        return lines.joined(separator: "\n")
    }

}
