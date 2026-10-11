import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import ClipboardCore

struct ImageTests {
    private func fixture(red: CGFloat = 0.3, width: Int = 24, height: Int = 16, alpha: CGFloat = 1) throws -> ClipboardImage {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: red, green: 0.4, blue: 0.7, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return try ClipboardImage(pngData: data as Data)
    }

    private func withFile(_ body: (HistoryFile) throws -> Void) throws {
        let root = Foundation.FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? Foundation.FileManager.default.removeItem(at: root) }
        try body(HistoryFile(url: root.appendingPathComponent("history.json")))
    }

    @Test func mixedHistoryDeduplicatesAndPreservesImageIdentity() throws {
        let image = try fixture()
        var history = ClipboardHistory()
        let first = history.record(image, sourceName: "Screenshot")
        #expect(first)
        let id = history.clips[0].id
        let text = history.record("multiline\ntext")
        #expect(text)
        let moved = history.record(image, sourceName: "Preview")
        #expect(moved)
        #expect(history.clips.count == 2)
        #expect(history.clips[0].id == id)
        #expect(history.clips[0].image == image)
        #expect(history.clips[0].sourceName == "Preview")
        let duplicate = history.record(image)
        #expect(!duplicate)
    }

    @Test func imageSearchMatchesKindDimensionsAndSourceWithoutOCR() throws {
        var history = ClipboardHistory()
        history.record(try fixture(), sourceName: "Preview")
        history.record("ordinary text", sourceName: "Editor")
        #expect(history.search("이미지 preview").count == 1)
        #expect(history.search("image 24x16").count == 1)
        #expect(history.search("스크린샷").first?.isImage == true)
        #expect(history.search("ordinary").first?.isImage == false)
        #expect(history.search("words inside the pixels").isEmpty)
    }

    @Test func imageBudgetEvictsOldestEntriesAndRejectsAnItemOverBudget() throws {
        let images = try [fixture(red: 0.1), fixture(red: 0.5), fixture(red: 0.9)]
        let largest = try #require(images.map { $0.pngData.count }.max())
        var history = ClipboardHistory(imageByteLimit: largest * 2)
        history.record(images[0])
        history.record("keep this text")
        history.record(images[1])
        history.record(images[2])
        #expect(history.clips.filter(\.isImage).count == 2)
        #expect(history.clips.last?.text == "keep this text")
        #expect(history.clips.reduce(0) { $0 + $1.imageByteCount } <= largest * 2)
        var tiny = ClipboardHistory(imageByteLimit: images[0].pngData.count - 1)
        let oversized = tiny.record(images[0])
        #expect(!oversized)
        #expect(tiny.clips.isEmpty)
    }

    @Test func mixedPersistenceRoundTripAndClearUseTheSameProtectedFile() throws {
        try withFile { file in
            let image = try fixture()
            let clips = [Clip(image: image, sourceName: "Screenshot"), Clip(text: "exact\n text")]
            try file.save(clips)
            #expect(try file.load() == clips)
            let json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file.url)) as? [String: Any])
            #expect(json["version"] as? Int == 2)
            #expect(try Foundation.FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int == 0o600)
            try file.save([])
            #expect(!Foundation.FileManager.default.fileExists(atPath: file.url.path))
        }
    }

    @Test func legacyTextHistoryLoadsAndUpgradesWithoutLosingWhitespaceOrID() throws {
        struct LegacyArchive: Encodable { let version = 1; let clips: [Clip] }
        try withFile { file in
            try Foundation.FileManager.default.createDirectory(at: file.url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let clip = Clip(text: "  legacy\n\ttext\n", sourceName: "Editor")
            try JSONEncoder().encode(LegacyArchive(clips: [clip])).write(to: file.url)
            #expect(try file.load() == [clip])
            try file.save([Clip(image: fixture()), clip])
            #expect(try file.load().last == clip)
        }
    }

    @Test func imageDataValidationRejectsMalformedOversizedAndMismatchedMetadata() throws {
        #expect(throws: (any Error).self) { try ClipboardImage(pngData: Data("not an image".utf8)) }
        #expect(throws: ClipboardImage.ImageError.tooLarge) {
            try ClipboardImage(pngData: Data(repeating: 0, count: ClipboardImage.maximumPNGBytes + 1))
        }
        #expect(throws: ClipboardImage.ImageError.tooLarge) {
            try ClipboardImage.normalising(Data(repeating: 0, count: ClipboardImage.maximumInputBytes + 1))
        }
        let image = try fixture()
        #expect(throws: (any Error).self) { try ClipboardImage(pngData: Data(image.pngData.prefix(40))) }
        let json = try JSONSerialization.data(withJSONObject: [
            "pngData": image.pngData.base64EncodedString(), "width": image.width + 1, "height": image.height
        ])
        #expect(throws: (any Error).self) { try JSONDecoder().decode(ClipboardImage.self, from: json) }
    }

    @Test func thumbnailsAndTIFFKeepDimensionsAndNormalisationIsStable() throws {
        let image = try fixture(width: 128, height: 64)
        let thumbnail = try #require(image.thumbnail(maximumSize: 32))
        #expect(thumbnail.width == 32)
        #expect(thumbnail.height == 16)
        let normalised = try ClipboardImage.normalising(image.pngData)
        #expect(try ClipboardImage.normalising(normalised.pngData) == normalised)
        let fromTIFF = try ClipboardImage.normalising(image.tiffData())
        #expect(fromTIFF.width == 128)
        #expect(fromTIFF.height == 64)
    }

    @Test func unknownArchiveVersionAndBrokenImageDoNotOverwriteTheFile() throws {
        try withFile { file in
            try file.save([Clip(image: fixture())])
            let original = try Data(contentsOf: file.url)
            var json = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
            json["version"] = 99
            let future = try JSONSerialization.data(withJSONObject: json)
            try future.write(to: file.url)
            #expect(throws: HistoryFile.ArchiveError.unsupportedVersion) { try file.load() }
            #expect(try Data(contentsOf: file.url) == future)
            json["version"] = 2
            var clips = try #require(json["clips"] as? [[String: Any]])
            clips[0]["image"] = ["pngData": Data("bad".utf8).base64EncodedString(), "width": 1, "height": 1]
            json["clips"] = clips
            let broken = try JSONSerialization.data(withJSONObject: json)
            try broken.write(to: file.url)
            #expect(throws: (any Error).self) { try file.load() }
            #expect(try Data(contentsOf: file.url) == broken)
        }
    }

    @Test func forgedImageDimensionsAreRejectedBeforePixelDecoding() throws {
        let image = try fixture()
        for dimensions: (UInt32, UInt32) in [(40_000, 1), (8192, 8192)] {
            var data = image.pngData
            func bytes(_ value: UInt32) -> [UInt8] {
                [UInt8((value >> 24) & 255), UInt8((value >> 16) & 255), UInt8((value >> 8) & 255), UInt8(value & 255)]
            }
            data.replaceSubrange(16..<20, with: bytes(dimensions.0))
            data.replaceSubrange(20..<24, with: bytes(dimensions.1))
            var crc: UInt32 = 0xffff_ffff
            for byte in data[12..<29] {
                crc ^= UInt32(byte)
                for _ in 0..<8 { crc = (crc >> 1) ^ (crc & 1 == 1 ? 0xedb8_8320 : 0) }
            }
            data.replaceSubrange(29..<33, with: bytes(crc ^ 0xffff_ffff))
            #expect(throws: (any Error).self) { try ClipboardImage.normalising(data) }
            #expect(throws: (any Error).self) { try ClipboardImage(pngData: data) }
        }
    }

    @Test func PNGAndTIFFPreserveTransparency() throws {
        let image = try fixture(alpha: 0.5)
        let normalised = try ClipboardImage.normalising(image.tiffData())
        for entry in [image, normalised] {
            let decoded = try #require(entry.thumbnail(maximumSize: 24))
            let context = try #require(CGContext(data: nil, width: 24, height: 16, bitsPerComponent: 8,
                bytesPerRow: 24 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(decoded, in: CGRect(x: 0, y: 0, width: 24, height: 16))
            let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            #expect(abs(Int(pixels[3]) - 128) <= 1)
        }
    }
}
