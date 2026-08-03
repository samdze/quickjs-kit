import Foundation
import Testing
import QuickJSKit

@Suite("Direct conversion examples")
struct ConversionExamplesTests {
    enum Role: String, Codable, Sendable {
        case administrator
    }

    struct Payload: Codable, Sendable, Equatable {
        let enabled: Bool
        let note: String?
        let values: [Int]
        let metadata: [String: String]
        let role: Role
    }

    struct RenamedValue: Codable, Sendable, Equatable {
        let identifier: Int

        enum CodingKeys: String, CodingKey {
            case identifier = "user_id"
        }
    }

    struct IntegerBoundaries: Codable, Sendable, Equatable {
        let int8Minimum: Int8
        let int8Maximum: Int8
        let int16Minimum: Int16
        let int16Maximum: Int16
        let int32Minimum: Int32
        let int32Maximum: Int32
        let int64Minimum: Int64
        let int64Maximum: Int64
        let uint8Maximum: UInt8
        let uint16Maximum: UInt16
        let uint32Maximum: UInt32
        let uint64Maximum: UInt64
        let intMinimum: Int
        let intMaximum: Int
        let uintMaximum: UInt
    }

    @Test("runtime codecs round-trip nested Codable values")
    func codecsRoundTripCodable() async throws {
        let runtime = try JavaScriptRuntime()
        let payload = Payload(
            enabled: true,
            note: nil,
            values: [1, 2, 3],
            metadata: ["source": "Swift"],
            role: .administrator
        )

        let javaScript = try await runtime.encoder.encode(payload)
        let decoded = try await runtime.decoder.decode(Payload.self, from: javaScript)

        #expect(decoded == payload)

        let renamed: RenamedValue = try await runtime.evaluate("({ user_id: 42 })")
        #expect(renamed == RenamedValue(identifier: 42))
    }

    @Test("integers use Number or BigInt without losing precision")
    func integersRemainLossless() async throws {
        let runtime = try JavaScriptRuntime()
        let safe: Int = try await runtime.evaluate("9007199254740991")
        let signed: Int64 = try await runtime.evaluate("-9223372036854775808n")
        let unsigned: UInt64 = try await runtime.evaluate("18446744073709551615n")

        #expect(safe == 9_007_199_254_740_991)
        #expect(signed == .min)
        #expect(unsigned == .max)

        let encoded = try await runtime.encoder.encode(Int.max)
        try await runtime.global.set(encoded, forProperty: "largestSwiftInt")
        if Int.bitWidth > 53 {
            #expect(try await runtime.evaluate("typeof largestSwiftInt === 'bigint'", as: Bool.self))
        }
    }

    @Test("every Swift integer boundary round-trips losslessly")
    func integerBoundariesRoundTrip() async throws {
        let runtime = try JavaScriptRuntime()
        let boundaries = IntegerBoundaries(
            int8Minimum: .min,
            int8Maximum: .max,
            int16Minimum: .min,
            int16Maximum: .max,
            int32Minimum: .min,
            int32Maximum: .max,
            int64Minimum: .min,
            int64Maximum: .max,
            uint8Maximum: .max,
            uint16Maximum: .max,
            uint32Maximum: .max,
            uint64Maximum: .max,
            intMinimum: .min,
            intMaximum: .max,
            uintMaximum: .max
        )

        let value = try await runtime.encoder.encode(boundaries)
        let decoded = try await runtime.decoder.decode(
            IntegerBoundaries.self,
            from: value
        )

        #expect(decoded == boundaries)
    }

    @Test("the safe Number boundary is enforced in both directions")
    func safeNumberBoundaryIsExact() async throws {
        let runtime = try JavaScriptRuntime()
        let positive: Int64 = try await runtime.evaluate("9007199254740991")
        let negative: Int64 = try await runtime.evaluate("-9007199254740991")
        let positiveBigInt: Int64 = try await runtime.evaluate("9007199254740992n")
        let negativeBigInt: Int64 = try await runtime.evaluate("-9007199254740992n")

        #expect(positive == 9_007_199_254_740_991)
        #expect(negative == -9_007_199_254_740_991)
        #expect(positiveBigInt == 9_007_199_254_740_992)
        #expect(negativeBigInt == -9_007_199_254_740_992)

        await #expect(throws: DecodingError.self) {
            let _: Int64 = try await runtime.evaluate("9007199254740992")
        }
        await #expect(throws: DecodingError.self) {
            let _: Int64 = try await runtime.evaluate("-9007199254740992")
        }
    }

    @Test("missing null and undefined values decode as nil")
    func optionalAbsenceUsesJavaScriptSemantics() async throws {
        struct OptionalValues: Decodable, Sendable {
            let missing: String?
            let null: String?
            let undefined: String?
        }

        let runtime = try JavaScriptRuntime()
        let values: OptionalValues = try await runtime.evaluate("""
            ({ null: null, undefined: undefined })
            """)
        let topLevel: String? = try await runtime.evaluate("undefined")

        #expect(values.missing == nil)
        #expect(values.null == nil)
        #expect(values.undefined == nil)
        #expect(topLevel == nil)
    }

    @Test("raw undefined expressions preserve identity and runtime recovery")
    func rawUndefinedExpressionsRemainUsable() async throws {
        let runtime = try JavaScriptRuntime()

        let identifier = try await runtime.evaluate("undefined")
        let voidZero = try await runtime.evaluate("void 0")
        let globalProperty = try await runtime.evaluate("globalThis.undefined")

        #expect(identifier.isUndefined)
        #expect(voidZero.isUndefined)
        #expect(globalProperty.isUndefined)
        #expect(try await runtime.evaluate("40 + 2", as: Int.self) == 42)
    }

    @Test("Float decoding rejects finite values outside its range")
    func floatRangeIsChecked() async throws {
        let runtime = try JavaScriptRuntime()

        await #expect(throws: DecodingError.self) {
            let _: Float = try await runtime.evaluate("3.5e38")
        }
        await #expect(throws: DecodingError.self) {
            let _: [Float] = try await runtime.evaluate("[3.5e38]")
        }
    }

    @Test("arbitrary JavaScript BigInt values are detached and lossless")
    func arbitraryBigIntIsRepresentable() async throws {
        let runtime = try JavaScriptRuntime()

        let value = try await runtime.evaluate("123456789012345678901234567890n")

        #expect(value.bigIntValue?.description == "123456789012345678901234567890")
        #expect(JavaScriptBigInt("+00042")?.description == "42")

        let bigInt = try #require(JavaScriptBigInt("123456789012345678901234567890"))
        _ = try await runtime.evaluate("globalThis.BigInt = () => 0n")
        let encoded = try await runtime.encoder.encode(bigInt)
        try await runtime.global.set(encoded, forProperty: "huge")
        #expect(try await runtime.evaluate("typeof huge === 'bigint'", as: Bool.self))
        #expect(try await runtime.evaluate("huge === 123456789012345678901234567890n", as: Bool.self))
    }

    @Test("Data decodes from Uint8Array")
    func dataDecodesFromUint8Array() async throws {
        let runtime = try JavaScriptRuntime()
        let typed: Data = try await runtime.evaluate("new Uint8Array([1, 2, 255])")

        #expect(typed == Data([1, 2, 255]))
    }

    @Test("Data decodes from ArrayBuffer")
    func dataDecodesFromArrayBuffer() async throws {
        let runtime = try JavaScriptRuntime()
        let data: Data = try await runtime.evaluate(
            "new Uint8Array([4, 5, 6]).buffer"
        )

        #expect(data == Data([4, 5, 6]))
    }

    @Test("Data preserves the byte range of typed-array views")
    func dataDecodesFromTypedArrayViews() async throws {
        let runtime = try JavaScriptRuntime()
        let view: Data = try await runtime.evaluate("""
            (() => {
              const buffer = new ArrayBuffer(8);
              new Uint8Array(buffer).set([0, 1, 2, 3, 4, 5, 6, 7]);
              return new Uint16Array(buffer, 2, 2);
            })()
            """)

        #expect(view == Data([2, 3, 4, 5]))
    }

    @Test("Data accepts arrays containing valid bytes")
    func dataDecodesFromByteArrays() async throws {
        let runtime = try JavaScriptRuntime()
        let array: Data = try await runtime.evaluate("[3, 4, 5]")

        #expect(array == Data([3, 4, 5]))
    }

    @Test("Data encodes as Uint8Array")
    func dataEncodesAsUint8Array() async throws {
        let runtime = try JavaScriptRuntime()

        let encoded = try await runtime.encoder.encode(Data([9, 8, 7]))
        try await runtime.global.set(encoded, forProperty: "binary")
        #expect(try await runtime.evaluate("binary instanceof Uint8Array", as: Bool.self))
    }

    @Test("Date accepts Date milliseconds and ISO-8601 forms")
    func datesUseJavaScriptSemantics() async throws {
        let runtime = try JavaScriptRuntime()
        let fromObject: Date = try await runtime.evaluate("new Date(1000)")
        let fromNumber: Date = try await runtime.evaluate("1000")
        let fromString: Date = try await runtime.evaluate("'1970-01-01T00:00:01Z'")

        #expect(fromObject.timeIntervalSince1970 == 1)
        #expect(fromNumber.timeIntervalSince1970 == 1)
        #expect(fromString.timeIntervalSince1970 == 1)

        let encoded = try await runtime.encoder.encode(Date(timeIntervalSince1970: 2))
        try await runtime.global.set(encoded, forProperty: "swiftDate")
        #expect(try await runtime.evaluate("swiftDate instanceof Date", as: Bool.self))
    }

    @Test("URL accepts strings and href objects")
    func urlsDecodeFromCommonForms() async throws {
        let runtime = try JavaScriptRuntime()
        let direct: URL = try await runtime.evaluate("'https://example.com/path'")
        let object: URL = try await runtime.evaluate("({ href: 'https://swift.org' })")

        #expect(direct.absoluteString == "https://example.com/path")
        #expect(object.absoluteString == "https://swift.org")

        let encoded = try await runtime.encoder.encode(
            try #require(URL(string: "https://example.com/encoded"))
        )
        try await runtime.global.set(encoded, forProperty: "swiftURL")
        #expect(try await runtime.evaluate("typeof swiftURL === 'string'", as: Bool.self))
    }
}
