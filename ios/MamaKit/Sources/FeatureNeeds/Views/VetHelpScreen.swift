#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Acil veteriner bilgisi (FR-I4). Rota: `AppRoute.vetHelp(needId:)`.
/// Uygulama tıbbi tavsiye vermez; en yakın klinikleri ve resmi kurumları gösterir (PRD 9.1).
public struct VetHelpScreen: View {
    @State private var model: VetHelpViewModel
    @Environment(LocationStore.self) private var location
    @Environment(\.openURL) private var openURL

    public init(needId: UUID?, services: AppServices) {
        _model = State(initialValue: VetHelpViewModel(needId: needId, services: services, searcher: MapKitVetClinicSearch()))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                BannerView(
                    String(localized: "Mama Haritası tıbbi tavsiye vermez. Hayvanın durumu için bir veterinere danış."),
                    style: .warning,
                    systemImage: "cross.case.fill"
                )
                if let need = model.need {
                    needSummary(need)
                }
                clinicsSection
                authoritiesSection
            }
            .padding(MamaMetrics.screenPadding)
        }
        .mamaBackground()
        .navigationTitle("Acil veteriner bilgisi")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .refreshable { await load() }
    }

    private func needSummary(_ need: Need) -> some View {
        HStack(spacing: 10) {
            TagChip(need.type.label, systemImage: need.type.systemImage, style: need.isUrgent ? .danger : .neutral)
            Text([need.animalName, need.spotTitle].compactMap { $0 }.joined(separator: " · "))
                .font(MamaFont.subheadline)
                .foregroundStyle(MamaColor.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var clinicsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "En yakın veteriner klinikleri"))
            if model.isSearching && model.clinics.isEmpty {
                ProgressView(String(localized: "Yakındaki veterinerler aranıyor…"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 24)
            } else if model.clinics.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Text(model.searchFailed
                         ? String(localized: "Şu an arama yapamadık. Bağlantın gelince tekrar dener misin?")
                         : String(localized: "Yakında veteriner kliniği bulamadık."))
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                    Button(String(localized: "Haritalar'da ara")) {
                        if let url = VetHelpViewModel.mapsSearchURL(near: model.searchCenter(user: location.coordinate)) {
                            openURL(url)
                        }
                    }
                    .buttonStyle(.mamaSecondary(systemImage: "map.fill"))
                }
                .mamaCard()
            } else {
                ForEach(model.clinics) { clinic in
                    VetClinicRow(clinic: clinic, callURL: VetHelpViewModel.telURL(clinic.phone)) {
                        clinic.openWalkingDirections()
                    }
                }
            }
        }
    }

    private var authoritiesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(String(localized: "Resmi kurumlar"))
            AuthorityCard(
                title: String(localized: "Belediyenin Beyaz Masa hattı: Alo 153"),
                detail: String(localized: "Sokak hayvanları için belediyenin veteriner birimine Beyaz Masa üzerinden ulaşabilirsin."),
                systemImage: "building.columns.fill",
                tint: MamaColor.tileBlue,
                callTitle: String(localized: "153'ü ara")
            ) {
                call("153")
            }
            AuthorityCard(
                title: String(localized: "Hayvana kasıtlı zarar veya zehirleme şüphesinde 112'yi ara"),
                detail: String(localized: "Gördüklerini not al. Uygulamada da “Raporla → Şüpheli durum” ile bildirebilirsin."),
                systemImage: "exclamationmark.shield.fill",
                tint: MamaColor.tilePeach,
                callTitle: String(localized: "112'yi ara")
            ) {
                call("112")
            }
        }
    }

    private func load() async {
        var coordinate = location.coordinate
        if coordinate == nil { coordinate = await location.refresh() }
        await model.load(near: coordinate)
    }

    private func call(_ number: String) {
        if let url = VetHelpViewModel.telURL(number) { openURL(url) }
    }
}

struct VetClinicRow: View {
    let clinic: VetClinic
    let callURL: URL?
    let onDirections: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cross.case.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(MamaColor.tilePeach))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(clinic.name)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                    if let address = clinic.address {
                        Text(address)
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                            .lineLimit(2)
                    }
                    if let distance = clinic.distanceMeters {
                        Label(MamaFormat.distance(distance), systemImage: "location.fill")
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .combine)
            HStack(spacing: 10) {
                if let callURL {
                    Button(String(localized: "Ara")) { openURL(callURL) }
                        .buttonStyle(.mamaSecondary(tint: MamaColor.statusFed, systemImage: "phone.fill"))
                }
                Button(String(localized: "Yol tarifi"), action: onDirections)
                    .buttonStyle(.mamaPrimary(systemImage: "figure.walk"))
            }
        }
        .mamaCard(padding: 14)
    }
}

struct AuthorityCard: View {
    let title: String
    let detail: String
    let systemImage: String
    let tint: Color
    let callTitle: String
    let onCall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(MamaColor.textPrimary)
                    .frame(width: 44, height: 44)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(tint))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(detail)
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
            Button(callTitle, action: onCall)
                .buttonStyle(.mamaSecondary(tint: MamaColor.statusUrgent, systemImage: "phone.fill"))
        }
        .mamaCard(padding: 14)
    }
}

#Preview {
    PreviewEnvironment { services in
        VetHelpScreen(needId: DemoData.id(5, 1), services: services)
    }
}
#endif
