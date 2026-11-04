#if canImport(ImageIO)
import CoreGraphics
import Foundation
import ImageIO

/// Yüklemeden önce fotoğrafı temizler (PRD 7.1): uzun kenarı `maxPixelSize`'a indirir, EXIF yönünü piksellere
/// uygular ve **hiç metadata yazmadan** JPEG'e yeniden kodlar. Böylece EXIF/GPS/TIFF/maker-note alanları düşer.
public enum PhotoProcessor {
    public enum Failure: Error, Equatable, Sendable {
        /// Veri okunabilir bir görsel değil.
        case unreadableImage
        case encodingFailed
    }

    public static func sanitizedJPEG(from data: Data, maxPixelSize: Int = 1600, quality: Double = 0.8) throws -> Data {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions),
              CGImageSourceGetCount(source) > 0 else {
            throw Failure.unreadableImage
        }

        // Küçük görseller büyütülmez; `WithTransform` EXIF yönünü uygular (çıktıda yön etiketi gerekmez).
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
            kCGImageSourceShouldCacheImmediately: true,
        ] as CFDictionary
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions) else {
            throw Failure.unreadableImage
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output as CFMutableData, "public.jpeg" as CFString, 1, nil) else {
            throw Failure.encodingFailed
        }
        // Yalnızca sıkıştırma kalitesi; kaynak özellikleri (CGImageSourceCopyPropertiesAtIndex) bilerek kopyalanmaz.
        let destinationOptions = [
            kCGImageDestinationLossyCompressionQuality: min(1, max(0, quality)),
        ] as CFDictionary
        CGImageDestinationAddImage(destination, image, destinationOptions)
        guard CGImageDestinationFinalize(destination) else {
            throw Failure.encodingFailed
        }
        return output as Data
    }
}

/// Başka bir yükleyiciyi saran ve veriyi önce `PhotoProcessor` ile temizleyen yükleyici
/// (ör. demo modunda `InMemoryBackend`).
public struct SanitizingMediaUploader: MediaUploader {
    public let base: any MediaUploader
    public var maxPixelSize: Int
    public var quality: Double

    public init(base: any MediaUploader, maxPixelSize: Int = 1600, quality: Double = 0.8) {
        self.base = base
        self.maxPixelSize = maxPixelSize
        self.quality = quality
    }

    public func uploadJPEG(_ data: Data) async throws -> URL {
        let sanitized: Data
        do {
            sanitized = try PhotoProcessor.sanitizedJPEG(from: data, maxPixelSize: maxPixelSize, quality: quality)
        } catch {
            throw MamaError.invalidInput("Bu fotoğraf işlenemedi. Başka bir fotoğraf dener misin?")
        }
        return try await base.uploadJPEG(sanitized)
    }
}
#endif
