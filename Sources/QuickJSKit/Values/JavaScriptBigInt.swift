/// An arbitrary-precision JavaScript `bigint` value.
///
/// `JavaScriptBigInt` stores a canonical base-10 representation, so it is
/// independent of any runtime and safe to pass between concurrency domains.
/// Leading zeroes and a leading plus sign are removed. Negative zero is
/// normalized to zero.
public struct JavaScriptBigInt: Sendable, Hashable, Codable,
    LosslessStringConvertible, CustomStringConvertible
{
    /// The canonical base-10 representation of this integer.
    public let description: String

    /// Creates an arbitrary-precision integer from a base-10 string.
    ///
    /// The input may contain an optional leading `+` or `-`, followed by one or
    /// more ASCII digits. Whitespace, separators, exponents, and the JavaScript
    /// `n` suffix are not accepted.
    ///
    /// - Parameter description: A base-10 integer representation.
    public init?(_ description: String) {
        guard !description.isEmpty else { return nil }

        var digits = description[...]
        var isNegative = false
        if digits.first == "+" {
            digits.removeFirst()
        } else if digits.first == "-" {
            isNegative = true
            digits.removeFirst()
        }

        guard !digits.isEmpty,
              digits.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else {
            return nil
        }

        let significantDigits = digits.drop(while: { $0 == "0" })
        if significantDigits.isEmpty {
            self.description = "0"
        } else if isNegative {
            self.description = "-" + significantDigits
        } else {
            self.description = String(significantDigits)
        }
    }

    /// Creates a JavaScript arbitrary-precision integer from a signed value.
    public init(_ value: Int64) {
        self.description = String(value)
    }

    /// Creates a JavaScript arbitrary-precision integer from an unsigned value.
    public init(_ value: UInt64) {
        self.description = String(value)
    }

    /// Decodes a canonicalizable base-10 string.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        let representation = try container.decode(String.self)
        guard let value = JavaScriptBigInt(representation) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected a base-10 JavaScript bigint."
            )
        }
        self = value
    }

    /// Encodes the canonical base-10 representation.
    ///
    /// ``JavaScriptEncoder`` recognizes this type and emits a native JavaScript
    /// `bigint`. Other encoders receive its canonical string representation.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}
