import Foundation
import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
private struct SmokeUser: Codable, Sendable, Equatable {
    let id: Int
}

private struct SmokeModuleNamespace: Codable, Sendable, Equatable {
    let answer: Int
}

private enum HostFailure: Error, Sendable {
    case expected
}

private final class SmokeLogger {
    private let start = ContinuousClock.now
    private let fileHandle: FileHandle?

    init() {
        guard let path = ProcessInfo.processInfo.environment[
            "QUICKJSKIT_SMOKE_DIAGNOSTICS"
        ] else {
            fileHandle = nil
            return
        }

        let directory = URL(fileURLWithPath: path, isDirectory: true)
        let fileURL = directory.appendingPathComponent(
            "platform-smoke-stages.log"
        )
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        _ = FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        fileHandle = try? FileHandle(forWritingTo: fileURL)
    }

    deinit {
        try? fileHandle?.close()
    }

    func stage<Result: Sendable>(
        _ name: String,
        _ operation: () async throws -> Result
    ) async throws -> Result {
        log("stage: \(name)")
        do {
            let result = try await operation()
            log("stage passed: \(name)")
            return result
        } catch {
            log("stage failed: \(name)\n\(describe(error))")
            throw error
        }
    }

    func failure(_ error: Error) {
        log("smoke failed\n\(describe(error))")
    }

    private func log(_ message: String) {
        let elapsed = start.duration(to: .now)
        let line = "[\(elapsed)] \(message)\n"
        let data = Data(line.utf8)
        FileHandle.standardError.write(data)
        try? fileHandle?.write(contentsOf: data)
    }

    private func describe(_ error: Error) -> String {
        if let error = error as? JavaScriptError {
            return [
                "error.type: JavaScriptError",
                "error.kind: \(error.kind.rawValue)",
                "error.name: \(error.name ?? "<none>")",
                "error.message: \(error.message)",
                "error.sourceURL: \(error.sourceURL ?? "<none>")",
                "error.stack:\n\(error.stack ?? "<none>")",
            ].joined(separator: "\n")
        }
        return "error.type: \(String(reflecting: error))"
    }
}

@main
private struct PlatformSmoke {
    static func main() async throws {
        let logger = SmokeLogger()
        do {
            try await run(logger: logger)
        } catch {
            logger.failure(error)
            throw error
        }
    }

    private static func run(logger: SmokeLogger) async throws {
        let template = try await logger.stage("template-creation") {
            try JavaScriptRuntimeTemplate(configuration: .restricted) {
                Globals {
                    JavaScriptType(SmokeUser.self)
                    Function("syncSum") { (left: Int, right: Int) in
                        left + right
                    }
                    Function("throwingFailure") { () throws -> Int in
                        throw HostFailure.expected
                    }
                    Function("asyncAnswer") { () async -> Int in
                        42
                    }
                    Function("asyncFailure") { () async throws -> Int in
                        throw HostFailure.expected
                    }
                }
                SourceModule(
                    """
                    export const answer = 42;
                    export function double(value) { return value * 2; }
                    """,
                    as: "smoke:module"
                )
            }
        }

        let runtime = try await logger.stage("runtime-creation") {
            try await template.makeRuntime()
        }

        _ = try await logger.stage("initial-resource-usage") {
            let usage = await runtime.resourceUsage()
            guard usage.allocationLimit == JavaScriptRuntime.Configuration.restricted.memoryLimit,
                  usage.hostObjectLimit == JavaScriptRuntime.Configuration.restricted.maximumHostObjectCount,
                  usage.pendingHostCallLimit == JavaScriptRuntime.Configuration.restricted.maximumPendingHostCallCount
            else {
                throw SmokeFailure.resourceUsage
            }
            return usage
        }

        _ = try await logger.stage("raw-number") {
            let value: JavaScriptValue = try await runtime.evaluate("42")
            guard value.numberValue == 42 else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-boolean") {
            let value: JavaScriptValue = try await runtime.evaluate("true")
            guard value.booleanValue == true else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-string") {
            let value: JavaScriptValue = try await runtime.evaluate("'ok'")
            guard value.stringValue == "ok" else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-null") {
            let value: JavaScriptValue = try await runtime.evaluate("null")
            guard value.isNull else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        let undefinedValue: JavaScriptValue = try await logger.stage(
            "raw-undefined-evaluate"
        ) {
            try await runtime.evaluate("undefined")
        }

        _ = try await logger.stage("raw-undefined-check") {
            guard undefinedValue.isUndefined else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-void-zero-evaluate") {
            let value: JavaScriptValue = try await runtime.evaluate("void 0")
            guard value.isUndefined else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-global-undefined") {
            let value: JavaScriptValue = try await runtime.evaluate(
                "globalThis.undefined"
            )
            guard value.isUndefined else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-typeof-undefined") {
            let value: JavaScriptValue = try await runtime.evaluate(
                "typeof undefined"
            )
            guard value.stringValue == "undefined" else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-global-math") {
            let value: JavaScriptValue = try await runtime.evaluate("Math")
            guard value.objectValue != nil else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-arithmetic-recovery") {
            let value: Int = try await runtime.evaluate("40 + 2")
            guard value == 42 else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        _ = try await logger.stage("raw-bigint") {
            let value: JavaScriptValue = try await runtime.evaluate(
                "9007199254740993n"
            )
            guard value.bigIntValue != nil else {
                throw SmokeFailure.rawPrimitives
            }
            return true
        }

        let object = try await logger.stage("raw-object-and-array") {
            let objectValue: JavaScriptValue = try await runtime.evaluate(
                "({ answer: 42, removeMe: true })"
            )
            let arrayValue: JavaScriptValue = try await runtime.evaluate(
                "[1, 2]"
            )
            guard let object = objectValue.objectValue,
                  let array = arrayValue.arrayValue
            else {
                throw SmokeFailure.liveValues
            }
            guard try await array.count == 2 else {
                throw SmokeFailure.liveValues
            }
            return object
        }

        _ = try await logger.stage("object-properties") {
            let answer: Int = try await object.value(
                forProperty: "answer",
                as: Int.self
            )
            guard answer == 42,
                  try await object.hasProperty("removeMe")
            else {
                throw SmokeFailure.objectProperties
            }
            try await object.set(7, forProperty: "written")
            let written: Int = try await object.value(
                forProperty: "written",
                as: Int.self
            )
            guard written == 7 else {
                throw SmokeFailure.objectProperties
            }
            let names = try await object.propertyNames()
            guard names.contains("answer"), names.contains("written") else {
                throw SmokeFailure.objectProperties
            }
            guard try await object.deleteProperty("removeMe") else {
                throw SmokeFailure.objectProperties
            }
            return true
        }

        _ = try await logger.stage("array-operations") {
            let value: JavaScriptValue = try await runtime.evaluate("[1, 2]")
            guard let array = value.arrayValue else {
                throw SmokeFailure.liveValues
            }
            try await array.set(3, at: 1)
            try await array.append(4)
            let second: Int = try await array.value(at: 1, as: Int.self)
            let count = try await array.count
            guard second == 3, count == 3 else {
                throw SmokeFailure.arrayOperations
            }
            return true
        }

        let synchronousTotal: Int = try await logger.stage("synchronous-run") {
            try await runtime.run { runtime in
                let left: Int = try runtime.evaluate("20", as: Int.self)
                let right: Int = try runtime.evaluate("22", as: Int.self)
                return left + right
            }
        }
        guard synchronousTotal == 42 else {
            throw SmokeFailure.synchronousRun
        }

        let decodedUser: SmokeUser = try await logger.stage("typed-codable") {
            try await runtime.evaluate("({ id: 42, ignored: true })")
        }
        guard decodedUser == SmokeUser(id: 42) else {
            throw SmokeFailure.typedEvaluation
        }

        _ = try await logger.stage("raw-typeof") {
            let value: JavaScriptValue = try await runtime.evaluate(
                "typeof SmokeUser"
            )
            guard value.stringValue == "function" else {
                throw SmokeFailure.typedType
            }
            return true
        }

        _ = try await logger.stage("raw-type-function") {
            let value: JavaScriptValue = try await runtime.evaluate("SmokeUser")
            guard value.isFunction else {
                throw SmokeFailure.typedType
            }
            return true
        }

        let typeName: String = try await logger.stage("typed-typeof") {
            try await runtime.evaluate("typeof SmokeUser")
        }
        guard typeName == "function" else {
            throw SmokeFailure.typedType
        }

        let user: SmokeUser = try await logger.stage("value-construction") {
            try await runtime.evaluate("new SmokeUser({ id: 42, extra: true })")
        }
        guard user == SmokeUser(id: 42) else {
            throw SmokeFailure.typedEvaluation
        }

        _ = try await logger.stage("sync-binding") {
            let value: Int = try await runtime.evaluate("syncSum(20, 22)")
            guard value == 42 else { throw SmokeFailure.binding }
            return true
        }

        _ = try await logger.stage("throwing-binding") {
            do {
                let _: Int = try await runtime.evaluate("throwingFailure()")
                throw SmokeFailure.expectedError
            } catch let error as JavaScriptError {
                guard error.kind == .exception else {
                    throw SmokeFailure.binding
                }
            }
            return true
        }

        let asyncAnswer: Int = try await logger.stage("async-binding") {
            try await runtime.evaluate("asyncAnswer()")
        }
        guard asyncAnswer == 42 else {
            throw SmokeFailure.promise
        }

        _ = try await logger.stage("async-throwing-binding") {
            do {
                let _: Int = try await runtime.evaluate("asyncFailure()")
                throw SmokeFailure.expectedError
            } catch let error as JavaScriptError {
                guard error.kind == .exception else {
                    throw SmokeFailure.binding
                }
            }
            return true
        }

        _ = try await logger.stage("global-value") {
            try await runtime.global.set("configured", forProperty: "smokeValue")
            let value: String = try await runtime.global.value(
                forProperty: "smokeValue",
                as: String.self
            )
            guard value == "configured",
                  try await runtime.global.deleteProperty("smokeValue")
            else {
                throw SmokeFailure.globalValue
            }
            return true
        }

        _ = try await logger.stage("encoder-decoder") {
            let encoded = try await runtime.encoder.encode(SmokeUser(id: 42))
            let decoded = try await runtime.decoder.decode(
                SmokeUser.self,
                from: encoded
            )
            guard decoded == SmokeUser(id: 42) else {
                throw SmokeFailure.typedEvaluation
            }
            return true
        }

        let program = JavaScriptProgram("6 * 7", sourceURL: "prepared.js")
        _ = try await logger.stage("prepare-program") {
            try await runtime.prepare(program)
        }

        _ = try await logger.stage("evaluate-prepared-program") {
            let first: Int = try await runtime.evaluate(program)
            let second: Int = try await runtime.evaluate(program)
            guard first == 42, second == 42 else {
                throw SmokeFailure.preparedProgram
            }
            return true
        }

        let module = try await logger.stage("module-import") {
            try await runtime.importModule("smoke:module")
        }

        _ = try await logger.stage("module-export-names") {
            let names = try await module.exportNames()
            guard names.contains("answer"), names.contains("double") else {
                throw SmokeFailure.module
            }
            return true
        }

        _ = try await logger.stage("module-export-values") {
            let answer: Int = try await module.value(
                forExport: "answer",
                as: Int.self
            )
            let raw = try await module.value(forExport: "answer")
            guard answer == 42, raw.numberValue == 42 else {
                throw SmokeFailure.module
            }
            return true
        }

        _ = try await logger.stage("module-function-call") {
            let function = try await module.function(forExport: "double")
            let result: Int = try await function.call(21, as: Int.self)
            guard result == 42 else { throw SmokeFailure.module }
            return true
        }

        let namespace: SmokeModuleNamespace = try await logger.stage(
            "typed-module-namespace"
        ) {
            try await runtime.evaluateModule(
                "export const answer = 42;",
                as: SmokeModuleNamespace.self,
                sourceURL: "typed-module.js"
            )
        }
        guard namespace == SmokeModuleNamespace(answer: 42) else {
            throw SmokeFailure.module
        }

        _ = try await logger.stage("error-recovery") {
            do {
                let _: Int = try await runtime.evaluate(
                    "throw new Error('expected')"
                )
                throw SmokeFailure.expectedError
            } catch let error as JavaScriptError {
                guard error.kind == .exception else {
                    throw SmokeFailure.recovery
                }
            }
            let value: Int = try await runtime.evaluate("40 + 2")
            guard value == 42 else { throw SmokeFailure.recovery }
            return true
        }

        _ = try await logger.stage("garbage-collection") {
            await runtime.collectGarbage()
            return true
        }

        _ = try await logger.stage("final-resource-usage") {
            let usage = await runtime.resourceUsage()
            _ = usage.usedBytes
            return usage
        }

        _ = try await logger.stage("runtime-recovery") {
            let value: Int = try await runtime.evaluate("21 * 2")
            guard value == 42 else { throw SmokeFailure.recovery }
            return true
        }

        logger.success()
    }
}

private enum SmokeFailure: Error {
    case rawPrimitives
    case liveValues
    case objectProperties
    case arrayOperations
    case synchronousRun
    case typedType
    case typedEvaluation
    case binding
    case promise
    case globalValue
    case preparedProgram
    case module
    case recovery
    case resourceUsage
    case expectedError
}

private extension SmokeLogger {
    func success() {
        log("QuickJSKit platform smoke passed")
    }
}
