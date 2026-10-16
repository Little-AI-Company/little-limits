import AppKit
import UsageCore

struct StatusItemSummary: Equatable {
    struct Reading: Equatable {
        let provider: Provider
        let remainingPercent: Int?
    }

    let readings: [Reading]
    let isStale: Bool
}

@MainActor
enum StatusItemImage {
    /// The app's talking-gauge mark: a speech bubble whose top is a fuel gauge with the needle near empty.
    /// Shown when there are no readings to summarize. Drawn as a template so AppKit tints it.
    static let appGlyph: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: false) { _ in
            NSColor.black.set()
            let bubble = NSBezierPath()
            bubble.lineWidth = 1.6
            bubble.lineJoinStyle = .round
            bubble.lineCapStyle = .round
            // Gauge arc over the top, then the flat base with a tail at the lower left.
            bubble.appendArc(withCenter: NSPoint(x: 9.5, y: 7), radius: 6.6, startAngle: 0, endAngle: 180)
            bubble.line(to: NSPoint(x: 2.9, y: 6.2))
            bubble.line(to: NSPoint(x: 2.2, y: 1.6))
            bubble.line(to: NSPoint(x: 6.4, y: 4.6))
            bubble.line(to: NSPoint(x: 15.2, y: 4.6))
            bubble.curve(to: NSPoint(x: 16.1, y: 7), controlPoint1: NSPoint(x: 15.9, y: 4.6), controlPoint2: NSPoint(x: 16.1, y: 5.6))
            bubble.stroke()
            let needle = NSBezierPath()
            needle.lineWidth = 1.6
            needle.lineCapStyle = .round
            needle.move(to: NSPoint(x: 9.5, y: 7))
            needle.line(to: NSPoint(x: 5.3, y: 9.6))
            needle.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.2, y: 5.7, width: 2.6, height: 2.6)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Limits Left"
        return image
    }()

    static func render(_ summary: StatusItemSummary) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let labels = summary.readings.map { $0.remainingPercent.map { "\($0)%" } ?? "?" }
        let sizes = labels.map { ($0 as NSString).size(withAttributes: attributes) }
        let iconSize: CGFloat = 14
        let valueSpacing: CGFloat = 3
        let providerSpacing: CGFloat = 9
        let height: CGFloat = 18
        let indicatorSize = ("!" as NSString).size(withAttributes: attributes)
        let width = sizes.reduce(0) { $0 + iconSize + valueSpacing + ceil($1.width) }
            + CGFloat(max(0, labels.count - 1)) * providerSpacing
            + (summary.isStale ? 5 + ceil(indicatorSize.width) : 0)
        let image = NSImage(size: NSSize(width: width, height: height))
        for scale in [1, 2] {
            guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width) * scale, pixelsHigh: Int(height) * scale,
                                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { continue }
            bitmap.size = image.size
            bitmap.isOpaque = false
            guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { continue }
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            var x: CGFloat = 0
            for (index, reading) in summary.readings.enumerated() {
                ProviderIcons.images[reading.provider]?.draw(in: NSRect(x: x, y: (height - iconSize) / 2, width: iconSize, height: iconSize))
                x += iconSize + valueSpacing
                (labels[index] as NSString).draw(at: NSPoint(x: x, y: floor((height - sizes[index].height) / 2)), withAttributes: attributes)
                x += ceil(sizes[index].width) + providerSpacing
            }
            if summary.isStale {
                ("!" as NSString).draw(at: NSPoint(x: width - ceil(indicatorSize.width), y: floor((height - indicatorSize.height) / 2)), withAttributes: attributes)
            }
            NSGraphicsContext.restoreGraphicsState()
            image.addRepresentation(bitmap)
        }
        image.isTemplate = true
        return image
    }
}
