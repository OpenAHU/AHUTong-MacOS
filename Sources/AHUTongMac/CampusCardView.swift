import CoreImage.CIFilterBuiltins
import SwiftUI

struct CampusCardView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(title: "校园卡", subtitle: " ", symbol: "creditcard.fill")
                HStack(alignment: .top, spacing: 20) {
                    cardVisual
                    qrPanel.frame(width: 280)
                }
                VStack(alignment: .leading, spacing: 11) {
                    Label("安全提示", systemImage: "lock.shield.fill")
                        .font(.headline).foregroundStyle(.green)
                    Text("付款码来自智慧安大校园卡服务，请勿截屏或转发。当前版本仅提供余额与付款码查询，不会在未经确认的情况下发起充值或支付。")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .cardStyle()
            }
            .padding(28)
            .frame(maxWidth: 1050, alignment: .leading)
        }
    }

    private var cardVisual: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(LinearGradient(colors: [Brand.blue, Brand.purple], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().fill(.white.opacity(0.08)).frame(width: 240).offset(x: 330, y: -100)
            Circle().fill(.white.opacity(0.06)).frame(width: 170).offset(x: 390, y: 110)
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("AHU · 安大通").font(.headline)
                        Text("安徽大学校园卡").font(.caption).opacity(0.75)
                    }
                    Spacer()
                    Image(systemName: "wave.3.right").font(.title2)
                }
                Spacer()
                Text("可用余额").font(.caption).opacity(0.75)
                Text("¥\(store.decimal(store.balance))").font(.system(size: 38, weight: .bold, design: .rounded))
                Spacer()
                HStack {
                    Text(store.profileDisplayName).font(.subheadline.weight(.semibold))
                    Text(store.studentID).font(.caption.monospaced()).opacity(0.8)
                    Spacer()
                    Text("实时数据").font(.caption.weight(.medium))
                        .padding(.horizontal, 10).padding(.vertical, 5).background(.white.opacity(0.14), in: Capsule())
                }
            }
            .foregroundStyle(.white)
            .padding(24)
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .shadow(color: Brand.blue.opacity(0.18), radius: 18, y: 8)
    }

    private var qrPanel: some View {
        VStack(spacing: 14) {
            Text("校园付款码").font(.headline)
            if let payload = store.cardQRCode, let image = makeQRCode(payload) {
                Image(nsImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .padding(8)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("校园卡付款二维码")
            } else {
                Image(systemName: "qrcode")
                    .font(.system(size: 90)).foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Text("付款码暂不可用").font(.caption).foregroundStyle(.secondary)
            }
            Button("刷新付款码") { store.refresh() }.buttonStyle(.bordered)
        }
        .cardStyle()
        .frame(minHeight: 280)
    }

    private func makeQRCode(_ payload: String) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let representation = NSCIImageRep(ciImage: output)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
