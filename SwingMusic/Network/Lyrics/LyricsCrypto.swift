import Foundation
import zlib

enum LyricsCrypto {
    private static let qrcKey = Array("!@#)(*$%123ZXC!@!@#)(NHL".utf8)

    private static let qrcSchedule: [[[UInt8]]] = [
        keySchedule(Array(qrcKey[16...]), decrypt: true),
        keySchedule(Array(qrcKey[8...]), decrypt: false),
        keySchedule(Array(qrcKey[0...]), decrypt: true),
    ]

    static func qrcDecrypt(hex: String) -> String? {
        guard let bytes = bytes(fromHex: hex), !bytes.isEmpty, bytes.count % 8 == 0 else { return nil }
        var out = [UInt8]()
        out.reserveCapacity(bytes.count)
        var i = 0
        while i < bytes.count {
            var block = Array(bytes[i ..< i + 8])
            for k in qrcSchedule { block = crypt(block, k) }
            out += block
            i += 8
        }
        guard let plain = inflate(out) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    private static let krcKey: [UInt8] = [0x40, 0x47, 0x61, 0x77, 0x5E, 0x32, 0x74, 0x47,
                                          0x51, 0x36, 0x31, 0x2D, 0xCE, 0xD2, 0x6E, 0x69]

    static func krcDecrypt(base64: String) -> String? {
        guard let data = Data(base64Encoded: base64), data.count > 4 else { return nil }
        let enc = [UInt8](data.dropFirst(4))
        var dec = [UInt8](repeating: 0, count: enc.count)
        for i in enc.indices { dec[i] = enc[i] ^ krcKey[i % krcKey.count] }
        guard let plain = inflate(dec) else { return nil }
        return String(data: plain, encoding: .utf8)
    }

    static func inflate(_ input: [UInt8]) -> Data? {
        var stream = z_stream()
        guard inflateInit_(&stream, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var input = input
        var out = Data()
        let chunk = 64 * 1024
        var buffer = [UInt8](repeating: 0, count: chunk)
        return input.withUnsafeMutableBufferPointer { inBuf -> Data? in
            stream.next_in = inBuf.baseAddress
            stream.avail_in = uInt(inBuf.count)
            while true {
                var status: Int32 = Z_OK
                let produced = buffer.withUnsafeMutableBufferPointer { outBuf -> Int in
                    stream.next_out = outBuf.baseAddress
                    stream.avail_out = uInt(chunk)
                    status = zlib.inflate(&stream, Z_NO_FLUSH)
                    return chunk - Int(stream.avail_out)
                }
                guard status == Z_OK || status == Z_STREAM_END else { return nil }
                out.append(buffer, count: produced)
                if status == Z_STREAM_END { return out }
                if produced == 0, stream.avail_in == 0 { return nil }
            }
        }
    }

    private static func bytes(fromHex hex: String) -> [UInt8]? {
        let chars = Array(hex.utf8)
        guard chars.count % 2 == 0 else { return nil }
        func nibble(_ c: UInt8) -> UInt8? {
            switch c {
            case 48...57: return c - 48
            case 65...70: return c - 55
            case 97...102: return c - 87
            default: return nil
            }
        }
        var out = [UInt8]()
        out.reserveCapacity(chars.count / 2)
        var i = 0
        while i < chars.count {
            guard let hi = nibble(chars[i]), let lo = nibble(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    private static let sbox: [[UInt32]] = [
        [14, 4, 13, 1, 2, 15, 11, 8, 3, 10, 6, 12, 5, 9, 0, 7,
         0, 15, 7, 4, 14, 2, 13, 1, 10, 6, 12, 11, 9, 5, 3, 8,
         4, 1, 14, 8, 13, 6, 2, 11, 15, 12, 9, 7, 3, 10, 5, 0,
         15, 12, 8, 2, 4, 9, 1, 7, 5, 11, 3, 14, 10, 0, 6, 13],
        [15, 1, 8, 14, 6, 11, 3, 4, 9, 7, 2, 13, 12, 0, 5, 10,
         3, 13, 4, 7, 15, 2, 8, 15, 12, 0, 1, 10, 6, 9, 11, 5,
         0, 14, 7, 11, 10, 4, 13, 1, 5, 8, 12, 6, 9, 3, 2, 15,
         13, 8, 10, 1, 3, 15, 4, 2, 11, 6, 7, 12, 0, 5, 14, 9],
        [10, 0, 9, 14, 6, 3, 15, 5, 1, 13, 12, 7, 11, 4, 2, 8,
         13, 7, 0, 9, 3, 4, 6, 10, 2, 8, 5, 14, 12, 11, 15, 1,
         13, 6, 4, 9, 8, 15, 3, 0, 11, 1, 2, 12, 5, 10, 14, 7,
         1, 10, 13, 0, 6, 9, 8, 7, 4, 15, 14, 3, 11, 5, 2, 12],
        [7, 13, 14, 3, 0, 6, 9, 10, 1, 2, 8, 5, 11, 12, 4, 15,
         13, 8, 11, 5, 6, 15, 0, 3, 4, 7, 2, 12, 1, 10, 14, 9,
         10, 6, 9, 0, 12, 11, 7, 13, 15, 1, 3, 14, 5, 2, 8, 4,
         3, 15, 0, 6, 10, 10, 13, 8, 9, 4, 5, 11, 12, 7, 2, 14],
        [2, 12, 4, 1, 7, 10, 11, 6, 8, 5, 3, 15, 13, 0, 14, 9,
         14, 11, 2, 12, 4, 7, 13, 1, 5, 0, 15, 10, 3, 9, 8, 6,
         4, 2, 1, 11, 10, 13, 7, 8, 15, 9, 12, 5, 6, 3, 0, 14,
         11, 8, 12, 7, 1, 14, 2, 13, 6, 15, 0, 9, 10, 4, 5, 3],
        [12, 1, 10, 15, 9, 2, 6, 8, 0, 13, 3, 4, 14, 7, 5, 11,
         10, 15, 4, 2, 7, 12, 9, 5, 6, 1, 13, 14, 0, 11, 3, 8,
         9, 14, 15, 5, 2, 8, 12, 3, 7, 0, 4, 10, 1, 13, 11, 6,
         4, 3, 2, 12, 9, 5, 15, 10, 11, 14, 1, 7, 6, 0, 8, 13],
        [4, 11, 2, 14, 15, 0, 8, 13, 3, 12, 9, 7, 5, 10, 6, 1,
         13, 0, 11, 7, 4, 9, 1, 10, 14, 3, 5, 12, 2, 15, 8, 6,
         1, 4, 11, 13, 12, 3, 7, 14, 10, 15, 6, 8, 0, 5, 9, 2,
         6, 11, 13, 8, 1, 4, 10, 7, 9, 5, 0, 15, 14, 2, 3, 12],
        [13, 2, 8, 4, 6, 15, 11, 1, 10, 9, 3, 14, 5, 0, 12, 7,
         1, 15, 13, 8, 10, 3, 7, 4, 12, 5, 6, 11, 0, 14, 9, 2,
         7, 11, 4, 1, 9, 12, 14, 2, 0, 6, 10, 13, 15, 3, 5, 8,
         2, 1, 14, 7, 4, 10, 8, 13, 15, 12, 9, 0, 3, 5, 6, 11],
    ]

    @inline(__always)
    private static func bitnum(_ a: [UInt8], _ b: Int, _ c: Int) -> UInt32 {
        (UInt32(a[(b / 32) * 4 + 3 - (b % 32) / 8] >> (7 - b % 8)) & 1) << c
    }
    @inline(__always)
    private static func bitnumR(_ a: UInt32, _ b: Int, _ c: Int) -> UInt32 { ((a >> (31 - b)) & 1) << c }
    @inline(__always)
    private static func bitnumL(_ a: UInt32, _ b: Int, _ c: Int) -> UInt32 { ((a << b) & 0x8000_0000) >> c }
    @inline(__always)
    private static func sboxBit(_ a: UInt32) -> Int { Int((a & 32) | ((a & 31) >> 1) | ((a & 1) << 4)) }

    private static let ip0 = [57, 49, 41, 33, 25, 17, 9, 1, 59, 51, 43, 35, 27, 19, 11, 3,
                              61, 53, 45, 37, 29, 21, 13, 5, 63, 55, 47, 39, 31, 23, 15, 7]
    private static let ip1 = [56, 48, 40, 32, 24, 16, 8, 0, 58, 50, 42, 34, 26, 18, 10, 2,
                              60, 52, 44, 36, 28, 20, 12, 4, 62, 54, 46, 38, 30, 22, 14, 6]
    private static let invBase = [4, 5, 6, 7, 0, 1, 2, 3]
    private static let pbox: [(Int, Int)] = [
        (15, 0), (6, 1), (19, 2), (20, 3), (28, 4), (11, 5), (27, 6), (16, 7),
        (0, 8), (14, 9), (22, 10), (25, 11), (4, 12), (17, 13), (30, 14), (9, 15),
        (1, 16), (7, 17), (23, 18), (13, 19), (31, 20), (26, 21), (2, 22), (8, 23),
        (18, 24), (12, 25), (29, 26), (5, 27), (21, 28), (10, 29), (3, 30), (24, 31),
    ]

    private static func f(_ state: UInt32, _ key: [UInt8]) -> UInt32 {
        var t1: UInt32 = bitnumL(state, 31, 0) | ((state & 0xF000_0000) >> 1)
        t1 |= bitnumL(state, 4, 5) | bitnumL(state, 3, 6) | ((state & 0x0F00_0000) >> 3)
        t1 |= bitnumL(state, 8, 11) | bitnumL(state, 7, 12) | ((state & 0x00F0_0000) >> 5)
        t1 |= bitnumL(state, 12, 17) | bitnumL(state, 11, 18) | ((state & 0x000F_0000) >> 7)
        t1 |= bitnumL(state, 16, 23)

        var t2: UInt32 = bitnumL(state, 15, 0) | ((state & 0x0000_F000) << 15)
        t2 |= bitnumL(state, 20, 5) | bitnumL(state, 19, 6) | ((state & 0x0000_0F00) << 13)
        t2 |= bitnumL(state, 24, 11) | bitnumL(state, 23, 12) | ((state & 0x0000_00F0) << 11)
        t2 |= bitnumL(state, 28, 17) | bitnumL(state, 27, 18) | ((state & 0x0000_000F) << 9)
        t2 |= bitnumL(state, 0, 23)

        let l: [UInt32] = [
            ((t1 >> 24) & 0xFF) ^ UInt32(key[0]), ((t1 >> 16) & 0xFF) ^ UInt32(key[1]),
            ((t1 >> 8) & 0xFF) ^ UInt32(key[2]), ((t2 >> 24) & 0xFF) ^ UInt32(key[3]),
            ((t2 >> 16) & 0xFF) ^ UInt32(key[4]), ((t2 >> 8) & 0xFF) ^ UInt32(key[5]),
        ]

        var s: UInt32 = sbox[0][sboxBit(l[0] >> 2)] << 28
        s |= sbox[1][sboxBit(((l[0] & 0x03) << 4) | (l[1] >> 4))] << 24
        s |= sbox[2][sboxBit(((l[1] & 0x0F) << 2) | (l[2] >> 6))] << 20
        s |= sbox[3][sboxBit(l[2] & 0x3F)] << 16
        s |= sbox[4][sboxBit(l[3] >> 2)] << 12
        s |= sbox[5][sboxBit(((l[3] & 0x03) << 4) | (l[4] >> 4))] << 8
        s |= sbox[6][sboxBit(((l[4] & 0x0F) << 2) | (l[5] >> 6))] << 4
        s |= sbox[7][sboxBit(l[5] & 0x3F)]

        var out: UInt32 = 0
        for (b, c) in pbox { out |= bitnumL(s, b, c) }
        return out
    }

    private static func crypt(_ input: [UInt8], _ key: [[UInt8]]) -> [UInt8] {
        var s0: UInt32 = 0, s1: UInt32 = 0
        for i in 0..<32 {
            s0 |= bitnum(input, ip0[i], 31 - i)
            s1 |= bitnum(input, ip1[i], 31 - i)
        }
        for idx in 0..<15 {
            let prev = s1
            s1 = f(s1, key[idx]) ^ s0
            s0 = prev
        }
        s0 = f(s1, key[15]) ^ s0

        var data = [UInt8](repeating: 0, count: 8)
        for k in 0..<8 {
            let b = invBase[k]
            var v: UInt32 = bitnumR(s1, b, 7) | bitnumR(s0, b, 6) | bitnumR(s1, b + 8, 5) | bitnumR(s0, b + 8, 4)
            v |= bitnumR(s1, b + 16, 3) | bitnumR(s0, b + 16, 2) | bitnumR(s1, b + 24, 1) | bitnumR(s0, b + 24, 0)
            data[k] = UInt8(v)
        }
        return data
    }

    private static func keySchedule(_ key: [UInt8], decrypt: Bool) -> [[UInt8]] {
        let shifts = [1, 1, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 1]
        let permC = [56, 48, 40, 32, 24, 16, 8, 0, 57, 49, 41, 33, 25, 17, 9, 1, 58, 50, 42, 34, 26, 18, 10, 2, 59, 51, 43, 35]
        let permD = [62, 54, 46, 38, 30, 22, 14, 6, 61, 53, 45, 37, 29, 21, 13, 5, 60, 52, 44, 36, 28, 20, 12, 4, 27, 19, 11, 3]
        let compression = [13, 16, 10, 23, 0, 4, 2, 27, 14, 5, 20, 9, 22, 18, 11, 3, 25, 7, 15, 6, 26, 19, 12, 1, 40, 51, 30, 36,
                           46, 54, 29, 39, 50, 44, 32, 47, 43, 48, 38, 55, 33, 52, 45, 41, 49, 35, 28, 31]

        var schedule = [[UInt8]](repeating: [UInt8](repeating: 0, count: 6), count: 16)
        var c: UInt32 = 0, d: UInt32 = 0
        for i in 0..<28 {
            c |= bitnum(key, permC[i], 31 - i)
            d |= bitnum(key, permD[i], 31 - i)
        }
        for i in 0..<16 {
            let s = shifts[i]
            c = ((c << s) | (c >> (28 - s))) & 0xFFFF_FFF0
            d = ((d << s) | (d >> (28 - s))) & 0xFFFF_FFF0
            let row = decrypt ? 15 - i : i
            for j in 0..<24 {
                schedule[row][j / 8] |= UInt8(bitnumR(c, compression[j], 7 - j % 8))
            }
            for j in 24..<48 {
                schedule[row][j / 8] |= UInt8(bitnumR(d, compression[j] - 27, 7 - j % 8))
            }
        }
        return schedule
    }
}
