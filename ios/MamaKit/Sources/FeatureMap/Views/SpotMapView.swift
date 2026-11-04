#if canImport(UIKit)
import MapKit
import SwiftUI
import MamaCore
import MamaDesign

/// Tam ekran sokak haritası (FR-H1…H3, H6): kümelenmiş pinler, seçim, küme dokunuşunda yakınlaştırma,
/// uzun basınca o noktaya hızlı nokta ekleme.
struct SpotMapView: View {
    let model: MapViewModel
    @Binding var position: MapCameraPosition
    let onLongPress: (Coordinate) -> Void

    @State private var longPressHandled = false
    @State private var longPressCount = 0

    var body: some View {
        MapReader { proxy in
            // Seçim yalnızca pin butonundan: `selection:` binding'i aynı dokunuşu ikinci kez işlerdi.
            Map(position: $position) {
                UserAnnotation()
                ForEach(model.clusters) { cluster in
                    Annotation(annotationTitle(for: cluster), coordinate: cluster.coordinate.clCoordinate, anchor: .center) {
                        MapAnnotationContent(
                            cluster: cluster,
                            isSelected: isSelected(cluster),
                            now: model.now
                        ) {
                            select(cluster.id)
                        }
                    }
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .onMapCameraChange(frequency: .onEnd) { context in
                model.cameraDidChange(to: GeoBounds(context.region))
            }
            .simultaneousGesture(longPressGesture(proxy: proxy))
            .sensoryFeedback(.impact(weight: .medium), trigger: longPressCount)
        }
    }

    private func select(_ id: String?) {
        guard let cluster = model.handleAnnotationSelection(id) else { return }
        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(model.zoomBounds(for: cluster).mkRegion)
        }
    }

    /// MapContentBuilder kapanışında tip denetimini hafif tutmak için ayrı.
    private func isSelected(_ cluster: SpotCluster) -> Bool {
        guard cluster.isSingle, let spot = cluster.spots.first else { return false }
        return spot.id == model.selectedSpotId
    }

    private func annotationTitle(for cluster: SpotCluster) -> String {
        if cluster.isSingle, let spot = cluster.spots.first { return spot.title }
        return String(localized: "\(cluster.count) nokta")
    }

    /// iOS 17: uzun basma tamamlanınca ardından gelen sıfır mesafeli sürükleme parmağın konumunu verir.
    private func longPressGesture(proxy: MapProxy) -> some Gesture {
        LongPressGesture(minimumDuration: 0.5)
            .sequenced(before: DragGesture(minimumDistance: 0))
            .onChanged { value in
                guard !longPressHandled, case .second(true, let drag?) = value else { return }
                longPressHandled = true
                handleLongPress(at: drag.location, proxy: proxy)
            }
            .onEnded { value in
                defer { longPressHandled = false }
                guard !longPressHandled, case .second(true, let drag?) = value else { return }
                handleLongPress(at: drag.location, proxy: proxy)
            }
    }

    private func handleLongPress(at point: CGPoint, proxy: MapProxy) {
        guard let coordinate = proxy.convert(point, from: .local) else { return }
        longPressCount += 1
        onLongPress(Coordinate(coordinate))
    }
}

/// Tekil nokta pini veya küme rozeti. Dokununca seçer (kümede yakınlaştırır).
private struct MapAnnotationContent: View {
    let cluster: SpotCluster
    let isSelected: Bool
    let now: Date
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            if cluster.isSingle, let spot = cluster.spots.first {
                SpotPinView(spot: spot, isSelected: isSelected, now: now)
            } else {
                ClusterPinView(count: cluster.count, needsFoodCount: cluster.needsFoodCount, hasUrgentNeed: cluster.hasUrgentNeed)
            }
        }
        .buttonStyle(.plain)
        .frame(minWidth: MamaMetrics.minTapSize, minHeight: MamaMetrics.minTapSize)
        .contentShape(Circle())
        .accessibilityHint(cluster.isSingle ? Text("Nokta özetini gösterir") : Text("Yakınlaştırır"))
    }
}
#endif
