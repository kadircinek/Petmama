#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Raporla (`AppSheet.report`, PRD 9.1–9.2). Raporlar 24 saat içinde incelenir.
public struct ReportSheet: View {
    @State private var model: ReportViewModel
    @Environment(AppRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @FocusState private var detailsFocused: Bool

    public init(target: ReportTarget, targetId: UUID, services: AppServices) {
        _model = State(initialValue: ReportViewModel(target: target, targetId: targetId, services: services))
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(ReportViewModel.reasons, id: \.self) { reason in
                        reasonRow(reason)
                    }
                } header: {
                    Text(model.question)
                }

                if model.showsAnimalHarmWarning {
                    Section {
                        BannerView(ReportViewModel.animalHarmWarning, style: .error, systemImage: "phone.fill")
                    }
                    .listRowBackground(Color.clear)
                }

                Section {
                    TextField(String(localized: "Ne gördün? Kısaca anlat"), text: $model.details, axis: .vertical)
                        .lineLimit(3...6)
                        .focused($detailsFocused)
                } header: {
                    Text("Ayrıntı (isteğe bağlı)")
                } footer: {
                    Text(verbatim: "\(model.details.count)/\(ReportViewModel.maximumDetailsLength)")
                        .foregroundStyle(model.isDetailsTooLong ? MamaColor.statusUrgent : MamaColor.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                if model.offersBlock {
                    Section {
                        Toggle(String(localized: "Bu kullanıcıyı engelle"), isOn: $model.alsoBlock)
                            .tint(MamaColor.statusUrgent)
                    } footer: {
                        Text("Engellediğin kişinin içeriklerini görmezsin. Engeli Ayarlar'dan kaldırabilirsin.")
                    }
                }

                if let message = model.errorMessage {
                    Section { BannerView(message, style: .error) }
                        .listRowBackground(Color.clear)
                }

                Section {
                    Button(action: submit) {
                        if model.isSubmitting {
                            ProgressView().tint(MamaColor.onInk)
                        } else {
                            Text("Raporu gönder")
                        }
                    }
                    .buttonStyle(.mamaPrimary(systemImage: "paperplane.fill"))
                    .disabled(!model.canSubmit)
                } footer: {
                    Text("Raporun moderasyon ekibine gider ve 24 saat içinde incelenir. Kimliğin raporlanan kişiyle paylaşılmaz.")
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .mamaBackground()
            .navigationTitle(String(localized: "Raporla"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Vazgeç")) { dismiss() }
                }
            }
            .animation(.easeInOut(duration: 0.2), value: model.reason)
        }
        .interactiveDismissDisabled(model.isSubmitting)
        .sensoryFeedback(.success, trigger: model.didSubmit)
        .presentationDetents([.large])
    }

    private func reasonRow(_ reason: ReportReason) -> some View {
        let isSelected = model.reason == reason
        return Button {
            model.reason = reason
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon(for: reason))
                    .foregroundStyle(reason == .animalHarm ? MamaColor.statusUrgent : MamaColor.textSecondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(reason.label)
                    .foregroundStyle(MamaColor.textPrimary)
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? MamaColor.statusFed : MamaColor.stroke)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: MamaMetrics.minTapSize)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func icon(for reason: ReportReason) -> String {
        switch reason {
        case .inappropriate: return "eye.slash.fill"
        case .spam: return "nosign"
        case .wrongLocation: return "mappin.slash"
        case .animalHarm: return "exclamationmark.shield.fill"
        case .harassment: return "hand.raised.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    private func submit() {
        detailsFocused = false
        Task {
            guard await model.submit() else { return }
            router.showToast(model.completionMessage)
            dismiss()
        }
    }
}

#Preview {
    PreviewEnvironment { services in
        ReportSheet(target: .user, targetId: DemoData.emreId, services: services)
    }
}
#endif
