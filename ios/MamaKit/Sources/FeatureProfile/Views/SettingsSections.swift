#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Bildirim tercihleri (ekran 23). Değişiklikler `SettingsScreen` tarafından kısa gecikmeyle kaydedilir.
struct NotificationPreferencesSection: View {
    @Bindable var model: SettingsViewModel

    var body: some View {
        Section {
            Picker(selection: $model.preferences.radiusMeters) {
                ForEach(SettingsViewModel.radiusOptions, id: \.self) { meters in
                    Text(SettingsViewModel.radiusLabel(meters)).tag(meters)
                }
            } label: {
                Label(String(localized: "Bildirim yarıçapı"), systemImage: "scope")
            }
            Toggle(isOn: $model.preferences.needFoodNearby) {
                rowLabel(String(localized: "Yakındaki \"mama gerekli\""), detail: String(localized: "Çevrende bir kap boşalınca"), icon: "fork.knife")
            }
            Toggle(isOn: $model.preferences.followedUpdates) {
                rowLabel(String(localized: "Takip edilen noktalar"), detail: String(localized: "Takip ettiğin nokta ve hayvanlardaki değişiklikler"), icon: "heart.fill")
            }
            Toggle(isOn: $model.preferences.guardianAlerts) {
                rowLabel(String(localized: "Koruyucu uyarıları"), detail: String(localized: "Koruyucusu olduğun nokta uzun süre beslenmezse"), icon: "shield.lefthalf.filled")
            }
            Toggle(isOn: $model.preferences.communityUpdates) {
                rowLabel(String(localized: "Mahalle"), detail: String(localized: "Paylaşımına yorum gelince veya biri \"Ben bakarım\" deyince"), icon: "person.2.fill")
            }
        } header: {
            Text("Bildirimler")
        } footer: {
            Text(SettingsViewModel.dailyLimitNote)
        }
        .tint(MamaColor.statusFed)

        Section {
            hourPicker(String(localized: "Başlangıç"), selection: $model.preferences.quietStartHour, icon: "moon.fill")
            hourPicker(String(localized: "Bitiş"), selection: $model.preferences.quietEndHour, icon: "sun.max.fill")
        } header: {
            Text("Sessiz saatler")
        } footer: {
            Text(model.quietHoursSummary)
        }
    }

    private func hourPicker(_ title: String, selection: Binding<Int>, icon: String) -> some View {
        Picker(selection: selection) {
            ForEach(SettingsViewModel.hourOptions, id: \.self) { hour in
                Text(verbatim: SettingsViewModel.hourLabel(hour)).tag(hour)
            }
        } label: {
            Label(title, systemImage: icon)
        }
        .pickerStyle(.menu)
    }

    private func rowLabel(_ title: String, detail: String, icon: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(MamaFont.caption).foregroundStyle(MamaColor.textSecondary)
            }
        } icon: {
            Image(systemName: icon)
        }
    }
}

/// Engellenen kullanıcılar ve engeli kaldırma (PRD 9.2).
struct BlockedUsersSection: View {
    let model: SettingsViewModel

    var body: some View {
        Section {
            if model.blockedUsers.isEmpty {
                Text("Engellediğin kimse yok.")
                    .font(MamaFont.subheadline)
                    .foregroundStyle(MamaColor.textSecondary)
            } else {
                ForEach(model.blockedUsers) { user in
                    HStack(spacing: 12) {
                        AvatarView(name: user.displayName, size: 36)
                        Text(user.displayName)
                            .font(MamaFont.body)
                        Spacer()
                        Button(String(localized: "Engeli kaldır")) {
                            Task { await model.unblock(user) }
                        }
                        .buttonStyle(.borderless)
                        .font(MamaFont.subheadline.weight(.semibold))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } header: {
            Text("Engellenen kullanıcılar")
        } footer: {
            Text("Engellediğin kişilerin içeriklerini görmezsin; onlar da senin bildirimlerini tetiklemez.")
        }
    }
}

/// Yasal metin satırı: URL tanımlıysa Safari'de, değilse uygulama içi özet.
struct LegalLinkRow: View {
    let title: String
    let systemImage: String
    let url: URL?

    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router

    init(title: String, systemImage: String, url: URL?) {
        self.title = title
        self.systemImage = systemImage
        self.url = url
    }

    var body: some View {
        Button {
            if let url { openURL(url) } else { router.push(.privacy) }
        } label: {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(MamaColor.textPrimary)
                Spacer()
                Image(systemName: url == nil ? "chevron.right" : "arrow.up.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(MamaColor.textSecondary)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
#endif
