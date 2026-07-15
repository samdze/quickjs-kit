import Testing
import QuickJSKit

@Suite("Codec limit examples")
struct CodecLimitExamplesTests {
    struct NestingProbe: Decodable, Sendable {
        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            while !container.isAtEnd {
                container = try container.nestedUnkeyedContainer()
            }
        }
    }

    indirect enum NestedValue: Codable, Sendable {
        case end
        case next(NestedValue)

        init(from decoder: any Decoder) throws {
            var container = try decoder.unkeyedContainer()
            if container.isAtEnd {
                self = .end
            } else {
                self = .next(try container.decode(NestedValue.self))
            }
        }

        func encode(to encoder: any Encoder) throws {
            var container = encoder.unkeyedContainer()
            if case let .next(value) = self {
                try container.encode(value)
            }
        }
    }

    @Test("a codec accepts its configured nesting depth")
    func configuredDepthSucceeds() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate(nestedArraySource(depth: 64))
        var decoder = runtime.decoder
        decoder.maximumNestingDepth = 64

        _ = try await decoder.decode(NestingProbe.self, from: value)
    }

    @Test("a decoder reports the path beyond its nesting depth")
    func excessiveDepthFailsWithPath() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate(nestedArraySource(depth: 65))
        var decoder = runtime.decoder
        decoder.maximumNestingDepth = 64

        do {
            _ = try await decoder.decode(NestingProbe.self, from: value)
            Issue.record("Expected decoding to exceed its depth limit")
        } catch let error as DecodingError {
            guard case let .dataCorrupted(context) = error else {
                Issue.record("Expected dataCorrupted, received \(error)")
                return
            }
            #expect(context.codingPath.count == 64)
        }
    }

    @Test("an encoder enforces the same nesting depth")
    func encoderEnforcesDepth() async throws {
        let runtime = try JavaScriptRuntime()
        var encoder = runtime.encoder
        encoder.maximumNestingDepth = 64

        _ = try await encoder.encode(nestedValue(depth: 63))

        await #expect(throws: EncodingError.self) {
            _ = try await encoder.encode(nestedValue(depth: 64))
        }
    }

    @Test("cyclic JavaScript arrays terminate at the decoder limit")
    func cyclicArraysTerminateAtDepthLimit() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate("""
            (() => {
              const value = [];
              value.push(value);
              return value;
            })()
            """)
        var decoder = runtime.decoder
        decoder.maximumNestingDepth = 64

        do {
            _ = try await decoder.decode(NestingProbe.self, from: value)
            Issue.record("Expected decoding to exceed its depth limit")
        } catch let error as DecodingError {
            guard case let .dataCorrupted(context) = error else {
                Issue.record("Expected dataCorrupted, received \(error)")
                return
            }
            #expect(context.codingPath.count == 64)
        }
    }

    private func nestedArraySource(depth: Int) -> String {
        """
        (() => {
          let value = [];
          for (let index = 1; index < \(depth); index++) value = [value];
          return value;
        })()
        """
    }

    private func nestedValue(depth: Int) -> NestedValue {
        (0..<depth).reduce(.end) { value, _ in .next(value) }
    }
}
