# MP3 Renamer

## Build an installable app

On macOS, run:

```sh
./Scripts/package-app.sh
```

This builds a universal (Apple Silicon and Intel) `MP3 Renamer.app` and an
installable disk image at `dist/MP3 Renamer.dmg`. Open the DMG and drag the app
to the included Applications shortcut. The package uses the light Figma icon in
the Finder and Dock; the matching dark source export is retained in `Assets/`.

The first-release DMG is ad-hoc signed for local use. To distribute it publicly
without Gatekeeper warnings, sign with an Apple Developer *Developer ID*
certificate and notarize the DMG with Apple.
