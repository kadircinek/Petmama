#if canImport(UIKit)
import SwiftUI
import UIKit
import MamaCore
import MamaDesign

/// "Mama koydum" / "Mama gerekli" check-in sheet'i (FR-C1…C5, FR-H8).
public struct CheckInSheet: View {
    @State private var model: CheckInViewModel
    @State private var successTrigger = 0

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(AppRouter.self) private var router
    @Environment(LocationStore.self) private var location

    public init(spotId: UUID, kind: CheckInKind, services: AppServices) {
        _model = State(initialValue: CheckInViewModel(spotId: spotId, kind: kind, services: services))
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if let spot = model.spot {
                        CheckInSpotHeader(spot: spot, now: Date())
                    } else if let error = model.error {
                        BannerView(error.userMessage, style: .error)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                    if model.isRequestFlow {
                        requestKindPicker
                    } else {
                        giveKindPicker
                        if model.asksAmount { amountPicker }
                        photoSection
                    }
                    locationSection
                    if let result = model.result, !result.dismissesSheet {
                        BannerView(result.message, style: .warning)
                    }
                }
                .padding(20)
            }
            .mamaBackground()
            .navigationTitle(model.isRequestFlow ? Text("Mama gerekli") : Text("Mama koydum"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) { submitBar }
            .overlay { PawBurstView(trigger: successTrigger) }
        }
        .sensoryFeedback(.success, trigger: successTrigger)
        .task {
            await model.load()
            model.updateLocation(await location.refresh())
        }
    }

    // MARK: - Bölümler

    private var giveKindPicker: some View {
        HStack(spacing: 8) {
            ForEach(model.availableKinds, id: \.self) { kind in
                SelectableChip(kind.label, systemImage: kind.systemImage, isSelected: model.kind == kind) {
                    model.kind = kind
                }
            }
        }
    }

    private var requestKindPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ne gerekiyor?")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
            ForEach(model.availableKinds, id: \.self) { kind in
                ChoiceCard(kind.label, systemImage: kind.systemImage, tint: MamaColor.tilePeach, isSelected: model.kind == kind) {
                    model.kind = kind
                }
            }
            Text("Yakındaki gönüllülere haber vereceğiz. Biri mama koyunca bildirim kapanır.")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
        }
    }

    private var amountPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Ne kadar koydun? (isteğe bağlı)")
                .font(MamaFont.headline)
                .foregroundStyle(MamaColor.textPrimary)
            HStack(spacing: 8) {
                ForEach(FoodAmount.allCases, id: \.self) { amount in
                    SelectableChip(amount.label, isSelected: model.amount == amount) {
                        model.toggleAmount(amount)
                    }
                }
            }
        }
    }

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                PhotoInputButton { data in
                    model.photoData = data
                } label: {
                    Label(model.photoData == nil ? String(localized: "Fotoğraf ekle") : String(localized: "Fotoğrafı değiştir"), systemImage: "camera.fill")
                        .font(MamaFont.headline)
                        .foregroundStyle(MamaColor.textPrimary)
                        .padding(.horizontal, 18)
                        .frame(minHeight: 48)
                        .background(Capsule().fill(MamaColor.card))
                        .overlay(Capsule().strokeBorder(MamaColor.stroke, lineWidth: 1))
                }
                if let data = model.photoData {
                    PhotoThumbnail(data: data) { model.photoData = nil }
                }
            }
            Label("Fotoğraflı check-in daha çok puan kazandırır", systemImage: "sparkles")
                .font(MamaFont.caption)
                .foregroundStyle(MamaColor.textSecondary)
            if model.photoUploadFailed {
                Text("Fotoğraf yüklenemedi; check-in fotoğrafsız gönderildi.")
                    .font(MamaFont.caption)
                    .foregroundStyle(MamaColor.statusNeeds)
            }
        }
    }

    @ViewBuilder
    private var locationSection: some View {
        switch location.authorization {
        case .denied:
            VStack(alignment: .leading, spacing: 10) {
                BannerView(
                    String(localized: "Konum izni kapalı. Sahte check-in'leri önlemek için noktaya yakın olduğunu doğrulamamız gerekiyor."),
                    style: .warning,
                    systemImage: "location.slash.fill"
                )
                Button("Ayarları aç") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                }
                .buttonStyle(.mamaSecondary(systemImage: "gearshape.fill"))
            }
        case .notDetermined:
            VStack(alignment: .leading, spacing: 10) {
                BannerView(
                    String(localized: "Check-in için konumuna bir kez bakmamız gerekiyor. Konumun kaydedilmez."),
                    style: .info,
                    systemImage: "location.fill"
                )
                Button("Konuma izin ver") {
                    Task {
                        await location.requestAuthorization()
                        model.updateLocation(await location.refresh())
                    }
                }
                .buttonStyle(.mamaSecondary(systemImage: "location.fill"))
            }
        case .authorized:
            if let message = model.precheckMessage {
                VStack(alignment: .leading, spacing: 10) {
                    BannerView(message, style: bannerStyle, systemImage: model.isTooFar ? "figure.walk" : nil)
                    if model.isTooFar || model.userCoordinate == nil {
                        Button("Konumumu yenile") {
                            Task { model.updateLocation(await location.refresh()) }
                        }
                        .buttonStyle(.mamaSecondary(systemImage: "arrow.clockwise"))
                    }
                }
            }
        }
    }

    private var bannerStyle: BannerView.Style {
        switch model.precheckTone {
        case .ok: return .success
        case .info: return .info
        case .warning: return .warning
        }
    }

    private var submitBar: some View {
        Button(action: submit) {
            if model.isSubmitting {
                ProgressView().tint(MamaColor.onInk)
            } else {
                Text(model.isRequestFlow ? String(localized: "Mama gerekli diye bildir") : model.kind.label)
            }
        }
        .buttonStyle(model.isRequestFlow
            ? PrimaryPillButtonStyle(accent: MamaColor.statusNeeds, systemImage: "exclamationmark")
            : PrimaryPillButtonStyle(accent: MamaColor.statusFed, systemImage: "pawprint.fill"))
        .disabled(!model.canSubmit)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }

    private func submit() {
        Task {
            let user = await location.refresh()
            let result = await model.submit(user: user)
            guard result.dismissesSheet else { return }
            if result.isSuccess { successTrigger += 1 }
            router.showToast(result.message, style: result.toastStyle)
            try? await Task.sleep(nanoseconds: result.isSuccess ? 900_000_000 : 300_000_000)
            dismiss()
        }
    }
}

/// Sheet başındaki nokta özeti.
private struct CheckInSpotHeader: View {
    let spot: Spot
    let now: Date

    var body: some View {
        let status = spot.currentStatus(now: now)
        HStack(spacing: 14) {
            AsyncPhoto(url: spot.photoURL, placeholderSystemImage: spot.type.systemImage, placeholderTint: status.color)
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                Text(spot.title)
                    .font(MamaFont.title3)
                    .foregroundStyle(MamaColor.textPrimary)
                StatusBadge(status: status, hasUrgentNeed: spot.hasUrgentNeed)
            }
            Spacer(minLength: 0)
        }
        .mamaCard(padding: 12)
    }
}

#Preview {
    PreviewEnvironment { services in
        Color.clear.sheet(isPresented: .constant(true)) {
            CheckInSheet(spotId: DemoData.id(2, 6), kind: .fed, services: services)
        }
    }
}
#endif
