//
//  Copyright (C) 2002-2022   The FreeCol Team
//
//  This file is part of FreeCol.
//
//  FreeCol is free software: you can redistribute it and/or modify
//  it under the terms of the GNU General Public License as published by
//  the Free Software Foundation, either version 2 of the License, or
//  (at your option) any later version.
//
//  FreeCol is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with FreeCol.  If not, see <http://www.gnu.org/licenses/>.
//

import Compression
import Foundation

/// An error reading a zip archive.
public struct ZipError: Error, CustomStringConvertible {
    public let message: String

    public init(_ message: String) {
        self.message = message
    }

    public var description: String {
        message
    }
}

/// A zip archive read into memory: enough for FreeCol's saved games,
/// maps and mods (Java reads them with java.util.zip).
///
/// Entries may be stored or deflated, the two methods Java writes.
/// Zip64, encryption and multi-disk archives are not supported.
/// Deflate is undone by Apple's Compression framework, whose ZLIB
/// algorithm is raw deflate, as zip uses.
public struct ZipArchive: Sendable {

    /// One file in the archive.
    public struct Entry: Sendable {
        public let name: String
        let method: UInt16
        let crc32: UInt32
        let compressedSize: Int
        public let size: Int
        let localHeaderOffset: Int
    }

    private let data: Data
    /// The entries, in the order of the central directory.
    public let entries: [Entry]

    public init(contentsOf url: URL) throws {
        try self.init(data: Data(contentsOf: url))
    }

    public init(data: Data) throws {
        self.data = data
        let bytes = [UInt8](data)
        // The end of central directory record is 22 bytes plus a comment
        // of up to 65535 bytes, at the end of the file.
        let eocdSignature: UInt32 = 0x0605_4b50
        var eocd: Int?
        if bytes.count >= 22 {
            var i = bytes.count - 22
            let lowest = max(0, bytes.count - 22 - 0xffff)
            while i >= lowest {
                if ZipArchive.uint32(bytes, i) == eocdSignature {
                    eocd = i
                    break
                }
                i -= 1
            }
        }
        guard let eocd else { throw ZipError("Not a zip archive") }
        let count = Int(ZipArchive.uint16(bytes, eocd + 10))
        var offset = Int(ZipArchive.uint32(bytes, eocd + 16))
        var entries: [Entry] = []
        for _ in 0..<count {
            guard offset + 46 <= bytes.count,
                  ZipArchive.uint32(bytes, offset) == 0x0201_4b50 else {
                throw ZipError("Bad central directory entry at \(offset)")
            }
            let nameLength = Int(ZipArchive.uint16(bytes, offset + 28))
            let extraLength = Int(ZipArchive.uint16(bytes, offset + 30))
            let commentLength = Int(ZipArchive.uint16(bytes, offset + 32))
            guard offset + 46 + nameLength <= bytes.count else {
                throw ZipError("Truncated central directory")
            }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            entries.append(Entry(name: name,
                                 method: ZipArchive.uint16(bytes, offset + 10),
                                 crc32: ZipArchive.uint32(bytes, offset + 16),
                                 compressedSize: Int(ZipArchive.uint32(bytes, offset + 20)),
                                 size: Int(ZipArchive.uint32(bytes, offset + 24)),
                                 localHeaderOffset: Int(ZipArchive.uint32(bytes, offset + 42))))
            offset += 46 + nameLength + extraLength + commentLength
        }
        self.entries = entries
    }

    public func entry(_ name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// The contents of an entry, or nil if there is none of that name.
    ///
    /// - Throws: ZipError if the entry is damaged or uses an
    ///   unsupported method.
    public func contents(of name: String) throws -> Data? {
        guard let entry = entry(name) else { return nil }
        return try contents(of: entry)
    }

    public func contents(of entry: Entry) throws -> Data {
        let bytes = [UInt8](data)
        let header = entry.localHeaderOffset
        guard header + 30 <= bytes.count, ZipArchive.uint32(bytes, header) == 0x0403_4b50 else {
            throw ZipError("Bad local header for \(entry.name)")
        }
        let start = header + 30 + Int(ZipArchive.uint16(bytes, header + 26))
            + Int(ZipArchive.uint16(bytes, header + 28))
        guard start + entry.compressedSize <= bytes.count else {
            throw ZipError("Truncated data for \(entry.name)")
        }
        let compressed = Array(bytes[start..<(start + entry.compressedSize)])
        let result: [UInt8]
        switch entry.method {
        case 0:
            result = compressed
        case 8:
            result = try ZipArchive.inflate(compressed, size: entry.size, name: entry.name)
        default:
            throw ZipError("Unsupported compression method \(entry.method) for \(entry.name)")
        }
        guard ZipArchive.crc32(result) == entry.crc32 else {
            throw ZipError("CRC mismatch for \(entry.name)")
        }
        return Data(result)
    }

    private static func inflate(_ input: [UInt8], size: Int, name: String) throws -> [UInt8] {
        if size == 0 { return [] }
        var output = [UInt8](repeating: 0, count: size)
        let written = input.withUnsafeBufferPointer { src in
            output.withUnsafeMutableBufferPointer { dst in
                compression_decode_buffer(dst.baseAddress!, size, src.baseAddress!, input.count,
                                          nil, COMPRESSION_ZLIB)
            }
        }
        guard written == size else { throw ZipError("Failed to inflate \(name)") }
        return output
    }

    private static func uint16(_ b: [UInt8], _ i: Int) -> UInt16 {
        UInt16(b[i]) | UInt16(b[i + 1]) << 8
    }

    private static func uint32(_ b: [UInt8], _ i: Int) -> UInt32 {
        UInt32(b[i]) | UInt32(b[i + 1]) << 8 | UInt32(b[i + 2]) << 16 | UInt32(b[i + 3]) << 24
    }

    private static let crcTable: [UInt32] = (0..<256).map { n in
        var c = UInt32(n)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? 0xedb8_8320 ^ (c >> 1) : c >> 1
        }
        return c
    }

    /// The CRC-32 zip uses.
    static func crc32(_ bytes: [UInt8]) -> UInt32 {
        var c: UInt32 = 0xffff_ffff
        for b in bytes {
            c = crcTable[Int((c ^ UInt32(b)) & 0xff)] ^ (c >> 8)
        }
        return c ^ 0xffff_ffff
    }
}

extension ZipArchive {
    /// A zip archive of files, each deflated (or stored, if that is no
    /// smaller), as Java's JarOutputStream writes a saved game.
    public static func archive(_ files: [(name: String, data: Data)]) -> Data {
        var out: [UInt8] = []
        var central: [UInt8] = []
        func u16(_ v: Int, _ a: inout [UInt8]) { a += [UInt8(v & 0xff), UInt8((v >> 8) & 0xff)] }
        func u32(_ v: UInt32, _ a: inout [UInt8]) {
            a += [UInt8(v & 0xff), UInt8((v >> 8) & 0xff), UInt8((v >> 16) & 0xff), UInt8(v >> 24)]
        }
        for file in files {
            let raw = [UInt8](file.data)
            let crc = crc32(raw)
            var method = 0
            var body = raw
            if !raw.isEmpty {
                var buffer = [UInt8](repeating: 0, count: raw.count + 1024)
                let n = raw.withUnsafeBufferPointer { src in
                    buffer.withUnsafeMutableBufferPointer { dst in
                        compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, raw.count,
                                                  nil, COMPRESSION_ZLIB)
                    }
                }
                if n > 0 && n < raw.count {
                    method = 8
                    body = Array(buffer[0..<n])
                }
            }
            let name = [UInt8](file.name.utf8)
            let offset = out.count
            // Local header.
            u32(0x0403_4b50, &out); u16(20, &out); u16(0x0800, &out); u16(method, &out)
            u16(0, &out); u16(0x21, &out) // time and date: 1980-01-01 00:00
            u32(crc, &out); u32(UInt32(body.count), &out); u32(UInt32(raw.count), &out)
            u16(name.count, &out); u16(0, &out)
            out += name
            out += body
            // Its central directory entry.
            u32(0x0201_4b50, &central); u16(20, &central); u16(20, &central); u16(0x0800, &central)
            u16(method, &central); u16(0, &central); u16(0x21, &central)
            u32(crc, &central); u32(UInt32(body.count), &central); u32(UInt32(raw.count), &central)
            u16(name.count, &central); u16(0, &central); u16(0, &central); u16(0, &central); u16(0, &central)
            u32(0, &central); u32(UInt32(offset), &central)
            central += name
        }
        let centralOffset = out.count
        out += central
        // End of central directory.
        u32(0x0605_4b50, &out); u16(0, &out); u16(0, &out); u16(files.count, &out); u16(files.count, &out)
        u32(UInt32(central.count), &out); u32(UInt32(centralOffset), &out); u16(0, &out)
        return Data(out)
    }
}
