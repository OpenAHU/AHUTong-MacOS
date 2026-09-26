import SwiftUI

struct RootView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        Group {
            if store.sessionPhase == .authenticated {
                authenticatedContent
            } else {
                LoginView()
            }
        }
        .tint(Brand.blue)
        .preferredColorScheme(.light)
        .sheet(isPresented: $store.showProfileSettings) {
            ProfileSettingsView()
                .environmentObject(store)
        }
    }

    private var authenticatedContent: some View {
        NavigationSplitView {
            List(selection: $store.selection) {
                Section("校园") {
                    ForEach(AppSection.allCases.filter { $0 != .about }) { item in
                        Label(item.rawValue, systemImage: item.symbol)
                            .tag(item)
                    }
                }
                Section {
                    Label(AppSection.about.rawValue, systemImage: AppSection.about.symbol)
                        .tag(AppSection.about)
                }
            }
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 245)
            .safeAreaInset(edge: .bottom) {
                profilePanel
            }
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.white)
                .toolbar { toolbar }
        }
    }

    @ViewBuilder private var detail: some View {
        switch store.selection ?? .overview {
        case .overview: OverviewView()
        case .schedule: ScheduleView()
        case .card: CampusCardView()
        case .grades: GradesView()
        case .exams: ExamsView()
        case .services: ServicesView()
        case .about: AboutView()
        }
    }

    private var profilePanel: some View {
        HStack(spacing: 11) {
            Button {
                store.showProfileSettings = true
            } label: {
                HStack(spacing: 11) {
                    ProfileAvatarView(
                        imageData: store.profileAvatarData,
                        fallbackName: store.profileDisplayName,
                        size: 36
                    )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.profileDisplayName).font(.subheadline.weight(.semibold))
                        Text(store.studentID).font(.caption2).foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("编辑本地个人资料")
            Spacer(minLength: 4)
            Button { store.signOut() } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
            }
            .buttonStyle(.plain)
            .help("退出登录并清除钥匙串凭据")
        }
        .padding(12)
        .background(.bar)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if !store.dataWarnings.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .help(store.dataWarnings.joined(separator: "\n"))
            }
            Button {
                store.refresh()
            } label: {
                if store.isRefreshing { ProgressView().controlSize(.small) }
                else { Label("刷新", systemImage: "arrow.clockwise") }
            }
            .help("刷新数据（⌘R）")
        }
    }
}
