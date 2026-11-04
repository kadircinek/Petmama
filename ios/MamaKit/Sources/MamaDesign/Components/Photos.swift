#if canImport(UIKit)
import PhotosUI
import SwiftUI
import UIKit
import MamaCore

/// Uzak fotoğraf; yüklenemezse ikonlu pastel yer tutucu.
public struct AsyncPhoto: View {
    let url: URL?
    let placeholderSystemImage: String
    let placeholderTint: Color

    public init(url: URL?, placeholderSystemImage: String = "pawprint.fill", placeholderTint: Color = MamaColor.mint) {
        self.url = url
        self.placeholderSystemImage = placeholderSystemImage
        self.placeholderTint = placeholderTint
    }

    public var body: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                case .failure:
                    placeholder
                case .empty:
                    placeholder.overlay(ProgressView())
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            placeholderTint.opacity(0.25)
            Image(systemName: placeholderSystemImage)
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(placeholderTint)
        }
    }
}

/// Yaralı hayvan fotoğrafları bulanık gösterilir, "görmek için dokun" uyarısı (PRD 9.2).
public struct SensitivePhoto: View {
    let url: URL?
    @State private var revealed = false

    public init(url: URL?) {
        self.url = url
    }

    public var body: some View {
        ZStack {
            AsyncPhoto(url: url, placeholderSystemImage: "cross.case.fill", placeholderTint: MamaColor.statusUrgent)
                .blur(radius: revealed ? 0 : 28)
                .clipped()
            if !revealed {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { revealed = true }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: "eye.slash.fill").font(.title2)
                        Text("Hassas içerik olabilir").font(MamaFont.subheadline.weight(.semibold))
                        Text("Görmek için dokun").font(MamaFont.caption)
                    }
                    .foregroundStyle(.white)
                    .padding()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black.opacity(0.25))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Hassas içerik olabilir. Görmek için dokun.")
            }
        }
    }
}

/// Baş harfli veya fotoğraflı yuvarlak avatar.
public struct AvatarView: View {
    let name: String
    let url: URL?
    let size: CGFloat

    public init(name: String, url: URL? = nil, size: CGFloat = 44) {
        self.name = name
        self.url = url
        self.size = size
    }

    private var initials: String {
        let parts = name.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased(with: Locale(identifier: "tr_TR"))
    }

    public var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().scaledToFill() } else { initialsView }
                }
            } else {
                initialsView
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }

    private var initialsView: some View {
        ZStack {
            Circle().fill(MamaColor.tileMint)
            Text(initials)
                .font(.system(size: size * 0.38, weight: .bold, design: .rounded))
                .foregroundStyle(MamaColor.textPrimary)
        }
    }
}

/// Fotoğraf ekleme: kamera veya galeri. Seçilen görsel JPEG `Data` olarak döner.
/// EXIF/GPS temizliği ve 1600 px küçültme yüklemeden önce `PhotoProcessor` ile yapılır (PRD 7.1).
public struct PhotoInputButton<Label: View>: View {
    let onPicked: (Data) -> Void
    let label: () -> Label

    @State private var libraryItem: PhotosPickerItem?
    @State private var showLibrary = false
    @State private var showCamera = false

    public init(onPicked: @escaping (Data) -> Void, @ViewBuilder label: @escaping () -> Label) {
        self.onPicked = onPicked
        self.label = label
    }

    public var body: some View {
        Menu {
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button {
                    showCamera = true
                } label: {
                    SwiftUI.Label("Fotoğraf çek", systemImage: "camera.fill")
                }
            }
            Button {
                showLibrary = true
            } label: {
                SwiftUI.Label("Galeriden seç", systemImage: "photo.on.rectangle")
            }
        } label: {
            label()
        }
        .photosPicker(isPresented: $showLibrary, selection: $libraryItem, matching: .images, preferredItemEncoding: .compatible)
        .onChange(of: libraryItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    onPicked(data)
                }
                libraryItem = nil
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in
                if let data = image.jpegData(compressionQuality: 0.9) { onPicked(data) }
            }
            .ignoresSafeArea()
        }
    }
}

/// UIImagePickerController kamera sarmalayıcı.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

/// Seçilmiş fotoğrafın küçük önizlemesi + kaldır butonu.
public struct PhotoThumbnail: View {
    let data: Data
    let onRemove: () -> Void

    public init(data: Data, onRemove: @escaping () -> Void) {
        self.data = data
        self.onRemove = onRemove
    }

    public var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: MamaMetrics.smallCornerRadius, style: .continuous))
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, Color.black.opacity(0.6))
            }
            .padding(4)
            .accessibilityLabel("Fotoğrafı kaldır")
        }
    }
}
#endif
