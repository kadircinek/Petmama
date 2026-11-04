#if canImport(UIKit)
import SwiftUI
import MamaCore

/// Boş durum: "Bu sokağın ilk besleyicisi sen ol" (PRD 6.4).
public struct EmptyStateView: View {
    let systemImage: String
    let title: String
    let message: String?
    let actionTitle: String?
    let action: (() -> Void)?

    public init(systemImage: String, title: String, message: String? = nil, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(MamaColor.textPrimary)
                .frame(width: 84, height: 84)
                .background(Circle().fill(MamaColor.tileMint))
                .accessibilityHidden(true)
            Text(LocalizedStringKey(title))
                .font(MamaFont.title3)
                .foregroundStyle(MamaColor.textPrimary)
                .multilineTextAlignment(.center)
            if let message {
                Text(LocalizedStringKey(message))
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            if let actionTitle, let action {
                Button(action: action) { Text(LocalizedStringKey(actionTitle)) }
                    .buttonStyle(.mamaPrimary(fullWidth: false))
                    .padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }
}

/// Bilgi bandı (çevrimdışı, hata, uyarı).
public struct BannerView: View {
    public enum Style: Sendable { case info, warning, error, success }

    let message: String
    let style: Style
    let systemImage: String?

    public init(_ message: String, style: Style = .info, systemImage: String? = nil) {
        self.message = message
        self.style = style
        self.systemImage = systemImage
    }

    private var tint: Color {
        switch style {
        case .info: return Color(hex: 0x3B82C4)
        case .warning: return MamaColor.statusNeeds
        case .error: return MamaColor.statusUrgent
        case .success: return MamaColor.statusFed
        }
    }

    private var icon: String {
        if let systemImage { return systemImage }
        switch style {
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        case .success: return "checkmark.circle.fill"
        }
    }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(tint)
            Text(LocalizedStringKey(message))
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous).fill(tint.opacity(0.12)))
        .accessibilityElement(children: .combine)
    }
}

/// Kısa süreli bildirim bandı (AppRouter.Toast).
public struct ToastView: View {
    let toast: AppRouter.Toast

    public init(_ toast: AppRouter.Toast) {
        self.toast = toast
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            Text(LocalizedStringKey(toast.message))
                .font(MamaFont.subheadline.weight(.semibold))
                .foregroundStyle(MamaColor.onInk)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Capsule().fill(MamaColor.ink))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch toast.style {
        case .success: return "pawprint.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch toast.style {
        case .success: return MamaColor.statusFed
        case .info: return MamaColor.mint
        case .warning: return MamaColor.statusStale
        }
    }
}

/// Yükleniyor durumu.
public struct LoadingView: View {
    let title: String?

    public init(_ title: String? = nil) {
        self.title = title
    }

    public var body: some View {
        VStack(spacing: 12) {
            ProgressView().controlSize(.large)
            if let title {
                Text(LocalizedStringKey(title)).font(MamaFont.subheadline).foregroundStyle(MamaColor.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// "Mama koydum" sonrası kısa pati animasyonu (PRD 6.4). Haptik ile birlikte kullanılır:
/// `.sensoryFeedback(.success, trigger: value)`.
public struct PawBurstView: View {
    let trigger: Int
    @State private var animate = false

    public init(trigger: Int) {
        self.trigger = trigger
    }

    public var body: some View {
        ZStack {
            ForEach(0..<6, id: \.self) { index in
                let angle = Double(index) / 6 * 2 * .pi
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(MamaColor.statusFed)
                    .offset(x: animate ? cos(angle) * 70 : 0, y: animate ? sin(angle) * 70 : 0)
                    .scaleEffect(animate ? 1 : 0.2)
                    .opacity(animate ? 0 : 1)
            }
            Image(systemName: "pawprint.circle.fill")
                .font(.system(size: 64, weight: .bold))
                .foregroundStyle(MamaColor.statusFed)
                .scaleEffect(animate ? 1.0 : 0.6)
                .opacity(animate ? 0 : 1)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onChange(of: trigger) { _, _ in
            animate = false
            withAnimation(.easeOut(duration: 0.9)) { animate = true }
        }
    }
}

extension View {
    /// Üstte kısa süreli toast gösterir ve 2,5 sn sonra kapatır.
    public func mamaToast(_ toast: Binding<AppRouter.Toast?>) -> some View {
        overlay(alignment: .top) {
            if let value = toast.wrappedValue {
                ToastView(value)
                    .padding(.top, 8)
                    .padding(.horizontal, 20)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .task(id: value.id) {
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        withAnimation(.easeInOut) { toast.wrappedValue = nil }
                    }
                    .onTapGesture { withAnimation { toast.wrappedValue = nil } }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: toast.wrappedValue)
    }
}
#endif
