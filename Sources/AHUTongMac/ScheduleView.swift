import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore

    private let days = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
    private let periods = CoursePeriod.labels

    private func calculateIndicatorY(totalMinutes: Int, rowHeight: CGFloat)
        -> CGFloat?
    {
        // 映射课表的起止时间
        // 格式：(开始的分钟数, 结束的分钟数)
        let schedule: [(start: Int, end: Int)] = [
            (8 * 60 + 0, 8 * 60 + 45),  // 0: 第1节
            (8 * 60 + 50, 9 * 60 + 35),  // 1: 第2节
            (9 * 60 + 50, 10 * 60 + 35),  // 2: 第3节
            (10 * 60 + 40, 11 * 60 + 25),  // 3: 第4节
            (11 * 60 + 30, 12 * 60 + 15),  // 4: 第5节
            (14 * 60 + 0, 14 * 60 + 45),  // 5: 第6节
            (14 * 60 + 50, 15 * 60 + 35),  // 6: 第7节
            (15 * 60 + 50, 16 * 60 + 35),  // 7: 第8节
            (16 * 60 + 40, 17 * 60 + 25),  // 8: 第9节
            (17 * 60 + 30, 18 * 60 + 15),  // 9: 第10节
            (19 * 60 + 0, 19 * 60 + 45),  // 10: 第11节
            (19 * 60 + 50, 20 * 60 + 35),  // 11: 第12节
            (20 * 60 + 40, 21 * 60 + 25),  // 12: 第13节
        ]

        let headerHeight: CGFloat = 54.0  // 表头高度
        let dismissTime = 21 * 60 + 35  // 晚上 21:35 消失

        // 早上 8:00 前，或超过 21:35，直接隐藏
        if totalMinutes < schedule[0].start || totalMinutes >= dismissTime {
            return nil
        }

        for i in 0..<schedule.count {
            let period = schedule[i]

            // 上课中：按实际进行的分钟数占比，计算红线在这节课单元格里的偏移高度
            if totalMinutes >= period.start && totalMinutes <= period.end {
                let duration = CGFloat(period.end - period.start)
                let elapsed = CGFloat(totalMinutes - period.start)
                let progress = elapsed / duration
                return headerHeight + CGFloat(i) * rowHeight + progress
                    * rowHeight
            }

            // 课间休息：红线直接停留在两节课的网格分割线上
            if i < schedule.count - 1 {
                let nextPeriod = schedule[i + 1]
                if totalMinutes > period.end && totalMinutes < nextPeriod.start
                {
                    // 卡在第 i 节课的最底部（即第 i+1 节课的顶部分割线）
                    return headerHeight + CGFloat(i + 1) * rowHeight
                }
            }
        }

        // 最后一节课结束 (21:25) 后，但在 21:35 之前：停在整个课表最底部边缘
        if totalMinutes > schedule.last!.end && totalMinutes < dismissTime {
            return headerHeight + CGFloat(schedule.count) * rowHeight
        }

        return nil
    }

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

    private func timetableGrid(
        timeWidth: CGFloat,
        dayWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {

        let isCurrentWeek = store.selectedWeek == store.currentWeek

        return TimelineView(.periodic(from: .now, by: 60)) { _ in
            ZStack(alignment: .topLeading) {

                if isCurrentWeek {
                    currentDayHighlight(
                        timeWidth: timeWidth,
                        dayWidth: dayWidth,
                        rowHeight: rowHeight
                    )
                }

                ForEach(0...days.count, id: \.self) { column in
                    Path { path in
                        let x = timeWidth + CGFloat(column) * dayWidth
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(
                            to: CGPoint(
                                x: x,
                                y: 54 + rowHeight * CGFloat(store.totalPeriods)
                            )
                        )
                    }
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
                ForEach(0...store.totalPeriods, id: \.self) { row in
                    Path { path in
                        let y = 54 + CGFloat(row) * rowHeight
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(
                            to: CGPoint(
                                x: timeWidth + dayWidth * CGFloat(days.count),
                                y: y
                            )
                        )
                    }
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
                }
                ForEach(Array(days.enumerated()), id: \.offset) { index, day in
                    Text(day)
                        .font(.subheadline.weight(.semibold))
                        .frame(width: dayWidth, height: 54)
                        .offset(x: timeWidth + CGFloat(index) * dayWidth)
                }
                ForEach(
                    Array(periods.prefix(store.totalPeriods).enumerated()),
                    id: \.offset
                ) { index, time in
                    VStack(spacing: 2) {
                        Text("\(index + 1)").font(.caption.bold())
                        Text(time).font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: timeWidth, height: rowHeight)
                    .offset(y: 54 + CGFloat(index) * rowHeight)
                }

                if isCurrentWeek {
                    currentTimeIndicator(
                        timeWidth: timeWidth,
                        dayWidth: dayWidth,
                        rowHeight: rowHeight
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func currentDayHighlight(
        timeWidth: CGFloat,
        dayWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        let weekday = Calendar.current.component(.weekday, from: Date())
        let currentDayIndex = (weekday == 1) ? 6 : (weekday - 2)  // 转为 0=周一, 1=周二

        if currentDayIndex >= 0 && currentDayIndex < days.count {
            Rectangle()
                .fill(Color.accentColor.opacity(0.08))  // 浅色高亮
                .frame(
                    width: dayWidth,
                    height: 54 + rowHeight * CGFloat(store.totalPeriods)
                )
                .offset(x: timeWidth + CGFloat(currentDayIndex) * dayWidth)
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func currentTimeIndicator(
        timeWidth: CGFloat,
        dayWidth: CGFloat,
        rowHeight: CGFloat
    ) -> some View {
        let now = Date()
        let calendar = Calendar.current

        let currentHour = calendar.component(.hour, from: now)
        let currentMinute = calendar.component(.minute, from: now)
        let totalMinutes = currentHour * 60 + currentMinute
        let weekday = calendar.component(.weekday, from: now)
        let currentDayIndex = (weekday == 1) ? 6 : (weekday - 2)
        let isTodayInSchedule = currentDayIndex >= 0 && currentDayIndex < days.count

        if let currentY = calculateIndicatorY(
            totalMinutes: totalMinutes,
            rowHeight: rowHeight
        ) {
            let totalGridWidth = timeWidth + dayWidth * CGFloat(days.count)
            let todayStartX = timeWidth + CGFloat(currentDayIndex) * dayWidth
            let todayEndX = todayStartX + dayWidth

            ZStack(alignment: .topLeading) {
                Path { path in
                    if isTodayInSchedule {
                        path.move(to: CGPoint(x: 0, y: currentY))
                        path.addLine(to: CGPoint(x: todayStartX, y: currentY))
                        path.move(to: CGPoint(x: todayEndX, y: currentY))
                        path.addLine(to: CGPoint(x: totalGridWidth, y: currentY))
                    } else {
                        path.move(to: CGPoint(x: 0, y: currentY))
                        path.addLine(to: CGPoint(x: totalGridWidth, y: currentY))
                    }
                }
                .stroke(Color.red.opacity(0.25), lineWidth: 1.5)

                if isTodayInSchedule {
                    Path { path in
                        path.move(to: CGPoint(x: todayStartX, y: currentY))
                        path.addLine(to: CGPoint(x: todayEndX, y: currentY))
                    }
                    .stroke(Color.red, lineWidth: 2)
                }

                Circle()
                    .fill(Color.red)
                    .frame(width: 6, height: 6)
                    .offset(x: timeWidth - 3, y: currentY - 3)
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
