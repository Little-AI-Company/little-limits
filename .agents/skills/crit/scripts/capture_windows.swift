// Captures every on-screen window owned by the running app and records its
// frame in points so findings can convert screenshot pixels to points.
//
// Usage: swift capture_windows.swift <output-directory> <capture-prefix> <process-id>
// Pass the demo instance's PID so a separately running instance with real
// accounts is never captured.
// Requires Screen Recording permission for the calling terminal.

import AppKit
import CoreGraphics
import Foundation

struct CapturedWindow: Encodable {
    let file: String
    let windowID: CGWindowID
    let title: String
    let layer: Int
    let frame: CGRect
    let backingScale: CGFloat
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let processID = Int(arguments[3]) else {
    FileHandle.standardError.write(Data("usage: capture_windows.swift <output-directory> <capture-prefix> <process-id>\n".utf8))
    exit(64)
}
let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let prefix = arguments[2]
try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

guard let windowList = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
    FileHandle.standardError.write(Data("window list unavailable\n".utf8))
    exit(1)
}

func layerName(_ layer: Int) -> String {
    switch layer {
    case 0: "window"
    case 25: "status-item"
    case 101: "menu"
    default: "layer\(layer)"
    }
}

func backingScale(for frame: CGRect) -> CGFloat {
    let mainHeight = NSScreen.screens.first?.frame.height ?? 0
    // CGWindow bounds use a top-left origin; NSScreen frames use bottom-left.
    let flipped = CGRect(x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
    let screen = NSScreen.screens.first { $0.frame.intersects(flipped) } ?? NSScreen.main
    return screen?.backingScaleFactor ?? 2
}

// Remove earlier captures with this prefix so a failed or absent window never
// leaves a stale image that a report could present as current evidence.
for name in try FileManager.default.contentsOfDirectory(atPath: outputDirectory.path)
where name == "\(prefix).json" || (name.hasPrefix("\(prefix)-") && name.hasSuffix(".png")) {
    try FileManager.default.removeItem(at: outputDirectory.appendingPathComponent(name))
}

var captured: [CapturedWindow] = []
var layerCounts: [Int: Int] = [:]
for info in windowList where (info[kCGWindowOwnerPID as String] as? Int) == processID {
    guard let windowID = info[kCGWindowNumber as String] as? CGWindowID,
          let layer = info[kCGWindowLayer as String] as? Int,
          let boundsDictionary = info[kCGWindowBounds as String] as? NSDictionary,
          let frame = CGRect(dictionaryRepresentation: boundsDictionary),
          frame.width > 4, frame.height > 4 else { continue }
    let index = layerCounts[layer, default: 0]
    layerCounts[layer] = index + 1
    let suffix = index == 0 ? "" : "-\(index + 1)"
    let file = "\(prefix)-\(layerName(layer))\(suffix).png"
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    process.arguments = ["-x", "-o", "-l\(windowID)", outputDirectory.appendingPathComponent(file).path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        FileHandle.standardError.write(Data("screencapture failed for window \(windowID)\n".utf8))
        continue
    }
    captured.append(CapturedWindow(
        file: file,
        windowID: windowID,
        title: info[kCGWindowName as String] as? String ?? "",
        layer: layer,
        frame: frame,
        backingScale: backingScale(for: frame)
    ))
}

let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
let manifest = outputDirectory.appendingPathComponent("\(prefix).json")
try encoder.encode(captured).write(to: manifest)
print("captured \(captured.count) window(s) -> \(manifest.path)")
if captured.isEmpty { exit(2) }
