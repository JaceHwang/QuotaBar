import AppKit

// Compile the approved raster motif inside an exact circular native icon boundary.
// Source radius stays inside the reconstructed white badge, excluding alpha-edge specks.
let arguments = CommandLine.arguments
precondition(arguments.count == 3, "Usage: build-windows-icon.swift source.png output-assets-directory")
let sourceURL = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2], isDirectory: true)
guard let source = NSImage(contentsOf: sourceURL), let image = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("Invalid source image") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
func png(size: Int) throws -> Data {
    let side = CGFloat(size)
    guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Cannot allocate icon bitmap") }
    context.interpolationQuality = .high
    context.addEllipse(in: CGRect(x: side * 0.05, y: side * 0.05, width: side * 0.9, height: side * 0.9))
    context.clip()
    let drawingSide = side * 0.9 / 0.875
    context.draw(image, in: CGRect(x: (side-drawingSide)/2, y: (side-drawingSide)/2, width: drawingSide, height: drawingSide))
    guard let rendered = context.makeImage(), let result = NSBitmapImageRep(cgImage: rendered).representation(using: .png, properties: [:]) else { fatalError("Cannot encode icon") }
    return result
}
let master = try png(size: 1024)
try master.write(to: output.appendingPathComponent("quotabar-icon.png"), options: .atomic)
let sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
let frames = try sizes.map { try png(size: $0) }
var ico = Data()
func append16(_ value: Int, to data: inout Data) { data.append(UInt8(value & 255)); data.append(UInt8((value >> 8) & 255)) }
func append32(_ value: Int, to data: inout Data) { for shift in stride(from: 0, to: 32, by: 8) { data.append(UInt8((value >> shift) & 255)) } }
append16(0, to: &ico); append16(1, to: &ico); append16(sizes.count, to: &ico)
var offset = 6 + 16 * sizes.count
for (index, size) in sizes.enumerated() {
    ico.append(UInt8(size == 256 ? 0 : size)); ico.append(UInt8(size == 256 ? 0 : size)); ico.append(0); ico.append(0)
    append16(1, to: &ico); append16(32, to: &ico); append32(frames[index].count, to: &ico); append32(offset, to: &ico); offset += frames[index].count
}
for frame in frames { ico.append(frame) }
try ico.write(to: output.appendingPathComponent("QuotaBar.ico"), options: .atomic)
print("Compiled circular 1024px PNG and multi-resolution Windows ICO")
