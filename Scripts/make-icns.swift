import Foundation

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: make-icns.swift <iconset-directory> <output.icns>\\n", stderr)
    exit(1)
}

let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let output = URL(fileURLWithPath: CommandLine.arguments[2])

let entries: [(type: String, filename: String)] = [
    ("icp4", "AppIcon_16.png"),
    ("icp5", "AppIcon_32.png"),
    ("icp6", "AppIcon_32@2x.png"),
    ("ic07", "AppIcon_128.png"),
    ("ic08", "AppIcon_256.png"),
    ("ic09", "AppIcon_512.png"),
    ("ic10", "AppIcon_512@2x.png")
]

func appendBigEndian(_ value: UInt32, to data: inout Data) {
    let bigEndian = value.bigEndian
    withUnsafeBytes(of: bigEndian) { data.append(contentsOf: $0) }
}

var chunks = Data()
for entry in entries {
    let pngURL = iconset.appendingPathComponent(entry.filename)
    let png = try Data(contentsOf: pngURL)
    chunks.append(entry.type.data(using: .ascii)!)
    appendBigEndian(UInt32(png.count + 8), to: &chunks)
    chunks.append(png)
}

var icns = Data("icns".utf8)
appendBigEndian(UInt32(chunks.count + 8), to: &icns)
icns.append(chunks)
try icns.write(to: output, options: .atomic)
