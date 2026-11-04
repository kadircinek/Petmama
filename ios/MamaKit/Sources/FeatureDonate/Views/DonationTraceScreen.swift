#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// "Bağışım nereye gitti?" (ekran 19). Rota: `AppRoute.donationTrace`.
/// Teslim kanıtı ve bildirim v1.1'de (D13); adımlar açıklama + "v1.1'de" durumuyla gösterilir.
public struct DonationTraceScreen: View {
    @State private var model: DonationTraceViewModel

    public init(services: AppServices) {
        _model = State(initialValue: DonationTraceViewModel(services: services))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Bağışın ortak dernek aracılığıyla mamaya dönüşür. Yolculuğu adım adım burada izleyeceksin.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
                overviewCard
                timeline
                BannerView(
                    String(localized: "Şimdilik dernek aylık toplamı paylaşıyor; sayaç bu toplamla güncellenir. Teslim fotoğrafları ve bildirimler v1.1'de geliyor."),
                    style: .info
                )
            }
            .padding(MamaMetrics.screenPadding)
        }
        .mamaBackground()
        .navigationTitle("Bağışım nereye gitti?")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
    }

    @ViewBuilder
    private var overviewCard: some View {
        if let kilograms = model.kilogramsText {
            VStack(alignment: .leading, spacing: 6) {
                Text(model.monthTitle ?? String(localized: "Bu ay"))
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.textSecondary)
                Text("\(kilograms) mama dağıtıldı")
                    .font(MamaFont.title2)
                    .foregroundStyle(MamaColor.textPrimary)
                if let donors = model.donorCountText {
                    Label(donors, systemImage: "person.2.fill")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .mamaCard()
            .accessibilityElement(children: .combine)
        } else if !model.hasLoaded {
            ProgressView().frame(maxWidth: .infinity)
        }
    }

    private var timeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(model.steps.enumerated()), id: \.element.id) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        Image(systemName: step.systemImage)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(step.isAvailable ? MamaColor.onInk : MamaColor.textSecondary)
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(step.isAvailable ? MamaColor.ink : MamaColor.cardSecondary))
                        if index < model.steps.count - 1 {
                            Rectangle()
                                .fill(MamaColor.stroke)
                                .frame(width: 2)
                                .frame(minHeight: 28)
                        }
                    }
                    .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Text(step.title)
                                .font(MamaFont.headline)
                                .foregroundStyle(MamaColor.textPrimary)
                            if !step.isAvailable {
                                TagChip(String(localized: "v1.1'de"), style: .info)
                            }
                        }
                        Text(step.detail)
                            .font(MamaFont.subheadline)
                            .foregroundStyle(MamaColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 18)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .mamaCard()
    }
}

#Preview {
    PreviewEnvironment { services in
        DonationTraceScreen(services: services)
    }
}
#endif
