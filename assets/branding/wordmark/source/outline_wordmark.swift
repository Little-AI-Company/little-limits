// Outlines a line of text with CoreText and prints SVG path data.
// Usage: swift outline_wordmark.swift <font.ttf> <text> <tracking_em> <word_space_em> [index:em,...]
// The optional last argument moves the glyph at that character index, and all later glyphs, by em units.
// Output (stdout): line 1 = "minX minY width height" of the ink bounds, line 2 = path data.
// Units: font size 1000, y axis pointing down, baseline at y = 0.
// Wordmark font: latin-700-normal.ttf (Schibsted Grotesk Bold, Latin subset) from Fontsource
// @fontsource/schibsted-grotesk 5.3.0, https://cdn.jsdelivr.net/fontsource/fonts/schibsted-grotesk@5.3.0/latin-700-normal.ttf
// SHA-256 d7c4b81c2ff8e99614dd8b6ba40fce89e2073e596c2681ee975467106d5b0dcc.
import CoreGraphics
import CoreText
import Foundation

let arguments = CommandLine.arguments
guard arguments.count >= 5,
      let tracking = Double(arguments[3]),
      let wordSpace = Double(arguments[4]) else {
    FileHandle.standardError.write("usage: outline_wordmark.swift <font.ttf> <text> <tracking_em> <word_space_em> [index:em,...]\n".data(using: .utf8)!)
    exit(2)
}
let fontURL = URL(fileURLWithPath: arguments[1])
let text = arguments[2]
let size: CGFloat = 1000
// Optional pair adjustments: "characterIndex:em,..." shifts that glyph and everything after it.
var pairAdjustments: [Int: CGFloat] = [:]
if arguments.count == 6 {
    for item in arguments[5].split(separator: ",") {
        let parts = item.split(separator: ":")
        pairAdjustments[Int(parts[0])!] = CGFloat(Double(parts[1])!) * size
    }
}

guard let provider = CGDataProvider(url: fontURL as CFURL), let graphicsFont = CGFont(provider) else {
    FileHandle.standardError.write("cannot load font\n".data(using: .utf8)!)
    exit(1)
}
let font = CTFontCreateWithGraphicsFont(graphicsFont, size, nil, nil)
let attributes: [NSAttributedString.Key: Any] = [
    NSAttributedString.Key(kCTFontAttributeName as String): font,
]
let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))

// Collect glyphs with their kerned positions from CoreText, then apply tracking and the word space.
var penShift: CGFloat = 0
let combined = CGMutablePath()
for run in CTLineGetGlyphRuns(line) as! [CTRun] {
    let count = CTRunGetGlyphCount(run)
    var glyphs = [CGGlyph](repeating: 0, count: count)
    var positions = [CGPoint](repeating: .zero, count: count)
    var indices = [CFIndex](repeating: 0, count: count)
    CTRunGetGlyphs(run, CFRange(location: 0, length: count), &glyphs)
    CTRunGetPositions(run, CFRange(location: 0, length: count), &positions)
    CTRunGetStringIndices(run, CFRange(location: 0, length: count), &indices)
    let characters = Array(text.utf16)
    for index in 0..<count {
        let character = characters[indices[index]]
        penShift += pairAdjustments[indices[index]] ?? 0
        if character == 0x20 {
            var spaceGlyph = glyphs[index]
            var advance = CGSize.zero
            CTFontGetAdvancesForGlyphs(font, .horizontal, &spaceGlyph, &advance, 1)
            penShift += CGFloat(wordSpace) * size - advance.width
            continue
        }
        if let glyphPath = CTFontCreatePathForGlyph(font, glyphs[index], nil) {
            let x = positions[index].x + penShift
            // Flip y so the SVG has y down with the baseline at 0.
            let transform = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: x, ty: 0)
            combined.addPath(glyphPath, transform: transform)
        }
        penShift += CGFloat(tracking) * size
    }
}

func format(_ value: CGFloat) -> String {
    let rounded = (value * 10).rounded() / 10
    return rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
}

var data = ""
combined.applyWithBlock { pointer in
    let element = pointer.pointee
    let points = element.points
    switch element.type {
    case .moveToPoint:
        data += "M\(format(points[0].x)) \(format(points[0].y))"
    case .addLineToPoint:
        data += "L\(format(points[0].x)) \(format(points[0].y))"
    case .addQuadCurveToPoint:
        data += "Q\(format(points[0].x)) \(format(points[0].y)) \(format(points[1].x)) \(format(points[1].y))"
    case .addCurveToPoint:
        data += "C\(format(points[0].x)) \(format(points[0].y)) \(format(points[1].x)) \(format(points[1].y)) \(format(points[2].x)) \(format(points[2].y))"
    case .closeSubpath:
        data += "Z"
    @unknown default:
        break
    }
}
let bounds = combined.boundingBoxOfPath
print("\(format(bounds.minX)) \(format(bounds.minY)) \(format(bounds.width)) \(format(bounds.height))")
print(data)
