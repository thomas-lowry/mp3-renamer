import Testing
import Foundation
import AppKit
@testable import MP3Renamer

@Test func filenamePadsTrackNumberAndSanitizes() {
    #expect(FilenameBuilder.filename(artist: "A/rtist", album: "Album", track: 3, title: "A: Song") == "A-rtist - Album - 03 - A- Song.mp3")
}

@Test func onlyAllCapsTextIsNormalized() {
    #expect(TextSanitizer.sentenceCaseIfAllCaps("THE SONG") == "The song")
    #expect(TextSanitizer.sentenceCaseIfAllCaps("AC/DC Live") == "AC/DC Live")
}

@Test func writingTagsReplacesExistingDataAndRoundTrips() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mp3-renamer-test-\(UUID().uuidString).mp3")
    defer { try? FileManager.default.removeItem(at: url) }
    // MPEG frame-sync bytes are sufficient for the metadata layer; it never alters audio bytes.
    try Data([0xff, 0xfb, 0x90, 0x00, 0, 0, 0]).write(to: url)
    try ID3Service.write(url, metadata: ID3Metadata(artist: "Artist", album: "Album", year: "2026", track: "1", title: "Song"), coverPNG: nil)
    // Rewriting a file that already contains an ID3 tag must not retain a
    // non-zero Data index after stripping the old tag.
    try ID3Service.write(url, metadata: ID3Metadata(artist: "New Artist", album: "Album", year: "2026", track: "1", title: "Song"), coverPNG: nil)
    let read = try ID3Service.read(url)
    #expect(read.artist == "New Artist")
    #expect(read.album == "Album")
    #expect(read.year == "2026")
    #expect(read.track == "1")
    #expect(read.title == "Song")
}

@Test func coverArtworkIsCroppedToASquarePNG() throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 320, pixelsHigh: 160,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    bitmap.setColor(NSColor(calibratedRed: 1, green: 0.1, blue: 0.5, alpha: 1), atX: 0, y: 0)
    let source = try #require(bitmap.representation(using: .png, properties: [:]))
    let square = try #require(CoverImage.squarePNGData(from: source))
    let result = try #require(NSImage(data: square))
    #expect(result.size.width == result.size.height)
}

@Test func oversizedCoverArtworkIsDownscaled() throws {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1_600, pixelsHigh: 800,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .calibratedRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    let source = try #require(bitmap.representation(using: .png, properties: [:]))
    let square = try #require(CoverImage.squarePNGData(from: source))
    let result = try #require(NSImage(data: square))
    #expect(result.size.width == CGFloat(CoverImage.maximumPixelDimension))
    #expect(result.size.height == CGFloat(CoverImage.maximumPixelDimension))
}

@Test func albumFolderMustContainATopLevelMP3() throws {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mp3-renamer-folder-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    #expect(!AlbumFolderValidator.isValid(folder))
    try Data().write(to: folder.appendingPathComponent("01 song.MP3"))
    #expect(AlbumFolderValidator.isValid(folder))
}

@Test func filenameTrackNumbersUseOnlyLeadingTrackPrefixes() {
    #expect(FilenameTrackNumber.guess(from: URL(fileURLWithPath: "/tmp/01 - Song.mp3")) == 1)
    #expect(FilenameTrackNumber.guess(from: URL(fileURLWithPath: "/tmp/2. Song.mp3")) == 2)
    #expect(FilenameTrackNumber.guess(from: URL(fileURLWithPath: "/tmp/Song 03.mp3")) == nil)
    #expect(FilenameTrackNumber.guess(from: URL(fileURLWithPath: "/tmp/99Problems.mp3")) == nil)
}

@Test func id3TextTrimsInvisibleFrameTerminators() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("mp3-renamer-nul-\(UUID().uuidString).mp3")
    defer { try? FileManager.default.removeItem(at: url) }
    try Data([0xff, 0xfb, 0x90, 0x00, 0, 0, 0]).write(to: url)
    try ID3Service.write(url, metadata: ID3Metadata(artist: "Artist", album: "Album", year: "2026", track: "1\0", title: "Song"), coverPNG: nil)
    let metadata = try ID3Service.read(url)
    #expect(metadata.track == "1")
    #expect(Int(metadata.track) == 1)
}
