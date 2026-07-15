import Foundation
import Testing
import QuickJSKit

@Suite("Error handling examples")
struct ErrorExamplesTests {
    struct User: Decodable, Sendable {
        let id: Int
    }

    @Test("JavaScript exceptions preserve stack traces")
    func exceptionsRemainJavaScriptErrors() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            _ = try await runtime.evaluate(
                "throw new TypeError('wrong value')",
                sourceURL: "example.js"
            )
            Issue.record("Expected evaluation to throw")
        } catch let error as JavaScriptError {
            #expect(error.kind == .exception)
            #expect(error.name == "TypeError")
            #expect(error.stack?.contains("example.js") == true)
        }
    }

    @Test("syntax failures use the syntax error category")
    func syntaxFailuresAreCategorized() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            _ = try await runtime.evaluate("const =", sourceURL: "broken.js")
            Issue.record("Expected parsing to throw")
        } catch let error as JavaScriptError {
            #expect(error.kind == .syntax)
            #expect(error.name == "SyntaxError")
            #expect(error.sourceURL == "broken.js")
        }
    }

    @Test("shape mismatches use standard DecodingError")
    func mismatchesUseDecodingError() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            let _: User = try await runtime.evaluate("({ id: 'not an integer' })")
            Issue.record("Expected decoding to throw")
        } catch let error as DecodingError {
            guard case let .typeMismatch(_, context) = error else {
                Issue.record("Expected typeMismatch, received \(error)")
                return
            }
            #expect(context.codingPath.map(\.stringValue) == ["id"])
        }
    }

    @Test("Codable ignores inherited and non-enumerable properties")
    func codableUsesOwnEnumerableProperties() async throws {
        let runtime = try JavaScriptRuntime()

        do {
            let _: User = try await runtime.evaluate("""
                (() => {
                  const object = Object.create({ id: 42 });
                  Object.defineProperty(object, "hidden", { value: true });
                  return object;
                })()
                """)
            Issue.record("Expected the inherited id property to be unavailable")
        } catch let error as DecodingError {
            guard case let .keyNotFound(key, _) = error else {
                Issue.record("Expected keyNotFound, received \(error)")
                return
            }
            #expect(key.stringValue == "id")
        }
    }

    @Test("invalid special-type representations use DecodingError")
    func invalidSpecialTypesAreRejected() async throws {
        let runtime = try JavaScriptRuntime()

        await #expect(throws: DecodingError.self) {
            let _: Data = try await runtime.evaluate("[256]")
        }
        await #expect(throws: DecodingError.self) {
            let _: JavaScriptBigInt = try await runtime.evaluate("42")
        }
        await #expect(throws: DecodingError.self) {
            let _: Date = try await runtime.evaluate("NaN")
        }
        await #expect(throws: DecodingError.self) {
            let _: URL = try await runtime.evaluate("({ href: 42 })")
        }
    }

    @Test("function exceptions remain JavaScriptError values")
    func functionExceptionsRemainJavaScriptErrors() async throws {
        let runtime = try JavaScriptRuntime()
        let value = try await runtime.evaluate("() => { throw new RangeError('outside'); }")
        let function = try #require(value.functionValue)

        do {
            let _: Int = try await function.call()
            Issue.record("Expected the function to throw")
        } catch let error as JavaScriptError {
            #expect(error.name == "RangeError")
            #expect(error.message == "outside")
        }
    }

    @Test("values cannot cross runtime boundaries")
    func runtimeMismatchIsExplicit() async throws {
        let first = try JavaScriptRuntime()
        let second = try JavaScriptRuntime()
        let value = try await first.evaluate("({ answer: 42 })")

        do {
            try await second.global.set(value, forProperty: "foreign")
            Issue.record("Expected assignment to throw")
        } catch let error as JavaScriptError {
            #expect(error.kind == .runtime)
        }
    }
}
