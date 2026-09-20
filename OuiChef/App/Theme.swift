import SwiftUI

enum Theme {
    static let cream = Color(red: 0.97, green: 0.953, blue: 0.918)
    static let ink = Color(red: 0.14, green: 0.15, blue: 0.115)
    static let green = Color(red: 0.27, green: 0.31, blue: 0.20)
    static let sage = Color(red: 0.90, green: 0.875, blue: 0.817)
    static let orange = Color(red: 0.86, green: 0.40, blue: 0.19)
    static func serif(_ size: CGFloat) -> Font { .system(size: size, weight: .regular, design: .serif) }
}

struct FilledButton: ButtonStyle {
    var color = Theme.green
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.body, design: .rounded).weight(.medium))
            .frame(maxWidth: .infinity).padding(.vertical, 16)
            .foregroundStyle(.white).background(color, in: Capsule())
            .opacity(!isEnabled ? 0.4 : configuration.isPressed ? 0.75 : 1)
    }
}

struct VoiceOrb: View {
    var active = false
    var size: CGFloat = 130
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var glow = false

    var body: some View {
        ZStack {
            Circle().stroke(Theme.green.opacity(0.10), lineWidth: 1).padding(1)
            Circle().stroke(Theme.green.opacity(0.14), lineWidth: 1).padding(10)
            Circle().fill(RadialGradient(colors: [Theme.green, Theme.green.opacity(0.85), Theme.sage], center: .center, startRadius: 3, endRadius: size * 0.43))
                .padding(20).shadow(color: Theme.sage, radius: active ? 18 : 8)
            HStack(spacing: size * 0.035) {
                ForEach(Array([0.15, 0.25, 0.36, 0.24, 0.13].enumerated()), id: \.offset) { index, height in
                    Capsule().fill(.white).frame(width: size * 0.036, height: size * height * (glow && active ? (index.isMultiple(of: 2) ? 0.75 : 1.15) : 1))
                }
            }
        }
        .frame(width: size, height: size)
        .onChange(of: active, initial: true) { _, active in
            glow = false
            if active && !reduceMotion { withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) { glow = true } }
        }
        .accessibilityHidden(true)
    }
}

struct RecipeArtwork: View {
    let style: ChefStyle
    var body: some View {
        ZStack {
            LinearGradient(colors: style == .tequila ? [Color(red: 0.91, green: 0.91, blue: 0.76), Theme.sage] : [Color(red: 0.92, green: 0.85, blue: 0.70), Theme.cream], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(.white.opacity(0.30)).frame(width: 240, height: 240).offset(x: 95, y: -45)
            Circle().stroke(.white.opacity(0.65), lineWidth: 2).frame(width: 155, height: 155)
            Circle().fill(Theme.cream).frame(width: 138, height: 138).shadow(color: Theme.ink.opacity(0.13), radius: 15, x: 0, y: 9)
            Image(systemName: style.symbol).font(.system(size: 60, weight: .ultraLight)).foregroundStyle(style == .pasta ? Theme.orange : Theme.green)
            Image(systemName: "leaf.fill").font(.system(size: 32)).rotationEffect(.degrees(-35)).foregroundStyle(Theme.green.opacity(0.75)).offset(x: -88, y: 37)
            Image(systemName: "leaf").font(.system(size: 24)).rotationEffect(.degrees(35)).foregroundStyle(Theme.green.opacity(0.6)).offset(x: 85, y: -45)
        }
        .clipped().accessibilityHidden(true)
    }
}

extension View {
    func kitchenCard() -> some View {
        self.padding(18).frame(maxWidth: .infinity, alignment: .leading)
            .background(.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 22))
            .overlay(RoundedRectangle(cornerRadius: 22).stroke(Theme.green.opacity(0.09)))
    }
}

struct IngredientArtwork: View {
    let food: Food?
    var symbol = "leaf"
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let asset = food?.spriteAsset, let image = UIImage(named: asset) {
                Image(uiImage: image).resizable().scaledToFit()
            } else {
                Image(systemName: symbol).font(.system(size: size * 0.44, weight: .light))
                    .foregroundStyle(Theme.green).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.sage.opacity(0.6), in: Circle())
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}
