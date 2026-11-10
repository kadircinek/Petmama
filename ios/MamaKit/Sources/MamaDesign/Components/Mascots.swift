#if canImport(UIKit)
import SwiftUI
import MamaCore

// Maskot ikonları (D18): sevimli kedi ve köpek yüzleri. Çizimler bu modülün asset catalog'undadır
// (`Resources/Mascots.xcassets`, üretici: scripts/generate_mascots.py).

/// Kedi, köpek veya ikili maskot. İfade (`mood`) çoğunlukla nokta durumundan gelir.
public struct MascotView: View {
    private let assetName: String
    private let size: CGFloat

    /// Genel maskot: `MascotView(.duo, mood: .happy, size: 72)`
    public init(_ species: MascotSpecies, mood: MascotMood = .neutral, size: CGFloat) {
        self.assetName = species.assetName(mood: mood)
        self.size = size
    }

    /// Belirli tüy rengi.
    public init(coat: MascotCoat, mood: MascotMood = .neutral, size: CGFloat) {
        self.assetName = coat.assetName(mood: mood)
        self.size = size
    }

    /// Hayvanın renk tarifine göre seçilen maskot.
    public init(animal: Animal, mood: MascotMood = .neutral, size: CGFloat) {
        self.init(coat: animal.mascotCoat, mood: mood, size: size)
    }

    public var body: some View {
        Image(assetName, bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Nokta tipi ikonu: mama kabı, su kabı, kulübe, karışık.
public struct SpotTypeIcon: View {
    private let type: SpotType
    private let size: CGFloat

    public init(_ type: SpotType, size: CGFloat) {
        self.type = type
        self.size = size
    }

    private var assetName: String {
        switch type {
        case .food: return "spot-food"
        case .water: return "spot-water"
        case .shelter: return "spot-shelter"
        case .mixed: return "spot-mixed"
        }
    }

    public var body: some View {
        Image(assetName, bundle: .module)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Hayvanın fotoğrafı; fotoğraf yoksa pastel zeminde maskotu.
public struct AnimalAvatar: View {
    private let animal: Animal
    private let mood: MascotMood

    public init(animal: Animal, mood: MascotMood = .neutral) {
        self.animal = animal
        self.mood = mood
    }

    public var body: some View {
        if let url = animal.photoURLs.first {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                MamaColor.tileMint
                MascotView(animal: animal, mood: mood, size: side * 0.82)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// Noktanın fotoğrafı; fotoğraf yoksa durumuna göre ifadesi değişen maskot.
public struct SpotThumbnail: View {
    private let spot: Spot
    private let now: Date

    public init(spot: Spot, now: Date = Date()) {
        self.spot = spot
        self.now = now
    }

    public var body: some View {
        let status = spot.currentStatus(now: now)
        if let url = spot.photoURL {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    placeholder(status)
                }
            }
        } else {
            placeholder(status)
        }
    }

    private func placeholder(_ status: SpotStatus) -> some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack(alignment: .bottomTrailing) {
                status.color.opacity(0.16)
                MascotView(MascotSpecies(spot.species), mood: MascotMood(status: status), size: side * 0.84)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                if spot.type != .food {
                    SpotTypeIcon(spot.type, size: side * 0.36)
                        .padding(side * 0.03)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

#Preview("Maskotlar") {
    ScrollView {
        VStack(spacing: 16) {
            HStack {
                ForEach(MascotMood.allCases, id: \.self) { mood in
                    MascotView(.duo, mood: mood, size: 96)
                }
            }
            ForEach(MascotMood.allCases, id: \.self) { mood in
                HStack {
                    ForEach(MascotCoat.allCases, id: \.self) { coat in
                        MascotView(coat: coat, mood: mood, size: 34)
                    }
                }
            }
            HStack {
                ForEach(SpotType.allCases, id: \.self) { SpotTypeIcon($0, size: 56) }
            }
        }
        .padding()
    }
    .mamaBackground()
}
#endif
