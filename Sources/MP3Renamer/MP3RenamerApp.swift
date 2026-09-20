import SwiftUI
import AppKit

@main
struct MP3RenamerApp: App {
    @StateObject private var model = AlbumViewModel()
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup("MP3 Renamer") {
            ContentView(model: model)
        }
        .windowResizability(.contentSize)
    }
}

/// Swift Package executables are commonly launched by Terminal rather than
/// Launch Services. Explicitly activate the application so the app window,
/// rather than Terminal, receives keyboard commands during development.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { NSApp.windows.first?.makeKeyAndOrderFront(nil) }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        return true
    }
}
