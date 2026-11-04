// swift-tools-version: 5.10
import PackageDescription

// Mama Haritası modül yapısı (PRD 7.1: MVVM + feature modülleri).
//
//   MamaCore        → Domain modelleri, iş kuralları, repository protokolleri, demo backend,
//                     router/oturum/konum store'ları. Saf Swift; Linux'ta derlenir ve test edilir.
//   MamaDesign      → Tasarım sistemi (renkler, tipografi, bileşenler). SwiftUI.
//   MamaSupabase    → Repository protokollerinin Supabase implementasyonu.
//   MamaPersistence → SwiftData çevrimdışı önbellek + check-in kuyruğu.
//   Feature*        → Ekranlar + ViewModel'ler. ViewModel'ler Linux'ta derlenir;
//                     SwiftUI dosyaları `#if canImport(SwiftUI)` ile sarılıdır.
//   AppFeature      → Kompozisyon kökü: tab bar, rota çözümleme, servis kurulumu.
let package = Package(
    name: "MamaKit",
    defaultLocalization: "tr",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MamaCore", targets: ["MamaCore"]),
        .library(name: "MamaDesign", targets: ["MamaDesign"]),
        .library(name: "MamaSupabase", targets: ["MamaSupabase"]),
        .library(name: "MamaPersistence", targets: ["MamaPersistence"]),
        .library(name: "AppFeature", targets: ["AppFeature"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift.git", from: "2.30.0"),
    ],
    targets: [
        .target(name: "MamaCore"),
        .target(name: "MamaDesign", dependencies: ["MamaCore"]),
        .target(
            name: "MamaSupabase",
            dependencies: ["MamaCore", .product(name: "Supabase", package: "supabase-swift")]
        ),
        .target(name: "MamaPersistence", dependencies: ["MamaCore"]),

        .target(name: "FeatureOnboarding", dependencies: ["MamaCore", "MamaDesign"]),
        .target(name: "FeatureMap", dependencies: ["MamaCore", "MamaDesign"]),
        .target(name: "FeatureSpots", dependencies: ["MamaCore", "MamaDesign"]),
        .target(name: "FeatureAnimals", dependencies: ["MamaCore", "MamaDesign"]),
        .target(name: "FeatureNeeds", dependencies: ["MamaCore", "MamaDesign"]),
        .target(name: "FeatureDonate", dependencies: ["MamaCore", "MamaDesign"]),
        .target(name: "FeatureProfile", dependencies: ["MamaCore", "MamaDesign"]),

        .target(
            name: "AppFeature",
            dependencies: [
                "MamaCore", "MamaDesign", "MamaSupabase", "MamaPersistence",
                "FeatureOnboarding", "FeatureMap", "FeatureSpots", "FeatureAnimals",
                "FeatureNeeds", "FeatureDonate", "FeatureProfile",
            ]
        ),

        .testTarget(name: "MamaCoreTests", dependencies: ["MamaCore"]),
        .testTarget(
            name: "MamaSupabaseTests",
            dependencies: ["MamaCore", "MamaSupabase", .product(name: "Supabase", package: "supabase-swift")]
        ),
        .testTarget(name: "AppFeatureTests", dependencies: ["MamaCore", "AppFeature"]),
        .testTarget(
            name: "FeatureTests",
            dependencies: [
                "MamaCore", "FeatureOnboarding", "FeatureMap", "FeatureSpots", "FeatureAnimals",
                "FeatureNeeds", "FeatureDonate", "FeatureProfile",
            ]
        ),
    ]
)
