#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

/// Koruyucu ol / günleri düzenle / koruyuculuktan çık (FR-N4).
struct GuardianScheduleSheet: View {
    let isGuardian: Bool
    /// `nil` koruyuculuktan çıkar.
    let onSave: (Set<Weekday>?) -> Void

    @State private var schedule: Set<Weekday>
    @Environment(\.dismiss) private var dismiss

    init(initial: Set<Weekday>, isGuardian: Bool, onSave: @escaping (Set<Weekday>?) -> Void) {
        self.isGuardian = isGuardian
        self.onSave = onSave
        _schedule = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Koruyucular noktayı sahiplenir: düzenli mama ve su koyar, kapları temiz tutar. Hangi günler uğrarsın?")
                        .font(MamaFont.subheadline)
                        .foregroundStyle(MamaColor.textSecondary)
                    FlowLayout(spacing: 8) {
                        ForEach(Weekday.allCases, id: \.self) { day in
                            SelectableChip(day.localizedShortName, isSelected: schedule.contains(day)) {
                                if schedule.contains(day) {
                                    schedule.remove(day)
                                } else {
                                    schedule.insert(day)
                                }
                            }
                        }
                    }
                    if schedule.isEmpty {
                        Text("En az bir gün seç.")
                            .font(MamaFont.caption)
                            .foregroundStyle(MamaColor.textSecondary)
                    }
                    Button(isGuardian ? String(localized: "Günleri kaydet") : String(localized: "Koruyucu ol")) {
                        onSave(schedule)
                        dismiss()
                    }
                    .buttonStyle(.mamaPrimary(systemImage: "checkmark"))
                    .disabled(schedule.isEmpty)
                    if isGuardian {
                        Button("Koruyuculuktan çık", role: .destructive) {
                            onSave(nil)
                            dismiss()
                        }
                        .buttonStyle(.mamaSecondary(tint: MamaColor.statusUrgent, systemImage: "xmark.circle.fill"))
                    }
                }
                .padding(20)
            }
            .mamaBackground()
            .navigationTitle(isGuardian ? Text("Koruyuculuk günlerin") : Text("Koruyucu ol"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Vazgeç") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    GuardianScheduleSheet(initial: [.monday, .friday], isGuardian: true) { _ in }
}
#endif
