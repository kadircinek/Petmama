#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// İhtiyaç fotoğrafları. Yaralı/hasta hayvan içerebilecek tiplerde bulanık (PRD 9.2).
struct NeedPhotoHeader: View {
    let need: Need

    var body: some View {
        if need.photoURLs.isEmpty {
            ZStack {
                need.type.tileColor
                Image(systemName: need.type.systemImage)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
            .accessibilityHidden(true)
        } else {
            TabView {
                ForEach(need.photoURLs, id: \.self) { url in
                    photo(url)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                }
            }
            .tabViewStyle(.page(indexDisplayMode: need.photoURLs.count > 1 ? .always : .never))
            .frame(maxWidth: .infinity)
            .frame(height: 260)
            .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.cornerRadius, style: .continuous))
        }
    }

    @ViewBuilder
    private func photo(_ url: URL) -> some View {
        if need.mayContainSensitiveImagery {
            SensitivePhoto(url: url)
        } else {
            AsyncPhoto(url: url, placeholderSystemImage: need.type.systemImage)
        }
    }
}

/// Bağlı hayvan / nokta satırı.
struct NeedLinkRow: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let photoURL: URL?

    var body: some View {
        HStack(spacing: 12) {
            AsyncPhoto(url: photoURL, placeholderSystemImage: systemImage)
                .frame(width: 48, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(MamaFont.headline)
                    .foregroundStyle(MamaColor.textPrimary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.bold))
                .foregroundStyle(MamaColor.textSecondary)
                .accessibilityHidden(true)
        }
        .mamaCard(padding: 12)
        .accessibilityElement(children: .combine)
    }
}

/// açıldı → üstlenildi → çözüldü zaman çizelgesi (FR-I2).
struct NeedTimelineView: View {
    let steps: [NeedTimelineStep]
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(String(localized: "Durum"))
                .padding(.bottom, 12)
            ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    VStack(spacing: 0) {
                        Image(systemName: step.isDone ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(step.isDone ? MamaColor.statusFed : MamaColor.statusUnknown)
                        if index < steps.count - 1 {
                            Rectangle()
                                .fill(step.isDone ? MamaColor.statusFed : MamaColor.stroke)
                                .frame(width: 2)
                                .frame(minHeight: 26)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title(step.kind))
                            .font(MamaFont.headline)
                            .foregroundStyle(step.isDone ? MamaColor.textPrimary : MamaColor.textSecondary)
                        if let detail = step.detail {
                            Text(detail)
                                .font(MamaFont.subheadline)
                                .foregroundStyle(MamaColor.textSecondary)
                        }
                        if let date = step.date {
                            Text(MamaFormat.relative(date, now: now))
                                .font(MamaFont.caption)
                                .foregroundStyle(MamaColor.textSecondary)
                        }
                    }
                    .padding(.bottom, 14)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                .accessibilityValue(step.isDone ? String(localized: "tamamlandı") : String(localized: "bekliyor"))
            }
        }
        .mamaCard()
    }

    private func title(_ kind: NeedTimelineStep.Kind) -> String {
        switch kind {
        case .opened: return String(localized: "İhtiyaç açıldı")
        case .claimed: return String(localized: "Üstlenildi")
        case .resolved: return String(localized: "Çözüldü")
        }
    }
}
#endif
