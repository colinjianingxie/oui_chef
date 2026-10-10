import SwiftUI

/// One vector master, shared by onboarding, voice, and cooking milestones.
struct ChefMascot: View {
    var size: CGFloat = 64
    var body: some View {
        Canvas { context, bounds in
            let scale = min(bounds.width, bounds.height) / 100
            context.scaleBy(x: scale, y: scale)
            func draw(_ path: Path, fill: Color, outline: Bool = false) {
                context.fill(path, with: .color(fill))
                if outline { context.stroke(path, with: .color(Theme.plum), style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)) }
            }
            draw(Path(ellipseIn: CGRect(x: 8, y: 54, width: 25, height: 27)), fill: Theme.plum)
            draw(Path(ellipseIn: CGRect(x: 22, y: 34, width: 62, height: 55)), fill: Theme.plum)
            var neck = Path()
            neck.move(to: CGPoint(x: 43, y: 80)); neck.addLine(to: CGPoint(x: 35, y: 93))
            neck.addQuadCurve(to: CGPoint(x: 70, y: 93), control: CGPoint(x: 51, y: 87))
            neck.addLine(to: CGPoint(x: 63, y: 79)); neck.closeSubpath()
            draw(neck, fill: .white, outline: true)
            draw(Path(ellipseIn: CGRect(x: 29, y: 42, width: 48, height: 44)), fill: .white, outline: true)
            var fringe = Path()
            fringe.move(to: CGPoint(x: 24, y: 53))
            fringe.addQuadCurve(to: CGPoint(x: 57, y: 42), control: CGPoint(x: 44, y: 61))
            fringe.addQuadCurve(to: CGPoint(x: 80, y: 59), control: CGPoint(x: 63, y: 57))
            fringe.addLine(to: CGPoint(x: 76, y: 36)); fringe.addLine(to: CGPoint(x: 30, y: 37)); fringe.closeSubpath()
            draw(fringe, fill: Theme.plum)
            var hat = Path()
            hat.move(to: CGPoint(x: 31, y: 41)); hat.addLine(to: CGPoint(x: 30, y: 27))
            hat.addCurve(to: CGPoint(x: 24, y: 9), control1: CGPoint(x: 9, y: 28), control2: CGPoint(x: 12, y: 10))
            hat.addQuadCurve(to: CGPoint(x: 40, y: 13), control: CGPoint(x: 34, y: 5))
            hat.addCurve(to: CGPoint(x: 59, y: 10), control1: CGPoint(x: 42, y: 0), control2: CGPoint(x: 55, y: 0))
            hat.addCurve(to: CGPoint(x: 75, y: 29), control1: CGPoint(x: 76, y: -1), control2: CGPoint(x: 94, y: 19))
            hat.addLine(to: CGPoint(x: 75, y: 41)); hat.closeSubpath()
            draw(hat, fill: .white, outline: true)
            for x in [41.0, 63.0] { draw(Path(ellipseIn: CGRect(x: x, y: 62, width: 5, height: 6)), fill: Theme.plum) }
            var smile = Path(); smile.move(to: CGPoint(x: 50, y: 74))
            smile.addQuadCurve(to: CGPoint(x: 58, y: 74), control: CGPoint(x: 54, y: 79))
            context.stroke(smile, with: .color(Theme.plum), style: StrokeStyle(lineWidth: 2.8, lineCap: .round))
            var scarf = Path(); scarf.move(to: CGPoint(x: 43, y: 87)); scarf.addLine(to: CGPoint(x: 56, y: 91))
            scarf.addLine(to: CGPoint(x: 62, y: 86)); scarf.addLine(to: CGPoint(x: 59, y: 97))
            scarf.addLine(to: CGPoint(x: 52, y: 92)); scarf.closeSubpath(); draw(scarf, fill: Theme.plum)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ChefCallout: View {
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            ChefMascot(size: 54)
            Text(text).font(.subheadline).foregroundStyle(Theme.plum).lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.padding(16).background(Theme.blush.opacity(0.55), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct SectionEyebrow: View {
    let title: String
    var body: some View {
        Text(title.uppercased()).font(.caption2.weight(.semibold)).tracking(2).foregroundStyle(Theme.berry)
    }
}

struct MicrophoneRings: View {
    var active = false
    var symbol = "mic.fill"
    var size: CGFloat = 72
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle().fill(Theme.blush.opacity(active ? 0.9 : 0.45))
            Circle().fill(Theme.berry.opacity(active ? 0.22 : 0.10)).padding(size * 0.10)
            Circle().fill(Theme.berry.opacity(0.35)).padding(size * 0.19)
            Circle().fill(Theme.plum).padding(size * 0.27)
            Image(systemName: symbol).font(.system(size: size * 0.23, weight: .medium)).foregroundStyle(.white)
        }.frame(width: size, height: size)
            .scaleEffect(active && pulse ? 1.04 : 1)
            .animation(active && !reduceMotion ? .easeInOut(duration: 1.2).repeatForever(autoreverses: true) : .default, value: pulse)
            .onChange(of: active, initial: true) { _, value in pulse = value && !reduceMotion }
            .accessibilityHidden(true)
    }
}
