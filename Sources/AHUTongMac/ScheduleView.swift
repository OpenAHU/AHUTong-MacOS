import AppKit
import SwiftUI

struct ScheduleView: View {
    @EnvironmentObject private var store: AppStore
    @State private var semesters: [CampusScheduleSemester] = []
    @State private var selectedSemesterID = ""
    @State private var semesterWeeks: [String: Int] = [:]
    @State private var selectedSemesterCourses: [Course] = []
    @State private var isLoadingSemesters = false
    @State private var isLoadingSchedule = false
    @State private var semesterError: String?
    @State private var scheduleError: String?
    @State private var semesterListRevision = 0
    @State private var scheduleRevision = 0
    @State private var semesterAccountID = ""
    @State private var hoveredCourseID: Course.ID?

    private var currentSemesterID: String {
        semesters.first(where: \.current)?.id ?? ""
    }
    private var isCurrentSemester: Bool {
        selectedSemesterID.isEmpty || selectedSemesterID == currentSemesterID
    }
    private var selectedSemester: CampusScheduleSemester? {
        semesters.first { $0.id == selectedSemesterID }
    }
    private var displayedCourses: [Course] {
        isCurrentSemester ? store.courses : selectedSemesterCourses
    }

    private var displayedWeek: Int {
        get { isCurrentSemester ? store.selectedWeek : semesterWeeks[selectedSemesterID, default: 1] }
        nonmutating set {
            if isCurrentSemester { store.selectedWeek = newValue }
            else { semesterWeeks[selectedSemesterID] = newValue }
        }
    }
    private var displayedTotalWeeks: Int {
        max(store.totalWeeks, displayedCourses.flatMap(\.weekIndexes).max() ?? 1)
    }

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
        displayedCourses.filter { $0.isActive(in: displayedWeek) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if !isCurrentSemester || semesterError != nil {
                HStack {
                    Label(
                        semesterError ?? "正在查看 \(selectedSemester?.name ?? "所选学期")，不会影响本学期课程和上课提醒",
                        systemImage: semesterError == nil ? "info.circle" : "exclamationmark.triangle"
                    )
                    Spacer()
                    if semesterError != nil {
                        Button("重试学期列表") { semesterListRevision += 1 }
                            .disabled(isLoadingSemesters)
                    }
                    Button("刷新课表") {
                        if isCurrentSemester { store.refresh() }
                        else { scheduleRevision += 1 }
                    }
                    .disabled(isLoadingSchedule || store.isRefreshing)
                }
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 26).padding(.bottom, 12)
            }
            Divider()

            GeometryReader { geo in
                let timeWidth: CGFloat = 72
                let dayWidth = max(
                    132,
                    (geo.size.width - timeWidth - 24) / CGFloat(days.count)
                )
                let rowHeight: CGFloat = max(
                    58,
                    (geo.size.height - 54) / CGFloat(store.totalPeriods)
                )
                let fontScale = min(
                    1.18,
                    max(0.9, min(dayWidth / 124, rowHeight / 58))
                )
                ScrollView([.vertical, .horizontal]) {
                    ZStack(alignment: .topLeading) {
                        timetableGrid(
                            timeWidth: timeWidth,
                            dayWidth: dayWidth,
                            rowHeight: rowHeight,
                            fontScale: fontScale
                        )
                        ForEach(visibleCourses) { course in
                            courseBlock(
                                course,
                                timeWidth: timeWidth,
                                dayWidth: dayWidth,
                                rowHeight: rowHeight,
                                fontScale: fontScale
                            )
                        }
                    }
                    .frame(
                        width: timeWidth + dayWidth * CGFloat(days.count),
                        height: 54 + rowHeight * CGFloat(store.totalPeriods)
                    )
                    .padding(.horizontal, 12)
                }
                .overlay {
                    if isLoadingSchedule && !isCurrentSemester {
                        ProgressView("正在读取所选学期课表…")
                            .padding(24).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    } else if visibleCourses.isEmpty {
                        ContentUnavailableView(
                            scheduleError != nil && !isCurrentSemester ? "课表读取失败" : "第 \(displayedWeek) 周暂无课程",
                            systemImage: "calendar.badge.checkmark",
                            description: Text(scheduleError ?? "可切换教学周查看其他安排")
                        )
                    }
                }
            }
        }
        .task(id: "\(store.studentID)|\(store.lastUpdated.timeIntervalSince1970)|\(semesterListRevision)") {
            let accountID = store.studentID
            let accountChanged = semesterAccountID != accountID
            if accountChanged {
                semesterAccountID = accountID
                semesters = []
                selectedSemesterID = ""
                selectedSemesterCourses = []
                semesterWeeks = [:]
                scheduleError = nil
            }
            isLoadingSemesters = true
            semesterError = nil
            do {
                let values = try await store.performCampusRequest { try await $0.scheduleSemesters() }
                guard !Task.isCancelled, store.studentID == accountID else { return }
                semesters = values
                if accountChanged || !values.contains(where: { $0.id == selectedSemesterID }) {
                    selectedSemesterID = values.first(where: \.current)?.id ?? values.first?.id ?? ""
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, store.studentID == accountID else { return }
                semesterError = "学期列表读取失败：\(error.localizedDescription)"
            }
            if store.studentID == accountID { isLoadingSemesters = false }
        }
        .task(id: "\(store.studentID)|\(selectedSemesterID)|\(scheduleRevision)") {
            let semesterID = selectedSemesterID
            guard !semesterID.isEmpty, !isCurrentSemester else {
                selectedSemesterCourses = []
                scheduleError = nil
                isLoadingSchedule = false
                return
            }
            isLoadingSchedule = true
            scheduleError = nil
            selectedSemesterCourses = []
            do {
                let values = try await store.performCampusRequest { try await $0.courses(semesterID: semesterID) }
                guard !Task.isCancelled, selectedSemesterID == semesterID else { return }
                selectedSemesterCourses = store.mapCourses(values)
                let maximumWeek = max(store.totalWeeks, selectedSemesterCourses.flatMap(\.weekIndexes).max() ?? 1)
                semesterWeeks[semesterID] = min(max(semesterWeeks[semesterID, default: 1], 1), maximumWeek)
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, selectedSemesterID == semesterID else { return }
                scheduleError = error.localizedDescription
            }
            if selectedSemesterID == semesterID { isLoadingSchedule = false }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            PageHeader(
                title: "电子课表",
                subtitle: "\(selectedSemester?.name ?? "当前学期") · 共 \(displayedTotalWeeks) 周" + (isCurrentSemester ? " · 当前第 \(store.currentWeek) 周" : ""),
                symbol: "calendar.day.timeline.left"
            )
            Spacer()
            Picker("学期课程表", selection: $selectedSemesterID) {
                if semesters.isEmpty {
                    Text(isLoadingSemesters ? "正在读取学期…" : "当前学期").tag("")
                }
                ForEach(semesters) { semester in
                    Text(semester.current ? "\(semester.name)（当前）" : semester.name).tag(semester.id)
                }
            }
            .labelsHidden().frame(width: 190).disabled(isLoadingSemesters || semesters.isEmpty)
            Button {
                displayedWeek = max(1, displayedWeek - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(displayedWeek == 1)

            VStack(spacing: 1) {
                Text("第 \(displayedWeek) 周")
                    .font(.headline)
                if isCurrentSemester && displayedWeek == store.currentWeek {
                    Text("当前周").font(.caption2).foregroundStyle(.tint)
                }
            }
            .frame(minWidth: 78)

            Button {
                displayedWeek = min(displayedTotalWeeks, displayedWeek + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(displayedWeek == displayedTotalWeeks)

            Button("本周") {
                selectedSemesterID = currentSemesterID
                store.selectedWeek = store.currentWeek
            }
            .buttonStyle(.bordered)
            .disabled(isCurrentSemester && store.selectedWeek == store.currentWeek)
        }
        .padding(26)
    }

    private func timetableGrid(
        timeWidth: CGFloat,
        dayWidth: CGFloat,
        rowHeight: CGFloat,
        fontScale: CGFloat
    ) -> some View {

        let isCurrentWeek = isCurrentSemester && displayedWeek == store.currentWeek

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
                        .font(.system(size: 15 * fontScale, weight: .semibold))
                        .frame(width: dayWidth, height: 54)
                        .offset(x: timeWidth + CGFloat(index) * dayWidth)
                }
                ForEach(
                    Array(periods.prefix(store.totalPeriods).enumerated()),
                    id: \.offset
                ) { index, time in
                    VStack(spacing: 2) {
                        Text("\(index + 1)")
                            .font(.system(size: 13 * fontScale, weight: .semibold))
                        Text(time)
                            .font(
                                .system(
                                    size: 11 * fontScale,
                                    weight: .regular,
                                    design: .monospaced
                                )
                            )
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

    private func courseBlock(
        _ course: Course,
        timeWidth: CGFloat,
        dayWidth: CGFloat,
        rowHeight: CGFloat,
        fontScale: CGFloat
    ) -> some View {
        let blockWidth = dayWidth - 8
        let blockHeight = rowHeight * CGFloat(course.length) - 8
        let isCompact = blockHeight < 76
        let horizontalPadding = isCompact ? CGFloat(10) : 14 * fontScale
        let textWidth = max(0, blockWidth - horizontalPadding)
        let hasOverflow =
            isCompact
            || textExceedsWidth(
                course.name,
                fontSize: 14 * fontScale,
                weight: .bold,
                width: textWidth * 2
            )
            || (!isCompact
                && [
                    course.className.isEmpty ? nil : "班级 · \(course.className)",
                    course.room,
                    course.teacher.isEmpty ? "教师待公布" : course.teacher,
                ].compactMap { $0 }.contains {
                    textExceedsWidth(
                        $0,
                        fontSize: 11 * fontScale,
                        weight: .regular,
                        width: textWidth
                    )
                })
        let xOffset = timeWidth + CGFloat(course.weekday - 1) * dayWidth + 4
        let yOffset = 54 + CGFloat(course.start - 1) * rowHeight + 4
        return ScheduleCourseBlock(
            course: course,
            width: blockWidth,
            height: blockHeight,
            fontScale: fontScale,
            isCompact: isCompact,
            isExpanded: hasOverflow && hoveredCourseID == course.id,
            xOffset: xOffset,
            yOffset: yOffset,
            onHover: { isHovering in
                if isHovering && hasOverflow {
                    hoveredCourseID = course.id
                } else if hoveredCourseID == course.id {
                    hoveredCourseID = nil
                }
            }
        )
    }

    private func textExceedsWidth(
        _ text: String,
        fontSize: CGFloat,
        weight: NSFont.Weight,
        width: CGFloat
    ) -> Bool {
        let font = NSFont.systemFont(ofSize: fontSize, weight: weight)
        return (text as NSString).size(withAttributes: [.font: font]).width
            > width
    }

}

private struct ScheduleCourseBlock: View {
    let course: Course
    let width: CGFloat
    let height: CGFloat
    let fontScale: CGFloat
    let isCompact: Bool
    let isExpanded: Bool
    let xOffset: CGFloat
    let yOffset: CGFloat
    let onHover: (Bool) -> Void

    private var border: RoundedRectangle {
        RoundedRectangle(cornerRadius: 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3 * fontScale) {
            Text(course.name)
                .font(.system(size: 14 * fontScale, weight: .bold))
                .lineLimit(isCompact ? 1 : 2)
            if !isCompact {
                if !course.className.isEmpty {
                    Text("班级 · \(course.className)")
                        .font(.system(size: 11 * fontScale))
                        .lineLimit(1)
                }
                Text(course.room)
                    .font(.system(size: 11 * fontScale))
                    .lineLimit(1)
                Spacer(minLength: 1)
                Text(course.teacher.isEmpty ? "教师待公布" : course.teacher)
                    .font(.system(size: 11 * fontScale))
                    .opacity(0.82)
                    .lineLimit(1)
            } else {
                Text(course.room)
                    .font(.system(size: 11 * fontScale))
                    .lineLimit(1)
            }
        }
        .foregroundStyle(course.color)
        .padding(isCompact ? 5 : 7 * fontScale)
        .frame(width: width, height: height, alignment: .topLeading)
        .background(course.color.opacity(0.13), in: border)
        .overlay(border.stroke(course.color.opacity(0.25)))
        .overlay(alignment: .topLeading) {
            if isExpanded {
                expandedDetails
                    .offset(x: -4, y: -4)
                    .onHover(perform: onHover)
                    .transition(
                        .opacity.combined(
                            with: .scale(scale: 0.96, anchor: .topLeading)
                        )
                    )
            }
        }
        .onHover(perform: onHover)
        .offset(x: xOffset, y: yOffset)
        .zIndex(isExpanded ? 1 : 0)
        .animation(.easeOut(duration: 0.16), value: isExpanded)
    }

    private var expandedDetails: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(course.name)
                .font(.system(size: 14 * fontScale, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            detailLine(
                "班级",
                value: course.className.isEmpty ? "未公布" : course.className
            )
            detailLine(
                "教师",
                value: course.teacher.isEmpty ? "待公布" : course.teacher
            )
            detailLine("地点", value: course.room)
            detailLine("周次", value: course.weeks.isEmpty ? "待公布" : course.weeks)
            detailLine("节次", value: "\(course.start)-\(course.end)")
        }
        .foregroundStyle(course.color)
        .padding(10)
        .frame(width: max(width * 1.2, 190), alignment: .leading)
        .background(.white, in: border)
        .overlay(border.stroke(course.color.opacity(0.55), lineWidth: 1.5))
        // .shadow(color: .black.opacity(0.22), radius: 8, y: 4)
    }

    private func detailLine(_ title: String, value: String) -> some View {
        Text("\(title) · \(value)")
            .font(.system(size: 11 * fontScale))
            .fixedSize(horizontal: false, vertical: true)
    }
}
