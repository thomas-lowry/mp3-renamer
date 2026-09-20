import Foundation
import SwiftUI
import UniformTypeIdentifiers

private struct RenameItem: Sendable {
    let sourceURL: URL
    let destinationName: String
    let metadata: ID3Metadata
}

private enum RenameResult: Sendable {
    case success
    case failure(String)
}

@MainActor
final class AlbumViewModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var album = ""
    @Published var year = ""
    @Published var sharedArtist = ""
    @Published var applyArtistToAll = true
    @Published var tracks: [Track] = []
    @Published var coverData: Data?
    @Published var errorMessage: String?
    @Published var completionMessage: String?
    @Published private(set) var isRenaming = false
    @Published private(set) var renameProgress = ""
    @Published private(set) var previewRefreshID = UUID()
    @Published private(set) var initialTrackNumbers: [UUID: String] = [:]
    @Published private(set) var editedTrackNumbers = Set<UUID>()

    var validationIssues: [String] {
        var issues: [String] = []
        if album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Album is required.") }
        if year.range(of: "^[0-9]{4}$", options: .regularExpression) == nil { issues.append("Year must contain four digits.") }
        if applyArtistToAll && sharedArtist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Artist is required.") }
        if tracks.isEmpty { issues.append("Choose a folder that contains MP3 files.") }
        if tracks.contains(where: { !$0.metadataReadable }) { issues.append("One or more MP3 files cannot be read.") }
        var trackNumbers = Set<Int>()
        var targets = Set<String>()
        for track in tracks {
            let artist = applyArtistToAll ? sharedArtist : track.artist
            guard let number = Int(track.trackNumber), number > 0 else { issues.append("Every track number must be positive."); continue }
            if !trackNumbers.insert(number).inserted { issues.append("Track numbers must be unique.") }
            if track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Every song title is required.") }
            if artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { issues.append("Every artist is required.") }
            let target = FilenameBuilder.filename(artist: artist, album: album, track: number, title: track.title)
            if !targets.insert(target.lowercased()).inserted { issues.append("Two tracks would use the same filename.") }
            if let folderURL, target.lowercased() != track.url.lastPathComponent.lowercased(),
                FileManager.default.fileExists(atPath: folderURL.appendingPathComponent(target).path) {
                issues.append("\(target) already exists in this folder.")
            }
        }
        return Array(Set(issues)).sorted()
    }

    var canRename: Bool { validationIssues.isEmpty }
    var plannedNames: [(Track, String)] {
        tracks.compactMap { track in
            guard let number = Int(track.trackNumber) else { return nil }
            return (track, FilenameBuilder.filename(artist: applyArtistToAll ? sharedArtist : track.artist, album: album, track: number, title: track.title))
        }
    }

    func loadFolder(_ url: URL) {
        errorMessage = nil; completionMessage = nil
        guard AlbumFolderValidator.isValid(url) else {
            errorMessage = "Choose a folder containing at least one MP3 file."
            return
        }
        guard url.startAccessingSecurityScopedResource() else { errorMessage = "The selected folder could not be accessed."; return }
        folderURL = url
        defer { url.stopAccessingSecurityScopedResource() }
        do {
            let contents = try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            let files = contents.filter { $0.pathExtension.lowercased() == "mp3" }.sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            var firstMetadata: ID3Metadata?
            var newTracks: [Track] = []
            for file in files {
                do {
                    let metadata = try ID3Service.read(file)
                    firstMetadata = firstMetadata ?? metadata
                    newTracks.append(Track(url: file, metadata: metadata))
                } catch { newTracks.append(Track(url: file, metadataReadable: false)) }
            }
            // Use filename numbers only when the complete folder presents a
            // consistent, unique sequence. This avoids treating incidental digits
            // in a song title as a track number.
            let guessedNumbers = newTracks.map { FilenameTrackNumber.guess(from: $0.url) }
            if guessedNumbers.allSatisfy({ $0 != nil }), Set(guessedNumbers.compactMap { $0 }).count == newTracks.count {
                for index in newTracks.indices where newTracks[index].trackNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    newTracks[index].trackNumber = String(guessedNumbers[index]!)
                }
            }
            album = TextSanitizer.sentenceCaseIfAllCaps(firstMetadata?.album ?? "")
            year = firstMetadata?.year ?? ""
            sharedArtist = TextSanitizer.sentenceCaseIfAllCaps(firstMetadata?.artist ?? "")
            for index in newTracks.indices {
                newTracks[index].artist = TextSanitizer.sentenceCaseIfAllCaps(newTracks[index].artist)
                newTracks[index].title = TextSanitizer.sentenceCaseIfAllCaps(newTracks[index].title)
            }
            let image = contents.first { ["png", "jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
            coverData = image.flatMap { try? Data(contentsOf: $0) } ?? firstMetadata?.coverData
            // Set preview fallback data before publishing rows. SwiftUI creates the
            // row views in response to `tracks`; the first render must already be
            // able to resolve a prefilled number.
            initialTrackNumbers = Dictionary(uniqueKeysWithValues: newTracks.compactMap { track in
                track.trackNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : (track.id, track.trackNumber)
            })
            editedTrackNumbers = []
            tracks = newTracks
            // Yield once so native text fields can receive their initial values,
            // then explicitly rebuild the derived SwiftUI preview labels.
            DispatchQueue.main.async { [weak self] in self?.previewRefreshID = UUID() }
        } catch { errorMessage = error.localizedDescription }
    }

    func trackNumberBinding(for track: Binding<Track>) -> Binding<String> {
        Binding(
            get: { track.wrappedValue.trackNumber },
            set: { [weak self] value in
                track.wrappedValue.trackNumber = value
                self?.editedTrackNumbers.insert(track.wrappedValue.id)
            }
        )
    }

    func previewTrackNumber(for track: Track) -> String {
        let value = track.trackNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if !value.isEmpty { return value }
        guard !editedTrackNumbers.contains(track.id) else { return "" }
        return initialTrackNumbers[track.id] ?? ""
    }

    func setCover(_ data: Data) {
        guard let png = CoverImage.squarePNGData(from: data) else { errorMessage = "That image could not be converted to PNG."; return }
        coverData = png
    }

    func performRename() {
        guard let folderURL, canRename else { return }
        errorMessage = nil
        let artwork = coverData
        let items = tracks.compactMap { track -> RenameItem? in
            guard let number = Int(track.trackNumber) else { return nil }
            let artist = applyArtistToAll ? sharedArtist : track.artist
            return RenameItem(
                sourceURL: track.url,
                destinationName: FilenameBuilder.filename(artist: artist, album: album, track: number, title: track.title),
                metadata: ID3Metadata(artist: artist, album: album, year: year, track: track.trackNumber, title: track.title)
            )
        }
        isRenaming = true
        renameProgress = "Preparing files…"
        let reportProgress: @Sendable (String) -> Void = { [weak self] message in
            print("[MP3 Renamer] \(message)")
            Task { @MainActor in self?.renameProgress = message }
        }

        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> RenameResult in
                guard folderURL.startAccessingSecurityScopedResource() else {
                    return .failure("Folder access expired. Select it again.")
                }
                defer { folderURL.stopAccessingSecurityScopedResource() }
                do {
                    // Folder-discovered artwork has not necessarily passed through
                    // setCover(_:), so normalize it away from the UI thread too.
                    reportProgress("Preparing cover artwork…")
                    let png = artwork.flatMap(CoverImage.squarePNGData)
                    if let png {
                        reportProgress("Writing cover.png…")
                        try png.write(to: folderURL.appendingPathComponent("cover.png"))
                    }
                    for (index, item) in items.enumerated() {
                        reportProgress("Writing metadata \(index + 1) of \(items.count): \(item.sourceURL.lastPathComponent)")
                        try ID3Service.write(item.sourceURL, metadata: item.metadata, coverPNG: png)
                    }
                    // Temporary names prevent one planned rename from blocking another.
                    let staging = items.map { ($0.sourceURL, folderURL.appendingPathComponent(".mp3renamer-\(UUID().uuidString).mp3"), $0.destinationName) }
                    reportProgress("Preparing filenames…")
                    for item in staging { try FileManager.default.moveItem(at: item.0, to: item.1) }
                    for (index, item) in staging.enumerated() {
                        reportProgress("Renaming \(index + 1) of \(items.count): \(item.2)")
                        try FileManager.default.moveItem(at: item.1, to: folderURL.appendingPathComponent(item.2))
                    }
                    return .success
                } catch {
                    return .failure("Rename stopped: \(error.localizedDescription)")
                }
            }.value

            guard let self else { return }
            self.isRenaming = false
            self.renameProgress = ""
            switch result {
            case .success:
                for index in self.tracks.indices {
                    self.tracks[index].url = folderURL.appendingPathComponent(items[index].destinationName)
                }
                self.completionMessage = "Updated metadata and renamed \(items.count) MP3 file\(items.count == 1 ? "" : "s")."
            case let .failure(message):
                self.errorMessage = message
            }
        }
    }
}
