import SwiftUI
import AppKit

enum AppTheme {
    static func color(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(red: value.0, green: value.1, blue: value.2, alpha: 1)
        })
    }

    static let primaryText = color(light: (0, 0, 0), dark: (1, 1, 1))
    static let headingText = color(light: (0.114, 0.114, 0.122), dark: (0.96, 0.96, 0.98))
    static let bodyText = color(light: (0.227, 0.227, 0.235), dark: (0.87, 0.87, 0.88))
    static let secondaryText = color(light: (0.431, 0.431, 0.451), dark: (0.63, 0.63, 0.65))
    static let tertiaryText = color(light: (0.557, 0.557, 0.576), dark: (0.49, 0.49, 0.51))
    static let primaryBackground = color(light: (1, 1, 1), dark: (0.11, 0.11, 0.12))
    // Figma: background/secondary (#F7F7F7 in light mode).
    static let secondaryBackground = color(light: (247.0 / 255.0, 247.0 / 255.0, 247.0 / 255.0), dark: (0.14, 0.14, 0.15))
    static let tertiaryBackground = color(light: (0.898, 0.898, 0.918), dark: (0.22, 0.22, 0.23))
    static let mutedBackground = color(light: (0.818, 0.818, 0.818), dark: (0.26, 0.26, 0.27))
    static let disabledBackground = color(light: (0.622, 0.622, 0.622), dark: (0.34, 0.34, 0.34))
    static let lightStroke = color(light: (0.824, 0.824, 0.843), dark: (0.26, 0.26, 0.28))
    static let defaultStroke = color(light: (0.78, 0.78, 0.8), dark: (0.3, 0.3, 0.32))
    static let accent = color(light: (0, 0.478, 1), dark: (0.04, 0.52, 1))
    static let accentLight = color(light: (0.298, 0.631, 0.992), dark: (0.24, 0.60, 1))
    static let danger = color(light: (0.907, 0.081, 0.081), dark: (0.91, 0.175, 0.175))
}

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? (isHovered ? AppTheme.accentLight : AppTheme.accent).opacity(configuration.isPressed ? 0.78 : 1) : AppTheme.disabledBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onHover { isHovered = isEnabled && $0 }
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration)
    }
}

private struct SecondaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    var body: some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(isEnabled ? AppTheme.bodyText : AppTheme.tertiaryText)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(isEnabled && (isHovered || configuration.isPressed) ? AppTheme.tertiaryBackground : AppTheme.primaryBackground)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.lightStroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .onHover { isHovered = isEnabled && $0 }
    }
}

struct AlbumTextField<FocusValue: Hashable>: View {
    let placeholder: String
    @Binding var text: String
    var isDisabled = false
    @Binding var focus: FocusValue?
    let focusValue: FocusValue
    var onTab: ((Bool) -> Void)?

    var body: some View {
        let hasFocus = !isDisabled && focus == focusValue
        NativeTextField(
            text: $text, placeholder: placeholder, isEnabled: !isDisabled,
            isFocused: hasFocus,
            onFocus: { if !isDisabled { focus = focusValue } }, onTab: onTab
        )
            .padding(.horizontal, 8)
            .frame(height: 32)
            .background(isDisabled ? AppTheme.mutedBackground : AppTheme.secondaryBackground)
            // The updated Figma component intentionally uses fill alone for
            // resting and disabled fields. Only an enabled focused field gets
            // the 2 pt accent outline.
            .overlay {
                if hasFocus {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(AppTheme.accent, lineWidth: 2)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
