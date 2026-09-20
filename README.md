# MP3 Renamer

A native macOS 14+ SwiftUI app for normalizing album metadata, embedding optional cover art, and renaming a folder's top-level MP3 files.

## Run

Open this folder in Xcode and run the `MP3Renamer` scheme, or run:

```sh
swift run MP3Renamer
```

## Notes

- Folder images are converted to PNG and stored as `cover.png` when the batch is confirmed.
- The app rewrites ID3v2.3 metadata with only title, artist, album, year, track number, and optional front-cover art.
- `swift test` exercises filename formatting, capitalization behavior, and ID3 metadata write/read round-tripping.
