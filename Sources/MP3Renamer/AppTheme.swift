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
    static let secondaryBackground = color(light: (0.98, 0.98, 0.98), dark: (0.14, 0.14, 0.15))
    static let tertiaryBackground = color(light: (0.898, 0.898, 0.918), dark: (0.22, 0.22, 0.23))
    static let mutedBackground = color(light: (0.818, 0.818, 0.818), dark: (0.26, 0.26, 0.27))
    static let disabledBackground = color(light: (0.622, 0.622, 0.622), dark: (0.34, 0.34, 0.34))
    static let lightStroke = color(light: (0.824, 0.824, 0.843), dark: (0.26, 0.26, 0.28))
    static let defaultStroke = color(light: (0.78, 0.78, 0.8), dark: (0.3, 0.3, 0.32))
    static let accent = color(light: (0, 0.478, 1), dark: (0.04, 0.52, 1))
    static let danger = color(light: (0.907, 0.081, 0.081), dark: (0.91, 0.175, 0.175))
}

struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(.white)
            .frame(height: 32)
            .frame(maxWidth: .infinity)
            .background(isEnabled ? AppTheme.accent.opacity(configuration.isPressed ? 0.78 : 1) : AppTheme.disabledBackground)
            .clipShape(RoundedRectangle(cornerRadius: 7))
    }
}

struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14))
            .foregroundStyle(isEnabled ? AppTheme.bodyText : AppTheme.tertiaryText)
            .frame(height: 30)
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? AppTheme.tertiaryBackground : AppTheme.primaryBackground)
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(AppTheme.lightStroke, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 7))
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
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(hasFocus ? AppTheme.accent : AppTheme.defaultStroke, lineWidth: hasFocus ? 2 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
