import Foundation

/// Decodes and encodes note files while preserving BOM and line endings byte-for-byte
/// for valid UTF-8 input. Non-UTF-8 files are decoded lossily and flagged.
public struct MarkdownFileCodec: Sendable {
    public struct Decoded: Sendable, Equatable {
        public var text: String
        public var hasBOM: Bool
        public var lineEnding: LineEnding
        /// True when the bytes were not valid UTF-8 and a fallback encoding was used.
        public var isLossy: Bool
        public var encoding: String.Encoding
    }

    public init() {}

    private static let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]

    public func decode(_ data: Data) -> Decoded {
        var body = data
        var hasBOM = false
        if data.count >= 3, data[data.startIndex] == 0xEF, data[data.startIndex + 1] == 0xBB, data[data.startIndex + 2] == 0xBF {
            hasBOM = true
            body = data.subdata(in: (data.startIndex + 3)..<data.endIndex)
        }
        if let text = String(data: body, encoding: .utf8) {
            return Decoded(text: text, hasBOM: hasBOM, lineEnding: LineEnding.dominant(in: text), isLossy: false, encoding: .utf8)
        }
        var converted: NSString?
        let raw = NSString.stringEncoding(for: body, encodingOptions: nil, convertedString: &converted, usedLossyConversion: nil)
        let encoding = raw == 0 ? String.Encoding.isoLatin1 : String.Encoding(rawValue: raw)
        let text = (converted as String?) ?? String(decoding: body, as: UTF8.self)
        return Decoded(text: text, hasBOM: hasBOM, lineEnding: LineEnding.dominant(in: text), isLossy: true, encoding: encoding)
    }

    public func encode(_ text: String, hasBOM: Bool) -> Data {
        var data = Data()
        if hasBOM { data.append(contentsOf: Self.utf8BOM) }
        data.append(contentsOf: Array(text.utf8))
        return data
    }
}
