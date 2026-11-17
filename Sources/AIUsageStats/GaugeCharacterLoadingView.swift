import AppKit
import SwiftUI

struct GaugeCharacterLoadingView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { context in
            let pose = GaugeCharacterPose(elapsed: reduceMotion ? 0 : context.date.timeIntervalSince(start))
            Canvas { graphics, size in pose.draw(in: &graphics, size: size) }
        }
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct GaugeCharacterPose {
    @MainActor static let head = Bundle.appResources
        .url(forResource: "gauge-head-blank", withExtension: "png", subdirectory: "Character")
        .flatMap(NSImage.init(contentsOf:))
        .map(Image.init(nsImage:))

    let needleRadians: Double
    let eyeOpening: Double

    init(elapsed: TimeInterval) {
        let sweep = elapsed.truncatingRemainder(dividingBy: 2.4) / 2.4
        needleRadians = (-113 * cos(2 * .pi * sweep) + 2.5 * sin(14 * .pi * sweep)) * .pi / 180
        let blink = elapsed.truncatingRemainder(dividingBy: 3.7)
        eyeOpening = blink < 0.16 ? max(abs(cos(.pi * blink / 0.16)), 0.12) : 1
    }

    @MainActor func draw(in graphics: inout GraphicsContext, size: CGSize) {
        let side = min(size.width, size.height)
        let ink = GraphicsContext.Shading.color(Color(red: 0.071, green: 0.075, blue: 0.071))
        if let head = Self.head {
            graphics.draw(head, in: CGRect(x: 0, y: 0, width: side, height: side))
        }
        for eyeX in [0.4511, 0.6736] {
            let center = CGPoint(x: (eyeX + 0.012 * sin(needleRadians)) * side, y: 0.5223 * side)
            let width = 0.0598 * side
            let height = 0.1016 * side * eyeOpening
            graphics.fill(Path(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)),
                          with: ink)
        }
        let hub = CGPoint(x: 0.5181 * side, y: 0.2000 * side)
        var needle = Path()
        needle.move(to: hub)
        needle.addLine(to: CGPoint(x: hub.x + 0.1333 * side * sin(needleRadians), y: hub.y - 0.1333 * side * cos(needleRadians)))
        graphics.stroke(needle, with: ink, style: StrokeStyle(lineWidth: 0.0229 * side, lineCap: .round))
        let hubRadius = 0.0290 * side
        graphics.fill(Path(ellipseIn: CGRect(x: hub.x - hubRadius, y: hub.y - hubRadius, width: hubRadius * 2, height: hubRadius * 2)),
                      with: ink)
    }
}
