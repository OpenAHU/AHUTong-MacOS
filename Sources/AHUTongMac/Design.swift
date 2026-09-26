import SwiftUI

enum Brand {
    static let blue = Color(red: 0.08, green: 0.32, blue: 0.82)
    static let cyan = Color(red: 0.10, green: 0.67, blue: 0.88)
    static let purple = Color(red: 0.44, green: 0.25, blue: 0.86)
    static let background = Color(nsColor: .windowBackgroundColor)
}

struct AppLogo: View {
    let size: CGFloat

    var body: some View {
        Image("AHULogo")
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .background(Color.white, in: Circle())
            .clipShape(Circle())
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 18

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(Color.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.separator.opacity(0.35), lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.035), radius: 10, y: 3)
    }
}

extension View {
    func cardStyle(padding: CGFloat = 18) -> some View {
        modifier(CardStyle(padding: padding))
    }
}

struct PageHeader: View {
    let title: String
    let subtitle: String
    var symbol: String? = nil

    var body: some View {
        HStack(spacing: 14) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Brand.blue.gradient, in: RoundedRectangle(cornerRadius: 13))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 25, weight: .bold, design: .rounded))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

struct MetricCard: View {
    let title: String
    let value: String
    let subtitle: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(value).font(.system(size: 23, weight: .bold, design: .rounded))
                Text(subtitle).font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .cardStyle(padding: 16)
    }
}

struct DemoBadge: View {
    var body: some View {
        Label("演示模式", systemImage: "sparkles")
            .font(.caption.weight(.medium))
            .foregroundStyle(.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(.orange.opacity(0.1), in: Capsule())
    }
}
