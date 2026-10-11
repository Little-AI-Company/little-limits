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
