import Dispatch
import Foundation
import QuickJSKit

/// Coverage-guided entry point for parser, module, conversion, and tooling
/// boundaries. Build this target with `-sanitize=fuzzer,address`.
@_cdecl("LLVMFuzzerTestOneInput")
public func quickJSKitFuzzOneInput(
    _ bytes: UnsafePointer<UInt8>?,
    _ count: Int
) -> Int32 {
    guard let bytes, count > 1, count <= 1_048_576 else {
        return 0
    }

    let input = Data(bytes: bytes, count: count)
    let completion = DispatchSemaphore(value: 0)

    Task.detached {
        await exercise(input)
        completion.signal()
    }

    completion.wait()
    return 0
}

private func exercise(_ input: Data) async {
    let mode = input[0] % 5
    let payload = String(decoding: input.dropFirst(), as: UTF8.self)

    do {
        switch mode {
        case 0:
            try await exerciseEvaluation(payload)
        case 1:
            try await exerciseModules(payload)
        case 2:
            try await exerciseCodable(payload)
        case 3:
            try exerciseDeclarations(payload)
        default:
            try await exerciseNesting(payload)
        }
    } catch {
        // Rejected input is expected. Crashes, traps, leaks, and sanitizer
        // findings are the fuzzing oracle.
    }
}

private func makeRuntime() throws -> JavaScriptRuntime {
    var configuration = JavaScriptRuntime.Configuration.restricted
    configuration.memoryLimit = 8 * 1_024 * 1_024
    configuration.maximumStackSize = 256 * 1_024
    configuration.defaultExecutionTimeout = .milliseconds(25)
    configuration.maximumHostObjectCount = 32
    configuration.maximumPendingHostCallCount = 16
    return try JavaScriptRuntime(configuration: configuration)
}

private func exerciseEvaluation(_ source: String) async throws {
    let runtime = try makeRuntime()
    _ = try await runtime.evaluate(source)
}

private func exerciseModules(_ source: String) async throws {
    let runtime = try makeRuntime()
    try await runtime.registerModule(
        source,
        as: "fuzz:root",
        sourceURL: "fuzz-root.js"
    )
    try await runtime.preloadModule("fuzz:root")
}

private struct FuzzModel: Codable, Sendable {
    let value: String?
    let items: [Int]
}

private func exerciseCodable(_ source: String) async throws {
    let runtime = try makeRuntime()
    _ = try await runtime.run { runtime in
        try runtime.evaluate(source, as: FuzzModel.self)
    }
}

private func exerciseDeclarations(_ text: String) throws {
    let schema = TypeScriptSchema.interface(
        "FuzzModel",
        documentation: .init(
            summary: text,
            examples: [.init(title: text, body: text)]
        ),
        properties: [
            .init(
                "value",
                type: .string,
                documentation: .init(summary: text)
            ),
        ]
    )
    let template = try JavaScriptRuntimeTemplate {}
    let environment = try template.environmentDescription(
        including: [schema]
    )
    _ = try environment.typeScriptDeclarations(
        options: .init(completeness: .allowUntyped)
    )
}

private func exerciseNesting(_ source: String) async throws {
    let runtime = try makeRuntime()
    let value = try await runtime.evaluate(source)
    var decoder = runtime.decoder
    decoder.maximumNestingDepth = 16
    _ = try await decoder.decode([String: [Int]].self, from: value)
}
