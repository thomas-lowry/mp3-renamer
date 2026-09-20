import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    private enum InputFocus: Hashable {
        case cover, sharedArtist, album, year, rename
        case trackNumber(UUID), trackArtist(UUID), trackTitle(UUID)
    }

    @ObservedObject var model: AlbumViewModel
    @State private var importingCover = false
    @State private var focusedElement: InputFocus?

    private let trackRowHeight: CGFloat = 54
    private let trackRowSpacing: CGFloat = 8
    private let metadataTrailingColumnWidth: CGFloat = 119
    private let metadataColumnSpacing: CGFloat = 16
    private let metadataLeadingColumnWidth: CGFloat = 378
    private var visibleTrackCount: Int { min(max(model.tracks.count, 1), 8) }
    private var trackListHeight: CGFloat {
        if model.tracks.isEmpty { return 74 }
        let rows = visibleTrackCount * Int(trackRowHeight)
        let gaps = max(visibleTrackCount - 1, 0) * Int(trackRowSpacing)
        return CGFloat(rows + gaps + 16)
    }

    var body: some View {
        mainCard
            .frame(width: 778)
            .fixedSize(horizontal: true, vertical: true)
        .fileImporter(isPresented: $importingCover, allowedContentTypes: [.png, .jpeg]) { result in
            if case let .success(url) = result, let data = try? Data(contentsOf: url) { model.setCover(data) }
        }
        .onChange(of: model.folderURL) { _, _ in focusedElement = nil }
        .onChange(of: model.applyArtistToAll) { _, isSharedArtistEnabled in
            if !isSharedArtistEnabled, focusedElement == .sharedArtist { focusedElement = nil }
        }
        .onDrop(of: [.fileURL], isTargeted: nil, perform: acceptDroppedFolder)
        .alert("MP3 Renamer", isPresented: Binding(get: { model.errorMessage != nil || model.completionMessage != nil }, set: { _ in model.errorMessage = nil; model.completionMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: { Text(model.errorMessage ?? model.completionMessage ?? "") }
    }

    private var mainCard: some View {
        ZStack {
            Color.clear.contentShape(Rectangle()).onTapGesture { focusedElement = nil }
            HStack(alignment: .top, spacing: 24) {
                coverColumn
                VStack(alignment: .leading, spacing: 16) {
                    metadataFields
                    tracksPanel
                }.frame(width: 513)
            }
        }
        .padding(24)
        .background(AppTheme.primaryBackground)
        .frame(width: 778)
    }

    private var coverColumn: some View {
        VStack(spacing: 14) {
            coverControl
            Spacer(minLength: 0)
            Button(model.isRenaming ? model.renameProgress : (model.tracks.isEmpty ? "Rename" : "Rename \(model.tracks.count) mp3\(model.tracks.count == 1 ? "" : "s")")) {
                focusedElement = .rename
                model.performRename()
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(model.tracks.isEmpty || !model.canRename || model.isRenaming)
            .overlay {
                if focusedElement == .rename && !model.tracks.isEmpty && model.canRename && !model.isRenaming {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(AppTheme.accent, lineWidth: 1)
                        .frame(width: 196, height: 36)
                }
            }
            if !model.tracks.isEmpty {
                Button("Choose a folder") { chooseFolder() }.buttonStyle(SecondaryButtonStyle())
            }
        }.frame(minHeight: cardContentHeight).frame(width: 192)
    }

    private var cardContentHeight: CGFloat { max(238, 130 + 32 + trackListHeight) }

    private var coverControl: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(AppTheme.tertiaryBackground)
            if let data = model.coverData, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill().clipShape(RoundedRectangle(cornerRadius: 10))
            } else if !model.tracks.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "photo").font(.system(size: 27))
                    Text("Paste or browse\nto add cover")
                        .font(.system(size: 14)).multilineTextAlignment(.center).frame(width: 110)
                    Button("Browse") { importingCover = true }
                        .buttonStyle(SecondaryButtonStyle()).frame(width: 76)
                }.foregroundStyle(AppTheme.secondaryText)
            }
        }
        .frame(width: 192, height: 192)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(AppTheme.accent, lineWidth: 2).opacity(focusedElement == .cover && !model.tracks.isEmpty ? 1 : 0))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .onTapGesture { if !model.tracks.isEmpty { focusedElement = .cover } }
        .background(
            CoverPasteReceiver(
                isActive: focusedElement == .cover,
                onPaste: { model.setCover($0) },
                onUnsupportedPaste: { model.errorMessage = "Clipboard does not contain a PNG, JPEG, or TIFF image." }
            )
            .frame(width: 1, height: 1)
        )
        .onDrop(of: [.image], isTargeted: nil) { providers in
            providers.first?.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                if let data { DispatchQueue.main.async { model.setCover(data) } }
            }; return true
        }
        .contextMenu { Button("Choose image…") { importingCover = true }; Button("Paste image") { pasteCover() } }
    }

    private var metadataFields: some View {
        VStack(spacing: 8) {
            fieldset("Artist") {
                HStack(spacing: metadataColumnSpacing) {
                    AlbumTextField(placeholder: model.applyArtistToAll ? "Artist" : "Please specify artists below", text: $model.sharedArtist, isDisabled: !model.applyArtistToAll, focus: $focusedElement, focusValue: .sharedArtist, onTab: { advanceFocus(reverse: $0) })
                        .frame(width: metadataLeadingColumnWidth)
                    Toggle("Apply to all tracks", isOn: $model.applyArtistToAll)
                        .toggleStyle(.checkbox).font(.system(size: 12, weight: .medium)).foregroundStyle(AppTheme.bodyText)
                        .fixedSize().frame(width: metadataTrailingColumnWidth, alignment: .leading)
                }
            }
            HStack(spacing: metadataColumnSpacing) {
                fieldset("Album") { AlbumTextField(placeholder: "Album", text: $model.album, focus: $focusedElement, focusValue: .album, onTab: { advanceFocus(reverse: $0) }) }.frame(width: metadataLeadingColumnWidth)
                fieldset("Year") { AlbumTextField(placeholder: "Year", text: $model.year, focus: $focusedElement, focusValue: .year, onTab: { advanceFocus(reverse: $0) }) }.frame(width: metadataTrailingColumnWidth)
            }
        }
    }

    private func fieldset<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 14, weight: .medium)).foregroundStyle(AppTheme.primaryText)
            content()
        }
    }

    private var tracksPanel: some View {
        Group {
            if model.tracks.isEmpty {
                emptyTracks
            } else {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Text("\u{00A0}#").frame(width: 40, alignment: .leading)
                        if !model.applyArtistToAll { Text("Artist").frame(maxWidth: .infinity, alignment: .leading) }
                        Text("Track title").frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.system(size: 14)).foregroundStyle(AppTheme.primaryText).padding(.horizontal, 8).frame(height: 32).background(AppTheme.tertiaryBackground)
                    populatedTracks
                }
            }
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(AppTheme.lightStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var emptyTracks: some View {
        VStack { Button("Choose a folder") { chooseFolder() }.buttonStyle(SecondaryButtonStyle()).frame(width: 131) }
            .frame(maxWidth: .infinity)
            // Extends the empty panel to the same baseline as the left-side Rename button.
            .frame(height: cardContentHeight - 116)
            .padding(.horizontal, 8)
    }

    private var populatedTracks: some View {
        ScrollView {
            LazyVStack(spacing: trackRowSpacing) {
                ForEach(model.tracks.indices, id: \.self) { index in trackRow(at: index) }
            }.padding(8)
        }
        .frame(height: trackListHeight)
    }

    private func trackRow(at index: Int) -> some View {
        let track = Binding<Track>(
            get: { model.tracks[index] },
            set: { model.tracks[index] = $0 }
        )
        let currentTrack = model.tracks[index]
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                AlbumTextField(placeholder: "##", text: model.trackNumberBinding(for: track), focus: $focusedElement, focusValue: .trackNumber(currentTrack.id), onTab: { advanceFocus(reverse: $0) }).frame(width: 40)
                if !model.applyArtistToAll { AlbumTextField(placeholder: "Artist", text: track.artist, focus: $focusedElement, focusValue: .trackArtist(currentTrack.id), onTab: { advanceFocus(reverse: $0) }).frame(maxWidth: .infinity) }
                AlbumTextField(placeholder: "Track title", text: track.title, focus: $focusedElement, focusValue: .trackTitle(currentTrack.id), onTab: { advanceFocus(reverse: $0) }).frame(maxWidth: .infinity)
            }
            Text(previewName(for: currentTrack, displayedTrackNumber: model.previewTrackNumber(for: currentTrack)))
                .id("\(currentTrack.id)-\(model.previewTrackNumber(for: currentTrack))-\(model.previewRefreshID)")
                .font(.system(size: 12)).foregroundStyle(currentTrack.metadataReadable ? AppTheme.secondaryText : AppTheme.danger)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 14, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }.frame(height: trackRowHeight)
    }

    private func previewName(for track: Track, displayedTrackNumber: String) -> String {
        let artist = model.applyArtistToAll ? model.sharedArtist : track.artist
        let displayedArtist = artist.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Artist" : artist
        let displayedAlbum = model.album.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Album" : model.album
        let displayedTitle = track.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Track title" : track.title
        let displayedNumber: String
        let normalizedTrackNumber = displayedTrackNumber.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        if let number = Int(normalizedTrackNumber), number > 0 {
            displayedNumber = String(format: "%02d", number)
        } else {
            displayedNumber = "##"
        }
        return "\(TextSanitizer.fileComponent(displayedArtist)) - \(TextSanitizer.fileComponent(displayedAlbum)) - \(displayedNumber) - \(TextSanitizer.fileComponent(displayedTitle)).mp3"
    }

    private var inputOrder: [InputFocus] {
        var fields: [InputFocus] = model.applyArtistToAll ? [.sharedArtist, .album, .year] : [.album, .year]
        for track in model.tracks {
            fields.append(.trackNumber(track.id))
            if !model.applyArtistToAll { fields.append(.trackArtist(track.id)) }
            fields.append(.trackTitle(track.id))
        }
        if !model.tracks.isEmpty { fields.append(.rename) }
        return fields
    }

    private func advanceFocus(reverse: Bool) {
        let fields = inputOrder
        guard !fields.isEmpty else { return }
        guard let focusedElement, let index = fields.firstIndex(of: focusedElement) else {
            self.focusedElement = reverse ? fields.last : fields.first
            return
        }
        let next = reverse ? (index - 1 + fields.count) % fields.count : (index + 1) % fields.count
        self.focusedElement = fields[next]
    }

    private func pasteCover() {
        if let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
           let tiff = image.tiffRepresentation { model.setCover(tiff) }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        let delegate = AlbumFolderPanelDelegate()
        panel.title = "Choose an MP3 album folder"
        panel.message = "Choose the folder containing this album's MP3 files."
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.delegate = delegate
        panel.directoryURL = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask).first
        panel.begin { response in
            _ = delegate // Keep the panel's weak delegate alive until dismissal.
            if response == .OK, let url = panel.url { model.loadFolder(url) }
        }
    }

    private func acceptDroppedFolder(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            let url: URL?
            if let fileURL = item as? URL {
                url = fileURL
            } else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else {
                url = nil
            }
            DispatchQueue.main.async {
                guard let url, url.hasDirectoryPath else { return }
                guard AlbumFolderValidator.isValid(url) else {
                    showInvalidFolderAlert()
                    return
                }
                model.loadFolder(url)
            }
        }
        return true
    }

    private func showInvalidFolderAlert() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "No MP3 files found"
        alert.informativeText = "Choose a folder containing at least one MP3 file."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

private final class AlbumFolderPanelDelegate: NSObject, NSOpenSavePanelDelegate {
    func panel(_ sender: Any, shouldEnable url: URL) -> Bool {
        AlbumFolderValidator.isValid(url)
    }
}
