# iOS kodlama kuralları (MamaKit)

Bu doküman feature modüllerini yazan herkes için ortak sözleşmedir. Mimari: PRD 7.1 (Swift + SwiftUI, iOS 17+,
MVVM + feature modülleri). Xcode 16+ ile derlenir, paket Swift 5 dil modunda (`swift-tools-version: 5.10`).

## Modüller ve bağımlılık kuralı

```
MamaCore  ←  MamaDesign  ←  Feature*  ←  AppFeature  ←  App (Xcode hedefi)
            MamaSupabase / MamaPersistence  ←  AppFeature
```
- Feature modülleri **birbirini import etmez**. Başka bir feature'ın ekranına gitmek için `AppRoute`
  (push) veya `AppSheet` (modal) kullanılır; rotayı `AppFeature` çözer.
- `MamaCore` ve `MamaDesign` paylaşılan modüllerdir. Feature yazarken bunları **değiştirme**; eksik bir şey
  varsa modülün içinde `private`/`internal` yardımcı yaz ve raporda öner.

## Dosya düzeni (her feature)

```
Sources/FeatureX/
  ViewModels/   ← yalnızca Foundation + Observation + MamaCore. SwiftUI/UIKit/MapKit YOK. Linux'ta derlenir.
  Views/        ← her dosya baştan sona `#if canImport(UIKit)` … `#endif` içinde.
Tests/FeatureTests/FeatureX*Tests.swift   ← ViewModel testleri (Linux'ta çalışır)
```

## ViewModel kalıbı

```swift
import Foundation
import Observation
import MamaCore

@MainActor
@Observable
public final class SpotDetailViewModel {
    public private(set) var spot: Spot?
    public private(set) var isLoading = false
    public var error: MamaError?

    @ObservationIgnored private let services: AppServices
    @ObservationIgnored private let spotId: UUID

    public init(spotId: UUID, services: AppServices) { … }

    /// Konum, oturum gibi ortam değerleri parametre olarak gelir (VM ortamı okumaz).
    public func load(near coordinate: Coordinate?) async { … }
}
```
- Hatalar `MamaError.classify(error)` ile sınıflanır; kullanıcıya `error.userMessage` gösterilir.
- Zaman için `services.now()` kullan (testler sabit zaman verir).
- Konum gereken işlemler `Coordinate?` parametresi alır; görünüm `LocationStore`'dan geçirir.

## Ekran kalıbı

```swift
#if canImport(UIKit)
import SwiftUI
import MamaCore
import MamaDesign

public struct SpotDetailScreen: View {
    @State private var model: SpotDetailViewModel
    @Environment(AppRouter.self) private var router
    @Environment(SessionStore.self) private var session
    @Environment(LocationStore.self) private var location

    public init(spotId: UUID, services: AppServices) {
        _model = State(initialValue: SpotDetailViewModel(spotId: spotId, services: services))
    }

    public var body: some View {
        ScrollView { … }
            .mamaBackground()
            .navigationTitle(…)
            .task { await model.load(near: location.coordinate) }
            .refreshable { await model.load(near: location.coordinate) }
    }
}

#Preview {
    PreviewEnvironment { services in SpotDetailScreen(spotId: DemoData.id(2, 1), services: services) }
}
#endif
```
- **Gezinme:** Sekme köklerini `AppFeature` bir `NavigationStack` içine koyar ve
  `.navigationDestination(for: AppRoute.self)` ile çözer. Feature ekranları kendi `NavigationStack`'ini
  **açmaz** (yalnızca sheet içeriği kendi `NavigationStack`'ini açar). İtme: `NavigationLink(value: AppRoute.spot(id))`
  veya `router.push(.spot(id))`.
- **Modallar:** `router.present(.checkIn(spotId:kind:), session: session)` — oturum gerektirenler önce giriş
  ekranını açar (FR-P1). Sheet içinden kapatmak: `@Environment(\.dismiss)`.
- **Geri bildirim:** `router.showToast("Teşekkürler! …")`, başarıda `.sensoryFeedback(.success, trigger:)`.
- **Ortam:** `@Environment(\.services)` da mevcut ama tercihen init'te gelen `services` kullanılır.

## Tasarım (MamaDesign)
`mamaBackground()`, `mamaCard()`, `MamaFont.*`, `MamaColor.*`, `.buttonStyle(.mamaPrimary)`, `.mamaFed`,
`.mamaSecondary`, `.mamaNeedsFood`, `.mamaCircle`, `TagChip`, `StatusBadge`, `SelectableChip`, `FlowLayout`,
`SpotPinView`, `ClusterPinView`, `StatusLegend`, `AsyncPhoto`, `SensitivePhoto`, `AvatarView`,
`PhotoInputButton`, `PhotoThumbnail`, `SectionHeader`, `QuickActionTile`, `StatsStrip`, `ProgressSegments`,
`PillSegmentedControl`, `ChoiceCard`, `InfoRow`, `EmptyStateView`, `BannerView`, `LoadingView`, `PawBurstView`,
`SpotCardView`, `NeedCardView`, `AnimalChipCard`, `PreviewEnvironment`. Maskotlar (D18): `MascotView(.cat/.dog/.duo, mood:, size:)`,
`MascotView(animal:)`, `SpotTypeIcon`, `AnimalAvatar`, `SpotThumbnail`, `EmptyStateView(mascot:mood:title:…)`. Enum etiketleri: `.label`,
`.systemImage`, `.color`, `.explanation`, `.tileColor` (Labels/DomainLabels.swift).

## Metin ve ton
- Kaynak dil **Türkçe**. `Text("Mama koydum")` doğrudan; String değerler `String(localized: "…")`.
  İngilizce çeviriler String Catalog'a sonradan eklenir.
- Ton sıcak, suçlayıcı değil: "Aç kaldı" değil **"Mama bekliyor"**. Boş durum: "Bu sokağın ilk besleyicisi sen ol".
- Uygulama tıbbi tavsiye vermez (FR-I4).

## Erişilebilirlik (PRD 6.1)
Dynamic Type (`MamaFont` metin stilleriyle ölçeklenir), durumlar renk + ikon + metin, VoiceOver etiketleri,
en az 44 pt dokunma alanı, açık/koyu tema (renkler `MamaColor`'dan).

## API sınırı: yalnızca iOS 17
Kullan: `Map(position:selection:)` + `Annotation`/`Marker`, `MapCameraPosition`, `.onMapCameraChange`,
`MapReader` + `MapProxy.convert(_:from:)`, `.mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))`,
`.mapControls`, `@Observable`, `.onChange(of:) { old, new in }`, `.sensoryFeedback`, `ContentUnavailableView`,
`.presentationDetents`, `.scrollTargetBehavior`, `PhotosPicker`, `SignInWithAppleButton`.
Kullanma (iOS 18+): `Tab` tipi, `@Entry`, `.onScrollGeometryChange`, `.presentationSizing`, `MapCameraPosition` dışı yeni harita API'leri, `#Preview` traits'leri.

## Linux doğrulaması
```
SCRATCH=/tmp/mama-build-<sen> scripts/linux-swift.sh build --target FeatureX
SCRATCH=/tmp/mama-build-<sen> scripts/linux-swift.sh test --filter FeatureTests.<SınıfAdı>
```
- Linux'ta XCTest assert'lerinin içinde `await` olmaz (önce yerel değişkene ata).
- `@MainActor` test sınıflarında test metodları `async` olmalı.
- SwiftUI dosyaları Linux'ta derlenmez; o yüzden iOS 17 SwiftUI API imzalarını dikkatle kullan, emin olmadığın
  API'yi kullanma.
