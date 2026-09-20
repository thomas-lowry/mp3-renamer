import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

struct ID3Metadata: Equatable, Sendable {
    var artist = ""
    var album = ""
    var year = ""
    var track = ""
    var title = ""
    var coverData: Data?
}

struct Track: Identifiable, Equatable, Sendable {
    let id = UUID()
    var url: URL
    var artist: String
    var trackNumber: String
    var title: String
    var metadataReadable: Bool

    init(url: URL, metadata: ID3Metadata? = nil, metadataReadable: Bool = true) {
        self.url = url
        artist = metadata?.artist ?? ""
        trackNumber = metadata?.track.components(separatedBy: "/").first ?? ""
        title = metadata?.title ?? ""
        self.metadataReadable = metadataReadable
    }
}

enum TextSanitizer {
    static func sentenceCaseIfAllCaps(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let letters = trimmed.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty, trimmed == trimmed.uppercased() else { return trimmed }
        return trimmed.lowercased().prefix(1).uppercased() + trimmed.lowercased().dropFirst()
    }

    static func fileComponent(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?*\"<>|")
        let cleaned = value.components(separatedBy: forbidden).joined(separator: "-")
        return cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

enum FilenameBuilder {
    static func filename(artist: String, album: String, track: Int, title: String) -> String {
        "\(TextSanitizer.fileComponent(artist)) - \(TextSanitizer.fileComponent(album)) - \(String(format: "%02d", track)) - \(TextSanitizer.fileComponent(title)).mp3"
    }
}

enum FilenameTrackNumber {
    /// Accepts familiar album-file prefixes such as `01`, `01 - Song`, and
    /// `01. Song`; it deliberately does not search later in a title for digits.
    static func guess(from url: URL) -> Int? {
        let stem = url.deletingPathExtension().lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = stem.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits), value > 0 else { return nil }
        let remaining = stem.dropFirst(digits.count)
        guard remaining.isEmpty || remaining.first?.isWhitespace == true || ["-", "_", ".", ")"].contains(remaining.first!) else { return nil }
        return value
    }
}

enum AlbumFolderValidator {
    static func mp3Files(in url: URL) -> [URL] {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return [] }
        return contents.filter { $0.pathExtension.lowercased() == "mp3" }
    }

    static func isValid(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && !mp3Files(in: url).isEmpty
    }
}

enum CoverImage {
    /// Large source artwork is expensive to encode and would be embedded in every MP3.
    /// This keeps the cover sharp in the app while making batch writes predictable.
    static let maximumPixelDimension = 1_200

    static func squarePNGData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return nil }
        let width = image.width
        let height = image.height
        guard width > 0, height > 0 else { return nil }
        let side = min(max(width, height), maximumPixelDimension)
        guard let context = CGContext(
            data: nil, width: side, height: side,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        let scale = max(CGFloat(side) / CGFloat(width), CGFloat(side) / CGFloat(height))
        let drawSize = CGSize(width: CGFloat(width) * scale, height: CGFloat(height) * scale)
        let drawRect = CGRect(x: (CGFloat(side) - drawSize.width) / 2, y: (CGFloat(side) - drawSize.height) / 2, width: drawSize.width, height: drawSize.height)
        context.draw(image, in: drawRect)
        guard let outputImage = context.makeImage() else { return nil }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, outputImage, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
