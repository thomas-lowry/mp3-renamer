import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct NativeTextField: NSViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let isEnabled: Bool
    let isFocused: Bool
    let onFocus: () -> Void
    let onTab: ((Bool) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> NSTextField {
        let field = FocusTextField()
        field.delegate = context.coordinator
        field.onFocus = context.coordinator.focusField
        field.isBezeled = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 14)
        field.textColor = .labelColor
        field.placeholderString = placeholder
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        (field as? FocusTextField)?.onFocus = context.coordinator.focusField
        if field.stringValue != text { field.stringValue = text }
        field.placeholderString = placeholder
        field.isEnabled = isEnabled
        if !isEnabled, field.window?.firstResponder === field.currentEditor() {
            field.window?.makeFirstResponder(nil)
        }
        if isFocused {
            DispatchQueue.main.async {
                guard field.window?.firstResponder !== field.currentEditor() else { return }
                field.window?.makeFirstResponder(field)
            }
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: NativeTextField
        init(parent: NativeTextField) { self.parent = parent }

        func focusField() { parent.onFocus() }
        func controlTextDidBeginEditing(_ notification: Notification) { parent.onFocus() }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            parent.text = field.stringValue
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertTab(_:)) {
                parent.onTab?(false)
                return parent.onTab != nil
            }
            if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
                parent.onTab?(true)
                return parent.onTab != nil
            }
            return false
        }
    }

    final class FocusTextField: NSTextField {
        var onFocus: () -> Void = {}

        override func mouseDown(with event: NSEvent) {
            onFocus()
            super.mouseDown(with: event)
        }

        override func becomeFirstResponder() -> Bool {
            let accepted = super.becomeFirstResponder()
            if accepted { onFocus() }
            return accepted
        }
    }
}

struct CoverPasteReceiver: NSViewRepresentable {
    let isActive: Bool
    let onPaste: (Data) -> Void
    let onUnsupportedPaste: () -> Void

    func makeNSView(context: Context) -> PasteView {
        let view = PasteView()
        view.onPaste = onPaste
        view.onUnsupportedPaste = onUnsupportedPaste
        return view
    }

    func updateNSView(_ view: PasteView, context: Context) {
        view.onPaste = onPaste
        view.onUnsupportedPaste = onUnsupportedPaste
        view.isPasteActive = isActive
        if isActive {
            DispatchQueue.main.async { view.window?.makeFirstResponder(view) }
        } else if view.window?.firstResponder === view {
            view.window?.makeFirstResponder(nil)
        }
    }

    final class PasteView: NSView {
        var onPaste: ((Data) -> Void)?
        var onUnsupportedPaste: (() -> Void)?
        var isPasteActive = false
        private var keyMonitor: Any?
        override var acceptsFirstResponder: Bool { true }

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, self.isPasteActive else { return event }
                let isPaste = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
                    && event.charactersIgnoringModifiers?.lowercased() == "v"
                if isPaste { self.handlePaste(); return nil }
                return event
            }
        }

        required init?(coder: NSCoder) { nil }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            let isPaste = event.modifierFlags.intersection(.deviceIndependentFlagsMask).contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "v"
            if isPaste { handlePaste(); return true }
            return super.performKeyEquivalent(with: event)
        }

        @objc func paste(_ sender: Any?) { handlePaste() }

        private func handlePaste() {
            let pasteboard = NSPasteboard.general
            if let image = NSImage(pasteboard: pasteboard), let data = image.tiffRepresentation {
                onPaste?(data)
                return
            }
            for type in [UTType.png.identifier, UTType.jpeg.identifier, UTType.tiff.identifier] {
                if let data = pasteboard.data(forType: NSPasteboard.PasteboardType(type)) {
                    onPaste?(data)
                    return
                }
            }
            onUnsupportedPaste?()
        }
    }
}
