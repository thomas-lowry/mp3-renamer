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
    /// APA title case: articles, coordinating conjunctions, and prepositions
    /// of three letters or fewer stay lowercase unless they begin the title or
    /// follow a subtitle separator. Acronyms within otherwise mixed-case text
    /// are preserved, while an entirely uppercase tag is normalized as a title.
    static func apaTitleCase(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.unicodeScalars.contains(where: { CharacterSet.letters.contains($0) }) else { return trimmed }

        // In an entirely uppercase tag, words such as THE and SONG are source
        // casing rather than acronyms. Preserve unambiguous acronyms (MP3,
        // AC/DC, R&B) while normalizing the rest. In mixed-case text, any
        // uppercase word is treated as deliberate acronym styling.
        let preserveUppercaseWords = trimmed.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
        var result = ""
        var word = ""
        var capitalizeNextWord = true

        func appendFormattedWord() {
            guard !word.isEmpty else { return }
            result += titleCaseWord(word, capitalize: capitalizeNextWord, preserveUppercaseWords: preserveUppercaseWords)
            word = ""
            capitalizeNextWord = false
        }

        for character in trimmed {
            if character.isWhitespace {
                appendFormattedWord()
                result.append(character)
            } else if character == ":" || character == ";" || character == "—" || character == "–" {
                appendFormattedWord()
                result.append(character)
                capitalizeNextWord = true
            } else {
                word.append(character)
            }
        }
        appendFormattedWord()
        return result
    }

    private static let apaMinorWords: Set<String> = [
        "a", "an", "the", "and", "as", "at", "but", "by", "for", "if",
        "in", "nor", "of", "on", "or", "per", "so", "to", "up", "via", "yet"
    ]

    private static func titleCaseWord(_ word: String, capitalize: Bool, preserveUppercaseWords: Bool) -> String {
        word.split(separator: "-", omittingEmptySubsequences: false).enumerated().map { index, part in
            titleCasePart(String(part), capitalize: capitalize && index == 0, preserveUppercaseWords: preserveUppercaseWords)
        }.joined(separator: "-")
    }

    private static func titleCasePart(_ part: String, capitalize: Bool, preserveUppercaseWords: Bool) -> String {
        guard let firstLetter = part.firstIndex(where: { $0.isLetter }),
              let lastLetter = part.lastIndex(where: { $0.isLetter }) else { return part }
        let prefix = String(part[..<firstLetter])
        let core = String(part[firstLetter...lastLetter])
        let suffix = String(part[part.index(after: lastLetter)...])
        let lowercasedCore = core.lowercased()
        let hasUppercaseLetter = core.unicodeScalars.contains { CharacterSet.uppercaseLetters.contains($0) }
        let hasLowercaseLetter = core.unicodeScalars.contains { CharacterSet.lowercaseLetters.contains($0) }
        let isAllCapsWord = hasUppercaseLetter && !hasLowercaseLetter
        let isUnambiguousAcronym = part.contains(where: { $0.isNumber }) || part.contains("/") || part.contains("&") || part.contains(".")

        if isAllCapsWord && (preserveUppercaseWords || isUnambiguousAcronym) {
            return prefix + core + suffix
        }
        if !capitalize && apaMinorWords.contains(lowercasedCore) {
            return prefix + lowercasedCore + suffix
        }
        return prefix + lowercasedCore.prefix(1).uppercased() + String(lowercasedCore.dropFirst()) + suffix
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
