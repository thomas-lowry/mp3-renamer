import Foundation

enum ID3Error: LocalizedError {
    case notMP3, malformedTag, writeFailed
    var errorDescription: String? {
        switch self {
        case .notMP3: return "This file is not a readable MP3."
        case .malformedTag: return "The ID3 metadata is malformed."
        case .writeFailed: return "The MP3 could not be written."
        }
    }
}

/// A compact ID3v2.3/v2.4 reader/writer. Rewriting the tag deliberately removes
/// all prior frames, leaving only the five fields and optional front-cover APIC.
enum ID3Service {
    static func read(_ url: URL) throws -> ID3Metadata {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count > 1 else { throw ID3Error.notMP3 }
        guard data.count >= 10, data.prefix(3) == Data("ID3".utf8) else {
            guard isMPEGFrame(at: 0, in: data) else { throw ID3Error.notMP3 }
            return ID3Metadata()
        }
        let version = data[3]
        guard version == 3 || version == 4 else { throw ID3Error.malformedTag }
        let tagSize = synchsafe(data[6...9])
        let hasFooter = version == 4 && (data[5] & 0x10) != 0
        let tagEnd = 10 + tagSize + (hasFooter ? 10 : 0)
        guard data.count >= tagEnd else { throw ID3Error.malformedTag }
        guard isMPEGFrame(at: tagEnd, in: data) else { throw ID3Error.notMP3 }
        var result = ID3Metadata()
        var cursor = 10
        let end = 10 + tagSize
        while cursor + 10 <= end {
            let identifier = String(decoding: data[cursor..<(cursor + 4)], as: UTF8.self)
            if identifier.trimmingCharacters(in: .controlCharacters).isEmpty || identifier == "\0\0\0\0" { break }
            let size: Int = version == 4 ? synchsafe(data[(cursor + 4)..<(cursor + 8)]) : bigEndian(data[(cursor + 4)..<(cursor + 8)])
            guard size >= 0, cursor + 10 + size <= end else { throw ID3Error.malformedTag }
            let payload = Data(data[(cursor + 10)..<(cursor + 10 + size)])
            switch identifier {
            case "TPE1": result.artist = decodeText(payload)
            case "TALB": result.album = decodeText(payload)
            case "TYER", "TDRC": result.year = decodeText(payload).prefix(4).description
            case "TRCK": result.track = decodeText(payload)
            case "TIT2": result.title = decodeText(payload)
            case "APIC" where result.coverData == nil: result.coverData = imageFromAPIC(payload)
            default: break
            }
            cursor += 10 + size
        }
        return result
    }

    static func write(_ url: URL, metadata: ID3Metadata, coverPNG: Data?) throws {
        var original = try Data(contentsOf: url)
        guard original.count > 1 else { throw ID3Error.notMP3 }
        if original.count >= 10, original.prefix(3) == Data("ID3".utf8) {
            let version = original[3]
            guard version == 3 || version == 4 else { throw ID3Error.malformedTag }
            let size = synchsafe(original[6...9])
            let hasFooter = version == 4 && (original[5] & 0x10) != 0
            let tagEnd = 10 + size + (hasFooter ? 10 : 0)
            guard original.count >= tagEnd else { throw ID3Error.malformedTag }
            // Data.removeFirst preserves the original collection index. Rebuilding
            // it gives the remaining MPEG bytes a zero-based index before parsing.
            original = Data(original.dropFirst(tagEnd))
        }
        guard isMPEGFrame(at: 0, in: original) else { throw ID3Error.notMP3 }
        if original.count >= 128, original.suffix(128).prefix(3) == Data("TAG".utf8) { original.removeLast(128) }

        var frames = Data()
        frames.append(textFrame("TIT2", metadata.title))
        frames.append(textFrame("TPE1", metadata.artist))
        frames.append(textFrame("TALB", metadata.album))
        frames.append(textFrame("TYER", metadata.year))
        frames.append(textFrame("TRCK", metadata.track))
        if let coverPNG { frames.append(apicFrame(coverPNG)) }
        var tag = Data("ID3".utf8)
        tag.append(contentsOf: [3, 0, 0])
        tag.append(synchsafeBytes(frames.count))
        tag.append(frames)
        tag.append(original)
        try tag.write(to: url, options: .atomic)
    }

    private static func textFrame(_ id: String, _ value: String) -> Data {
        var payload = Data([3]) // UTF-8
        payload.append(value.data(using: .utf8) ?? Data())
        return frame(id, payload)
    }

    private static func apicFrame(_ image: Data) -> Data {
        var payload = Data([3])
        payload.append(Data("image/png".utf8)); payload.append(0)
        payload.append(3) // front cover
        payload.append(0) // empty UTF-8 description
        payload.append(image)
        return frame("APIC", payload)
    }

    private static func frame(_ id: String, _ payload: Data) -> Data {
        var result = Data(id.utf8)
        var size = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &size) { result.append(contentsOf: $0) }
        result.append(contentsOf: [0, 0])
        result.append(payload)
        return result
    }

    private static func decodeText(_ data: Data) -> String {
        guard let encoding = data.first else { return "" }
        let content = data.dropFirst()
        let value: String
        switch encoding {
        case 0: value = String(data: content, encoding: .isoLatin1) ?? ""
        case 1: value = String(data: content, encoding: .utf16) ?? ""
        case 2: value = String(data: content, encoding: .utf16BigEndian) ?? ""
        default: value = String(data: content, encoding: .utf8) ?? ""
        }
        // Many encoders leave a NUL terminator in text frames. It is invisible in
        // NSTextField but makes numeric parsing (e.g. `Int("1\\0")`) fail.
        return value.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }

    private static func imageFromAPIC(_ data: Data) -> Data? {
        guard data.count > 4 else { return nil }
        let encoding = data[0]
        var cursor = 1
        while cursor < data.count, data[cursor] != 0 { cursor += 1 }
        guard cursor + 2 < data.count else { return nil }
        cursor += 1 // mime terminator
        cursor += 1 // picture type
        let terminatorWidth = encoding == 1 || encoding == 2 ? 2 : 1
        while cursor + terminatorWidth <= data.count {
            if terminatorWidth == 1 && data[cursor] == 0 { cursor += 1; break }
            if terminatorWidth == 2 && data[cursor] == 0 && data[cursor + 1] == 0 { cursor += 2; break }
            cursor += terminatorWidth == 2 ? 2 : 1
        }
        guard cursor < data.count else { return nil }
        return Data(data[cursor...])
    }

    private static func bigEndian(_ bytes: Data.SubSequence) -> Int {
        bytes.reduce(0) { ($0 << 8) | Int($1) }
    }
    private static func synchsafe(_ bytes: Data.SubSequence) -> Int {
        bytes.reduce(0) { ($0 << 7) | Int($1 & 0x7f) }
    }
    private static func synchsafeBytes(_ value: Int) -> Data {
        Data([UInt8((value >> 21) & 0x7f), UInt8((value >> 14) & 0x7f), UInt8((value >> 7) & 0x7f), UInt8(value & 0x7f)])
    }

    private static func isMPEGFrame(at index: Int, in data: Data) -> Bool {
        guard index >= 0, index + 1 < data.count else { return false }
        let first = data.index(data.startIndex, offsetBy: index)
        let second = data.index(after: first)
        return data[first] == 0xff && (data[second] & 0xe0) == 0xe0
    }
}
