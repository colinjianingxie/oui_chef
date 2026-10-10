import SwiftUI

enum Theme {
    static let cream = Color(red: 250/255, green: 245/255, blue: 238/255)
    static let ink = Color(red: 40/255, green: 35/255, blue: 38/255)
    static let plum = Color(red: 74/255, green: 16/255, blue: 42/255)
    static let berry = Color(red: 163/255, green: 72/255, blue: 101/255)
    static let blush = Color(red: 243/255, green: 223/255, blue: 226/255)
    static let sage = Color(red: 169/255, green: 182/255, blue: 154/255)
    static let muted = Color(red: 108/255, green: 100/255, blue: 105/255)
    static let line = plum.opacity(0.10)
    static let warning = Color(red: 143/255, green: 71/255, blue: 29/255)
    static func serif(_ size: CGFloat) -> Font {
        .system(size: UIFontMetrics(forTextStyle: .title1).scaledValue(for: size), weight: .regular, design: .serif)
    }
}

struct FilledButton: ButtonStyle {
    var color = Theme.plum
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.body.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 24).padding(.vertical, 15)
            .foregroundStyle(.white).background(color, in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}

extension View {
    func kitchenCard() -> some View {
        padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 18))
    }
    // One toolbar per presented screen, including numeric keyboards and multiline editors.
    func keyboardDone() -> some View {
        self.submitLabel(.done)
            .onSubmit { dismissCookingKeyboard() }
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { dismissCookingKeyboard() }.accessibilityIdentifier("keyboard-done")
                }
            }
    }
}

@MainActor func dismissCookingKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
