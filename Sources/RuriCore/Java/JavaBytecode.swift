import Foundation
import ZIPFoundation
import RuriLocalization

enum JavaBytecode {
    /// Inspect the actual installation tools, not the Minecraft client. Classes
    /// in multi-release overlays and module descriptors do not raise a JAR's
    /// baseline: an older JVM ignores those optional entries.
    static func minimumMajor(in files: [URL]) throws -> Int {
        var minimum = 8
        for file in Set(files) {
            let archive = try Archive(url: file, accessMode: .read)
            for entry in archive where entry.type == .file && entry.path.hasSuffix(".class") &&
                !entry.path.hasPrefix("META-INF/versions/") && entry.path != "module-info.class" {
                try Task.checkCancellation()
                guard entry.uncompressedSize <= 16 * 1024 * 1024 else {
                    throw RuriError.message(Messages.CoreJavaBytecode.invalidClass(file.lastPathComponent))
                }
                var header = Data()
                let crc = try archive.extract(entry) { data in
                    if header.count < 8 { header.append(data.prefix(8 - header.count)) }
                }
                guard crc == entry.checksum, header.count == 8, header.prefix(4) == Data([0xca, 0xfe, 0xba, 0xbe]) else {
                    throw RuriError.message(Messages.CoreJavaBytecode.invalidClass(file.lastPathComponent))
                }
                let major = Int(header[6]) << 8 | Int(header[7])
                guard major >= 45 else { throw RuriError.message(Messages.CoreJavaBytecode.invalidClass(file.lastPathComponent)) }
                minimum = max(minimum, major - 44)
            }
        }
        return minimum
    }
}
