import SwiftUI

struct ServicesView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.openURL) private var openURL

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "校园服务", subtitle: "常用校园入口集中访问", symbol: "sparkles.square.filled.on.square")
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(store.services) { service in
                        Button { open(service) } label: { serviceCard(service) }
                            .buttonStyle(.plain)
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Label("说明", systemImage: "lock.shield.fill").font(.headline).foregroundStyle(.green)
                    Text("本页面链接将跳转至外部浏览器打开")
                        .font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(28).frame(maxWidth: 1100, alignment: .leading)
        }
        .alert("校园地图", isPresented: $store.showMapNotice) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("当前安装包未包含离线地图资源。")
        }
    }

    private func serviceCard(_ service: CampusService) -> some View {
        HStack(spacing: 14) {
            Image(systemName: service.symbol)
                .font(.system(size: 20, weight: .semibold)).foregroundStyle(service.color)
                .frame(width: 46, height: 46)
                .background(service.color.opacity(0.11), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(service.title).font(.headline).foregroundStyle(.primary)
                Text(service.subtitle).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: service.url == nil ? "chevron.right" : "arrow.up.right")
                .font(.caption).foregroundStyle(.tertiary)
        }
        .cardStyle(padding: 16)
    }

    private func open(_ service: CampusService) {
        if let url = service.url { openURL(url) }
        else { store.showMapNotice = true }
    }
}
