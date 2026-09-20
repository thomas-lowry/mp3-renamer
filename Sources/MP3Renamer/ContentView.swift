import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {
    private enum InputFocus: Hashable {
        case cover, sharedArtist, album, year, rename
        case trackNumber(UUID), trackArtist(UUID), trackTitle(UUID)
    }

    @ObservedObject var model: AlbumViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var importingCover = false
    @State private var focusedElement: InputFocus?
    @State private var lastAutoScrollCheckpoint: Int?
    @State private var isCoverDropTarget = false
    @State private var isFolderDropTarget = false
    @State private var dropInspectionID = UUID()
    @State private var coverDropPulseOpacity: Double = 1
    @State private var coverDropPulseScale: CGFloat = 1
    @State private var coverDropPulseTask: Task<Void, Never>?

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
        dropAwareCard
            .frame(width: 778)
            .fixedSize(horizontal: true, vertical: true)
        .fileImporter(isPresented: $importingCover, allowedContentTypes: [.png, .jpeg]) { result in
            if case let .success(url) = result, let data = try? Data(contentsOf: url) { model.setCover(data) }
        }
        .onChange(of: model.folderURL) { _, _ in
            focusedElement = nil
            lastAutoScrollCheckpoint = nil
            clearDropTargets()
        }
        .onChange(of: model.applyArtistToAll) { _, isSharedArtistEnabled in
            if !isSharedArtistEnabled, focusedElement == .sharedArtist { focusedElement = nil }
        }
        .onChange(of: isCoverDropTarget) { _, isTargeted in updateCoverDropPulse(isTargeted: isTargeted) }
        .onChange(of: reduceMotion) { _, _ in updateCoverDropPulse(isTargeted: isCoverDropTarget) }
        .onDisappear { stopCoverDropPulse() }
        .alert("MP3 Renamer", isPresented: Binding(get: { model.errorMessage != nil || model.completionMessage != nil }, set: { _ in model.errorMessage = nil; model.completionMessage = nil })) {
            Button("OK", role: .cancel) { }
        } message: { Text(model.errorMessage ?? model.completionMessage ?? "") }
    }

    private var dropAwareCard: some View {
        mainCard
            .overlay {
                // Figma's folder-drop state is a 12 pt rounded container with
                // its 2 pt accent stroke entirely inside the window content.
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(AppTheme.accent, lineWidth: 2)
                    .opacity(isFolderDropTarget ? 1 : 0)
                    .allowsHitTesting(false)
            }
            .onDrop(
                of: [.fileURL, .png, .jpeg],
                delegate: AlbumDropDelegate(
                    entered: inspectDraggedItems,
                    exited: clearDropTargets,
                    performed: acceptDroppedItem
                )
            )
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
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
        // The focus/drop ring is a separate, static layer. The Figma pulse is
        // an additional transient ring, so the control never appears to lose
        // focus while its outer ring is fading and scaling.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(AppTheme.accent, lineWidth: 2)
                .opacity((focusedElement == .cover || isCoverDropTarget) && !model.tracks.isEmpty ? 1 : 0)
        )
        .overlay {
            if isCoverDropTarget && !model.tracks.isEmpty && model.coverData == nil {
                RoundedRectangle(cornerRadius: 10)
                    .stroke(AppTheme.accent, lineWidth: 2)
                    .scaleEffect(coverDropPulseScale)
                    .opacity(coverDropPulseOpacity)
                    .allowsHitTesting(false)
            }
        }
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
        .contextMenu { Button("Choose image…") { importingCover = true }; Button("Paste image") { pasteCover() } }
    }

    private var metadataFields: some View {
        VStack(spacing: 8) {
            fieldset("Artist") {
                HStack(spacing: metadataColumnSpacing) {
                    AlbumTextField(placeholder: model.applyArtistToAll ? "Artist" : "Please specify artists below", text: $model.sharedArtist, isDisabled: !model.applyArtistToAll, focus: $focusedElement, focusValue: .sharedArtist, onTab: { advanceFocus(reverse: $0) })
                        .frame(width: metadataLeadingColumnWidth)
                    Toggle("Same for all", isOn: $model.applyArtistToAll)
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
        ScrollViewReader { proxy in
            trackScrollView(proxy: proxy)
        }
        // Folder changes intentionally replace every native text field rather
        // than allowing SwiftUI to retain a field from the prior album.
        .id(model.folderURL?.standardizedFileURL.path ?? "no-folder")
        .frame(height: trackListHeight)
    }

    private func trackScrollView(proxy: ScrollViewProxy) -> some View {
        ScrollView {
            LazyVStack(spacing: trackRowSpacing) {
                // Bind rows by their stable track identity. A folder switch
                // replaces `tracks` in one update, so an index-based binding can
                // otherwise be evaluated after the old array is gone.
                ForEach($model.tracks) { $track in
                    trackRow($track).id(track.id)
                }
            }
            .padding(8)
        }
        .onChange(of: focusedElement) { _, newFocus in
            guard let trackID = trackID(for: newFocus),
                  let checkpoint = scrollCheckpoint(for: trackID),
                  lastAutoScrollCheckpoint != checkpoint else { return }
            lastAutoScrollCheckpoint = checkpoint
            // Start the checkpoint row at the top. This reveals the following
            // tracks and leaves the row's filename preview in view; ScrollView
            // naturally clamps this position when the remaining rows fit.
            DispatchQueue.main.async {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(trackID, anchor: .top)
                }
            }
        }
    }

    private func trackID(for focus: InputFocus?) -> UUID? {
        switch focus {
        case let .trackNumber(id), let .trackArtist(id), let .trackTitle(id): return id
        default: return nil
        }
    }

    private func scrollCheckpoint(for trackID: UUID) -> Int? {
        guard model.tracks.count > visibleTrackCount,
              let index = model.tracks.firstIndex(where: { $0.id == trackID }) else { return nil }
        // With eight visible rows, track 7 is one from the bottom. The next
        // checkpoint is likewise one from the bottom after the prior scroll.
        let step = max(visibleTrackCount - 2, 1)
        guard index >= step, index.isMultiple(of: step) else { return nil }
        return index
    }

    private func trackRow(_ track: Binding<Track>) -> some View {
        let currentTrack = track.wrappedValue
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
                // Keep the extension visible for long planned filenames.
                .truncationMode(.middle)
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

    private func acceptDroppedItem(_ providers: [NSItemProvider]) -> Bool {
        let canAcceptCover = !model.tracks.isEmpty
        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let fileURL = item as? URL {
                    url = fileURL
                } else if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = nil
                }
                guard let url else { return }
                if url.hasDirectoryPath {
                    DispatchQueue.main.async {
                        guard AlbumFolderValidator.isValid(url) else {
                            showInvalidFolderAlert()
                            return
                        }
                        clearDropTargets()
                        model.loadFolder(url)
                    }
                    return
                }
                guard canAcceptCover,
                      ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()),
                      let data = try? Data(contentsOf: url) else { return }
                DispatchQueue.main.async { model.setCover(data) }
            }
            return true
        }

        // A cover belongs to a loaded album only. When no album is loaded, the
        // only accepted drop is a valid directory.
        guard !model.tracks.isEmpty else { return false }
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
            if let data { DispatchQueue.main.async { model.setCover(data) } }
        }
        return true
    }

    private func inspectDraggedItems(_ providers: [NSItemProvider]) {
        let inspectionID = UUID()
        dropInspectionID = inspectionID
        isFolderDropTarget = false
        isCoverDropTarget = false

        if let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) {
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
                    guard inspectionID == dropInspectionID, let url else { return }
                    if url.hasDirectoryPath {
                        isFolderDropTarget = true
                    } else if !model.tracks.isEmpty,
                              ["png", "jpg", "jpeg"].contains(url.pathExtension.lowercased()) {
                        isCoverDropTarget = true
                    }
                }
            }
            return
        }

        if !model.tracks.isEmpty,
           providers.contains(where: { $0.hasItemConformingToTypeIdentifier(UTType.image.identifier) }) {
            isCoverDropTarget = true
        }
    }

    private func clearDropTargets() {
        dropInspectionID = UUID()
        isFolderDropTarget = false
        isCoverDropTarget = false
    }

    private func updateCoverDropPulse(isTargeted: Bool) {
        guard isTargeted, !model.tracks.isEmpty, model.coverData == nil, !reduceMotion else {
            stopCoverDropPulse()
            return
        }
        guard coverDropPulseTask == nil else { return }
        coverDropPulseOpacity = 1
        coverDropPulseScale = 1
        coverDropPulseTask = Task { @MainActor in
            while !Task.isCancelled {
                withAnimation(.timingCurve(0.5, 0, 0.5, 1, duration: 0.8)) {
                    coverDropPulseOpacity = 0
                }
                withAnimation(.timingCurve(0.42, 0, 0.024, 1, duration: 0.8)) {
                    coverDropPulseScale = 0.828
                }
                do { try await Task.sleep(nanoseconds: 800_000_000) } catch { return }
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    coverDropPulseOpacity = 1
                    coverDropPulseScale = 1
                }
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
            }
        }
    }

    private func stopCoverDropPulse() {
        coverDropPulseTask?.cancel()
        coverDropPulseTask = nil
        coverDropPulseOpacity = 1
        coverDropPulseScale = 1
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

/// SwiftUI's `isTargeted` only says that one of the registered types is over
/// the view. This delegate gives the UI the providers themselves so it can
/// distinguish a folder (app-level drop) from an artwork image (cover drop).
private struct AlbumDropDelegate: DropDelegate {
    let entered: ([NSItemProvider]) -> Void
    let exited: () -> Void
    let performed: ([NSItemProvider]) -> Bool

    func validateDrop(info: DropInfo) -> Bool { true }

    func dropEntered(info: DropInfo) {
        entered(info.itemProviders(for: [.fileURL, .png, .jpeg]))
    }

    func dropExited(info: DropInfo) {
        exited()
    }

    func performDrop(info: DropInfo) -> Bool {
        let didAccept = performed(info.itemProviders(for: [.fileURL, .png, .jpeg]))
        exited()
        return didAccept
    }
}
