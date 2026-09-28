import SwiftUI

@MainActor
final class FreeClassroomViewModel: ObservableObject {
    enum RoomState {
        case idle
        case loading
        case loaded([FreeClassroomRoom])
        case failed(String)
    }

    @Published var selectedCampusID = ClassroomCampus.all[0].id
    @Published private(set) var buildings: [ClassroomBuilding] = []
    @Published var selectedBuildingIDs: Set<Int> = []
    @Published var selectedUnits: Set<Int> = []
    @Published var startDate: Date
    @Published var endDate: Date
    @Published private(set) var buildingsLoading = false
    @Published private(set) var roomState: RoomState = .idle

    private let client: CampusCoreClient

    init(client: CampusCoreClient = .shared, now: Date = .now) {
        self.client = client
        let today = Calendar.current.startOfDay(for: now)
        startDate = today
        endDate = today
    }

    var rooms: [FreeClassroomRoom] {
        if case let .loaded(rooms) = roomState { return rooms }
        return []
    }

    var isSearching: Bool {
        if case .loading = roomState { return true }
        return false
    }

    func loadBuildings() async {
        buildingsLoading = true
        selectedBuildingIDs = []
        roomState = .idle
        defer { buildingsLoading = false }
        do {
            buildings = try await client.freeClassroomBuildings(campusID: selectedCampusID)
        } catch {
            buildings = []
            roomState = .failed(error.localizedDescription)
        }
    }

    func toggleBuilding(_ id: Int) {
        if selectedBuildingIDs.contains(id) {
            selectedBuildingIDs.remove(id)
        } else {
            selectedBuildingIDs.insert(id)
        }
    }

    func selectAllBuildings() {
        let all = Set(buildings.map(\.id))
        selectedBuildingIDs = selectedBuildingIDs == all ? [] : all
    }

    func toggleUnit(_ unit: Int) {
        if selectedUnits.contains(unit) {
            selectedUnits.remove(unit)
        } else {
            selectedUnits.insert(unit)
        }
    }

    func toggleUnits(_ range: ClosedRange<Int>) {
        let values = Set(range)
        selectedUnits = values.isSubset(of: selectedUnits)
            ? selectedUnits.subtracting(values)
            : selectedUnits.union(values)
    }

    func setStartDate(_ value: Date) {
        startDate = Calendar.current.startOfDay(for: value)
        if endDate < startDate { endDate = startDate }
    }

    func setEndDate(_ value: Date) {
        endDate = max(Calendar.current.startOfDay(for: value), startDate)
    }

    func useDayOffset(_ offset: Int, now: Date = .now) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let day = calendar.date(byAdding: .day, value: offset, to: today) ?? today
        startDate = day
        endDate = day
    }

    func search() async {
        guard !buildings.isEmpty else { return }
        roomState = .loading
        do {
            let buildingIDs = selectedBuildingIDs.isEmpty
                ? buildings.map(\.id)
                : selectedBuildingIDs.sorted()
            let result = try await client.freeClassrooms(
                query: FreeClassroomQuery(
                    campusID: selectedCampusID,
                    buildingIDs: buildingIDs,
                    units: selectedUnits.sorted(),
                    startDate: startDate,
                    endDate: endDate
                )
            )
            roomState = .loaded(result)
        } catch {
            roomState = .failed(error.localizedDescription)
        }
    }
}

struct FreeClassroomView: View {
    @StateObject private var model = FreeClassroomViewModel()
    @State private var filtersExpanded = true

    private let buildingColumns = [GridItem(.adaptive(minimum: 150), spacing: 9)]
    private let unitColumns = [GridItem(.adaptive(minimum: 104), spacing: 8)]
    private let roomColumns = [GridItem(.adaptive(minimum: 245), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "空闲教室",
                    subtitle: " ",
                    symbol: "door.left.hand.open"
                )

                if filtersExpanded {
                    filters
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
                searchBar
                results
            }
            .padding(28)
            .frame(maxWidth: 1100, alignment: .leading)
        }
        .task { await model.loadBuildings() }
        .onChange(of: model.selectedCampusID) { _, _ in
            Task { await model.loadBuildings() }
        }
    }

    private var filters: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                filterCard(title: "校区", symbol: "building.2.fill") {
                    Picker("校区", selection: $model.selectedCampusID) {
                        ForEach(ClassroomCampus.all) { campus in
                            Text(campus.name).tag(campus.id)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }

                filterCard(title: "日期", symbol: "calendar") {
                    HStack(spacing: 8) {
                        shortcutButton("今天", selected: isSameSingleDay(.now)) {
                            model.useDayOffset(0)
                        }
                        shortcutButton("明天", selected: isTomorrowSingleDay) {
                            model.useDayOffset(1)
                        }
                        Spacer(minLength: 8)
                    }
                    HStack(spacing: 8) {
                        DatePicker(
                            "开始",
                            selection: Binding(get: { model.startDate }, set: { model.setStartDate($0) }),
                            in: Calendar.current.startOfDay(for: .now)...,
                            displayedComponents: .date
                        )
                        DatePicker(
                            "结束",
                            selection: Binding(get: { model.endDate }, set: { model.setEndDate($0) }),
                            in: model.startDate...,
                            displayedComponents: .date
                        )
                    }
                    .datePickerStyle(.compact)
                }
            }

            filterCard(title: "教学楼", symbol: "building.columns.fill") {
                if model.buildingsLoading {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("正在从教务系统读取教学楼…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else if model.buildings.isEmpty {
                    Text("当前校区暂无可查询的教学楼")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                } else {
                    HStack {
                        Text(model.selectedBuildingIDs.isEmpty ? "未选择时查询全部教学楼" : "已选择 \(model.selectedBuildingIDs.count) 栋")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(model.selectedBuildingIDs.count == model.buildings.count ? "清除" : "全选") {
                            model.selectAllBuildings()
                        }
                        .buttonStyle(.link)
                    }
                    LazyVGrid(columns: buildingColumns, alignment: .leading, spacing: 9) {
                        ForEach(model.buildings) { building in
                            selectionButton(
                                building.nameZh,
                                selected: model.selectedBuildingIDs.contains(building.id)
                            ) {
                                model.toggleBuilding(building.id)
                            }
                        }
                    }
                }
            }

            filterCard(title: "节次", symbol: "clock.fill") {
                HStack(spacing: 8) {
                    shortcutButton("上午 1–5", selected: unitsSelected(1...5)) { model.toggleUnits(1...5) }
                    shortcutButton("下午 6–10", selected: unitsSelected(6...10)) { model.toggleUnits(6...10) }
                    shortcutButton("晚上 11–13", selected: unitsSelected(11...13)) { model.toggleUnits(11...13) }
                    Spacer()
                    if !model.selectedUnits.isEmpty {
                        Button("清除") { model.selectedUnits = [] }
                            .buttonStyle(.link)
                    }
                }
                LazyVGrid(columns: unitColumns, alignment: .leading, spacing: 8) {
                    ForEach(1...13, id: \.self) { unit in
                        selectionButton("第 \(unit) 节", selected: model.selectedUnits.contains(unit)) {
                            model.toggleUnit(unit)
                        }
                    }
                }
                Text("未选择节次时默认查询第 1–13 节")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Button {
                Task { await model.search() }
                withAnimation { filtersExpanded = false }
            } label: {
                HStack(spacing: 8) {
                    if model.isSearching { ProgressView().controlSize(.small) }
                    Text(model.isSearching ? "正在查询…" : "查询空闲教室")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSearching || model.buildingsLoading || model.buildings.isEmpty)
            .keyboardShortcut(.return, modifiers: .command)

            Button {
                withAnimation { filtersExpanded.toggle() }
            } label: {
                Label(filtersExpanded ? "收起条件" : "修改条件", systemImage: filtersExpanded ? "chevron.up" : "slider.horizontal.3")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }

    @ViewBuilder private var results: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("查询结果").font(.title3.bold())
                Spacer()
                if case let .loaded(rooms) = model.roomState {
                    Text("共 \(rooms.count) 间")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            switch model.roomState {
            case .idle:
                ContentUnavailableView(
                    "设置条件后开始查询",
                    systemImage: "door.left.hand.open",
                    description: Text(" ")
                )
                .frame(maxWidth: .infinity, minHeight: 210)
                .cardStyle()
            case .loading:
                VStack(spacing: 12) {
                    ProgressView().controlSize(.large)
                    Text("正在查询空闲教室…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 210)
                .cardStyle()
            case let .failed(message):
                ContentUnavailableView(
                    "查询失败",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                .frame(maxWidth: .infinity, minHeight: 210)
                .cardStyle()
            case let .loaded(rooms) where rooms.isEmpty:
                ContentUnavailableView(
                    "暂无符合条件的空闲教室",
                    systemImage: "magnifyingglass",
                    description: Text("可以尝试更换教学楼、日期或节次")
                )
                .frame(maxWidth: .infinity, minHeight: 210)
                .cardStyle()
            case let .loaded(rooms):
                LazyVGrid(columns: roomColumns, alignment: .leading, spacing: 14) {
                    ForEach(rooms) { room in
                        roomCard(room)
                    }
                }
            }
        }
    }

    private func roomCard(_ room: FreeClassroomRoom) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(room.nameZh).font(.headline)
                    if !room.code.isEmpty, room.code != room.nameZh {
                        Text(room.code).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .help("所选时段空闲")
            }
            Divider()
            Label(room.building.nameZh, systemImage: "building.2")
            HStack(spacing: 16) {
                Label("\(room.floor) 层", systemImage: "stairs")
                if room.seats > 0 {
                    Label("\(room.seats) 座", systemImage: "person.2")
                }
            }
            if let remark = room.remark, !remark.isEmpty {
                Text(remark).font(.caption).foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 122, alignment: .topLeading)
        .cardStyle(padding: 16)
    }

    private func filterCard<Content: View>(
        title: String,
        symbol: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: symbol).font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private func selectionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                Text(title)
                    .lineLimit(1)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .font(.subheadline)
            .foregroundStyle(selected ? Brand.blue : Color.primary)
            .padding(.horizontal, 11)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Brand.blue.opacity(0.1) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay {
                RoundedRectangle(cornerRadius: 9)
                    .stroke(selected ? Brand.blue.opacity(0.45) : Color.clear, lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func shortcutButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .tint(selected ? Brand.blue : .secondary)
    }

    private func unitsSelected(_ range: ClosedRange<Int>) -> Bool {
        Set(range).isSubset(of: model.selectedUnits)
    }

    private func isSameSingleDay(_ date: Date) -> Bool {
        Calendar.current.isDate(model.startDate, inSameDayAs: date)
            && Calendar.current.isDate(model.endDate, inSameDayAs: date)
    }

    private var isTomorrowSingleDay: Bool {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        return isSameSingleDay(tomorrow)
    }
}
