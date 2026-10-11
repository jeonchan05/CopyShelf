import CoreGraphics
import CryptoKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ClipboardImage: Codable, Equatable, Sendable {
    public static let maximumInputBytes = 32 * 1024 * 1024
    public static let maximumPNGBytes = 12 * 1024 * 1024
    public static let maximumPixels = 32_000_000
    public static let maximumDimension = 16_384
    public let pngData: Data
    public let width: Int
    public let height: Int
    public let fingerprint: String

    public enum ImageError: Error { case invalidImage, unsupportedFormat, tooLarge }
    private enum CodingKeys: String, CodingKey { case pngData, width, height }
    private static let formats: Set<String> = [
        UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier,
        UTType.heic.identifier, UTType.heif.identifier, UTType.gif.identifier, UTType.bmp.identifier
    ]

    public init(pngData: Data) throws {
        guard !pngData.isEmpty, pngData.count <= Self.maximumPNGBytes else { throw ImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              CGImageSourceGetType(source) as String? == UTType.png.identifier,
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceGetCount(source) == 1 else { throw ImageError.invalidImage }
        let size = try Self.dimensions(of: source)
        guard Self.thumbnail(source, size: 64) != nil else { throw ImageError.invalidImage }
        self.pngData = pngData
        width = size.width
        height = size.height
        fingerprint = SHA256.hash(data: pngData).map { String(format: "%02x", $0) }.joined()
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let data = try values.decode(Data.self, forKey: .pngData)
        let width = try values.decode(Int.self, forKey: .width)
        let height = try values.decode(Int.self, forKey: .height)
        try self.init(pngData: data)
        guard self.width == width, self.height == height else { throw ImageError.invalidImage }
    }

    public static func normalising(_ data: Data) throws -> ClipboardImage {
        guard !data.isEmpty, data.count <= maximumInputBytes else { throw ImageError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source) as String?, formats.contains(type) else {
            throw ImageError.unsupportedFormat
        }
        guard CGImageSourceGetStatus(source) == .statusComplete else { throw ImageError.invalidImage }
        let size = try dimensions(of: source)
        // This keeps full resolution while applying EXIF rotation and ignoring embedded previews.
        guard let image = thumbnail(source, size: max(size.width, size.height)) else { throw ImageError.invalidImage }
        let result = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(result, UTType.png.identifier as CFString, 1, nil) else {
            throw ImageError.invalidImage
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImageError.invalidImage }
        return try ClipboardImage(pngData: result as Data)
    }

    public func thumbnail(maximumSize: Int = 176) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil) else { return nil }
        return Self.thumbnail(source, size: min(max(maximumSize, 1), 512))
    }

    public func tiffData() throws -> Data {
        guard let source = CGImageSourceCreateWithData(pngData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { throw ImageError.invalidImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.tiff.identifier as CFString, 1, nil) else {
            throw ImageError.invalidImage
        }
        let options = [kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5]] as CFDictionary
        CGImageDestinationAddImage(destination, image, options)
        guard CGImageDestinationFinalize(destination), data.length <= Self.maximumPixels * 4 + 1_048_576 else {
            throw ImageError.tooLarge
        }
        return data as Data
    }

    private static func dimensions(of source: CGImageSource) throws -> (width: Int, height: Int) {
        guard let values = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (values[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (values[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0, height > 0 else { throw ImageError.invalidImage }
        guard width <= maximumDimension, height <= maximumDimension,
              width <= maximumPixels / height else { throw ImageError.tooLarge }
        return (width, height)
    }

    private static func thumbnail(_ source: CGImageSource, size: Int) -> CGImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: size,
            kCGImageSourceShouldCacheImmediately: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
