// Extracts the block and item textures used by built-in instance icons from a Minecraft
// client jar and embeds them in Sources/RuriCore/Instances/InstanceIconTextures.swift.
// Embedding keeps them available to every executable without resource bundles.
// Usage: xcrun swift scripts/dev/generate-block-textures.swift <client.jar>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let textures = [
    "grass_block_top", "grass_block_side", "dirt", "cobblestone", "oak_log", "oak_log_top", "oak_planks",
    "crafting_table_top", "crafting_table_front", "crafting_table_side", "furnace_top", "furnace_front", "furnace_side",
    "bookshelf", "tnt_top", "tnt_side", "diamond_ore", "bricks", "obsidian", "netherrack", "glowstone",
    "pumpkin_top", "pumpkin_side", "jack_o_lantern", "command_block_front", "command_block_side",
]
// The grass block item's tint in items/grass_block.json.
let grassTemperature = 0.5, grassDownfall = 1.0

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("Usage: generate-block-textures.swift <client.jar>\n".utf8)); exit(2)
}
let jar = CommandLine.arguments[1]
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("Sources/RuriCore/Instances/InstanceIconTextures.swift")

func entry(_ path: String) -> Data {
    let process = Process(), pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip"); process.arguments = ["-p", jar, path]
    process.standardOutput = pipe
    do { try process.run() } catch { fatalError("Cannot run unzip: \(error)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
    guard process.terminationStatus == 0, !data.isEmpty else { fatalError("Missing \(path) in \(jar)") }
    return data
}

func texture(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithData(entry(path) as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Unreadable \(path)") }
    // Animated textures stack frames vertically; icons use the first frame.
    return image.height > image.width ? image.cropping(to: CGRect(x: 0, y: 0, width: image.width, height: image.width))! : image
}

func redraw(_ images: [CGImage], _ edit: (UnsafeMutablePointer<UInt8>, Int) -> Void = { _, _ in }) -> CGImage {
    let width = images[0].width, height = images[0].height
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    for image in images { context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
    edit(context.data!.assumingMemoryBound(to: UInt8.self), width * height)
    return context.makeImage()!
}

func tinted(_ image: CGImage, _ color: (UInt8, UInt8, UInt8)) -> CGImage {
    redraw([image]) { pixels, count in
        for index in 0..<count {
            pixels[index * 4] = UInt8(Int(pixels[index * 4]) * Int(color.0) / 255)
            pixels[index * 4 + 1] = UInt8(Int(pixels[index * 4 + 1]) * Int(color.1) / 255)
            pixels[index * 4 + 2] = UInt8(Int(pixels[index * 4 + 2]) * Int(color.2) / 255)
        }
    }
}

func png(_ image: CGImage) -> String {
    let data = NSMutableData()
    let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Cannot encode PNG") }
    return (data as Data).base64EncodedString()
}

let colormap = texture("assets/minecraft/textures/colormap/grass.png")
var grass: (UInt8, UInt8, UInt8) = (0, 0, 0)
_ = redraw([colormap]) { pixels, _ in
    let x = Int((1 - grassTemperature) * 255), y = Int((1 - grassDownfall * grassTemperature) * 255)
    let offset = (y * colormap.width + x) * 4
    grass = (pixels[offset], pixels[offset + 1], pixels[offset + 2])
}

var encoded: [String: String] = [:]
for name in textures {
    let path = "assets/minecraft/textures/block/\(name).png"
    switch name {
    case "grass_block_top": encoded[name] = png(tinted(texture(path), grass))
    case "grass_block_side":
        let overlay = tinted(texture("assets/minecraft/textures/block/grass_block_side_overlay.png"), grass)
        encoded[name] = png(redraw([texture(path), overlay]))
    default: encoded[name] = png(texture(path))
    }
}

// Items keep the game's pixels as a white mark like the other glyphs: the dark
// outline stays opaque and lighter shading fades in two steps.
let items = [
    "item_pickaxe": ["item/diamond_pickaxe"], "item_sword": ["item/diamond_sword"], "item_heart": ["gui/sprites/hud/heart/full"],
    "item_gem": ["item/diamond"], "item_potion": ["item/potion_overlay", "item/potion"],
]

func monochrome(_ image: CGImage) -> CGImage {
    let width = image.width, height = image.height
    var alpha = [Double](repeating: 0, count: width * height), luma = [Double](repeating: -1, count: width * height)
    _ = redraw([image]) { pixels, count in
        for index in 0..<count where pixels[index * 4 + 3] > 0 {
            let value = Double(pixels[index * 4 + 3])
            alpha[index] = value / 255
            luma[index] = (0.2126 * Double(pixels[index * 4]) + 0.7152 * Double(pixels[index * 4 + 1]) + 0.0722 * Double(pixels[index * 4 + 2])) / value
        }
    }
    let values = luma.filter { $0 >= 0 }, low = values.min() ?? 0, high = values.max() ?? 1
    var bounds = (minX: width, minY: height, maxX: -1, maxY: -1)
    let mark = redraw([image]) { pixels, count in
        for index in 0..<count {
            let shade = high > low ? (luma[index] - low) / (high - low) : 0
            let level = luma[index] < 0 ? 0 : alpha[index] * (shade < 1.0 / 3 ? 1 : shade < 2.0 / 3 ? 0.75 : 0.5)
            let value = UInt8((level * 255).rounded())
            for channel in 0..<4 { pixels[index * 4 + channel] = value }
            if value > 0 {
                let x = index % width, y = index / width
                bounds = (min(bounds.minX, x), min(bounds.minY, y), max(bounds.maxX, x), max(bounds.maxY, y))
            }
        }
    }
    return mark.cropping(to: CGRect(x: bounds.minX, y: bounds.minY, width: bounds.maxX - bounds.minX + 1, height: bounds.maxY - bounds.minY + 1))!
}

for (name, layers) in items {
    encoded[name] = png(monochrome(redraw(layers.map { texture("assets/minecraft/textures/\($0).png") })))
}

let version = (try? JSONSerialization.jsonObject(with: entry("version.json")) as? [String: Any])?["name"] as? String ?? "unknown"
var lines = [
    "// Generated by scripts/dev/generate-block-textures.swift from the Minecraft \(version) client. Do not edit.",
    "",
    "/// Block and item textures for built-in instance icons as base64 PNG. Animated",
    "/// textures keep their first frame; grass is tinted as the game tints the grass",
    "/// block item; items are cropped white marks that keep the game's shading.",
    "enum InstanceIconTextures {",
    "    static let png: [String: String] = [",
]
lines += encoded.keys.sorted().map { "        \"\($0)\": \"\(encoded[$0]!)\"," }
lines += ["    ]", "}", ""]
try lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
print("Wrote \(encoded.count) textures from Minecraft \(version) to \(output.path)")
