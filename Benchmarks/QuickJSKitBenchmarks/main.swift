import Foundation
import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
private struct BenchmarkPoint: Codable, Sendable {
    let x: Int
    let y: Int
}

@JavaScriptExport
private enum BenchmarkState: String, Codable, Sendable {
    case ready
    case stopped
}

private struct BenchmarkPayload: Codable, Sendable {
    let identifier: Int
    let name: String
    let enabled: Bool
}

private struct BenchmarkNestedPayload: Codable, Sendable {
    let payloads: [BenchmarkPayload]
    let metadata: [String: [Int]]
}

@JavaScriptExport
private final class BenchmarkHost: Sendable {
    let offset: Int

    init(offset: Int) {
        self.offset = offset
    }

    func add(_ value: Int) -> Int { value + offset }

    func consume(_ point: BenchmarkPoint) -> Int { point.x + point.y + offset }

    func same() -> BenchmarkHost { self }

    static func double(_ value: Int) -> Int { value * 2 }
}

@main
struct QuickJSKitBenchmarks {
    private struct Measurement {
        let name: String
        let iterations: Int
        let operationsPerIteration: Int
        let samples: [Double]

        var p50: Double { percentile(0.50) }
        var p95: Double { percentile(0.95) }
        var p99: Double { percentile(0.99) }
        var normalizedP50: Double { p50 / Double(operationsPerIteration) }
        var operationsPerSecond: Double {
            1_000_000_000 / normalizedP50
        }

        private func percentile(_ fraction: Double) -> Double {
            let sorted = samples.sorted()
            let index = Int((Double(sorted.count - 1) * fraction).rounded(.up))
            return sorted[index]
        }
    }

    private struct ScalarMetric {
        let name: String
        let value: UInt64
        let unit: String
    }

    private struct JSONReport: Codable {
        let measurements: [JSONMeasurement]
        let metrics: [JSONMetric]
    }

    private struct JSONMeasurement: Codable {
        let name: String
        let iterations: Int
        let operationsPerIteration: Int
        let p50Nanoseconds: Double
        let p95Nanoseconds: Double
        let p99Nanoseconds: Double
        let normalizedP50Nanoseconds: Double
        let operationsPerSecond: Double
    }

    private struct JSONMetric: Codable {
        let name: String
        let value: UInt64
        let unit: String
    }

    private struct BenchmarkSummary: Encodable {
        let label: String
        let runs: Int
        let measurements: [JSONMeasurement]
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        if arguments.dropFirst().first == "summarize" {
            try summarize(Array(arguments.dropFirst(2)))
            return
        }
        let iterations = try parseIterations(arguments)
        let usesJSON = arguments.contains("--json")
        let jsonOutput = try parseOption("--json-output", in: arguments)
        let consumerExecutable = try parseOption(
            "--consumer-executable",
            in: arguments
        )
        let source = "export const answer = 42;"
        let template = try equivalentTemplate(source: source)
        let preparedProgram = JavaScriptProgram(
            "20 + 22",
            sourceURL: "Benchmarks/prepared.js"
        )
        let largeProgram = JavaScriptProgram(
            "0" + (0..<256).map { " + \($0)" }.joined(),
            sourceURL: "Benchmarks/large.js"
        )

        let sourceRuntime = try JavaScriptRuntime()
        let preparedRuntime = try JavaScriptRuntime()
        try await preparedRuntime.prepare(preparedProgram)
        let largeSourceRuntime = try JavaScriptRuntime()
        let largePreparedRuntime = try JavaScriptRuntime()
        try await largePreparedRuntime.prepare(largeProgram)

        let hostCallRuntime = try JavaScriptRuntime()
        _ = try await hostCallRuntime.function("sum") {
            (left: Int, right: Int) in left + right
        }
        let hostCallProgram = JavaScriptProgram("sum(20, 22)")
        try await hostCallRuntime.prepare(hostCallProgram)

        let exportRuntime = try JavaScriptRuntime()
        try await exportRuntime.registerModule(
            "export function sum(left, right) { return left + right; }",
            as: "benchmark:exports"
        )
        let exportModule = try await exportRuntime.importModule("benchmark:exports")
        let exportedSum = try await exportModule.function(forExport: "sum")
        let repeatedImportRuntime = try await template.makeRuntime()
        _ = try await repeatedImportRuntime.importModule("benchmark:module")

        let linkedTemplate = try JavaScriptRuntimeTemplate {
            SourceModule(source, as: "benchmark:module")
            Startup {
                PreloadModule("benchmark:module")
            }
        }
        let startedTemplate = try JavaScriptRuntimeTemplate {
            SourceModule(source, as: "benchmark:module")
            Startup {
                ImportModule("benchmark:module")
            }
        }
        let bindingTemplates = try [1, 10, 100].map(makeBindingTemplate)
        let typeTemplate = try JavaScriptRuntimeTemplate {
            Globals {
                JavaScriptType(BenchmarkPoint.self)
                JavaScriptType(BenchmarkState.self)
                JavaScriptType(BenchmarkHost.self)
            }
        }
        let typeRuntime = try await typeTemplate.makeRuntime()
        let structProgram = JavaScriptProgram(
            "new BenchmarkPoint({ x: 20, y: 22 }).x"
        )
        let enumProgram = JavaScriptProgram("BenchmarkState('ready')")
        let hostProgram = JavaScriptProgram("new BenchmarkHost(2).add(40)")
        let mixedProgram = JavaScriptProgram(
            "new BenchmarkHost(2).consume({ x: 20, y: 20 })"
        )
        let identityProgram = JavaScriptProgram("""
            globalThis.benchmarkHost ??= new BenchmarkHost(1);
            benchmarkHost === benchmarkHost.same();
            """)
        for program in [structProgram, enumProgram, hostProgram, mixedProgram, identityProgram] {
            try await typeRuntime.prepare(program)
        }
        let provisioner = try JavaScriptRuntimeProvisioner(
            template: template,
            warmCapacity: 4,
            maximumConcurrentCreations: 4
        )
        try await provisioner.warmUp()

        var measurements: [Measurement] = []
        measurements.append(
            try await measure("manual-equivalent-runtime", iterations: iterations) {
                let runtime = try JavaScriptRuntime()
                _ = try await runtime.function("sum") {
                    (left: Int, right: Int) in left + right
                }
                try await runtime.registerModule(source, as: "benchmark:module")
            }
        )
        measurements.append(
            try await measure("template-equivalent-runtime", iterations: iterations) {
                _ = try await template.makeRuntime()
            }
        )
        for (count, bindingTemplate) in zip([1, 10, 100], bindingTemplates) {
            measurements.append(
                try await measure(
                    "template-runtime-with-\(count)-bindings",
                    iterations: iterations
                ) {
                    _ = try await bindingTemplate.makeRuntime()
                }
            )
        }
        measurements.append(
            try await measure("source-program-evaluation", iterations: iterations) {
                let _: Int = try await sourceRuntime.evaluate("20 + 22")
            }
        )
        measurements.append(
            try await measure("prepared-program-evaluation", iterations: iterations) {
                let _: Int = try await preparedRuntime.evaluate(preparedProgram)
            }
        )
        measurements.append(
            try await measure("large-source-evaluation", iterations: iterations) {
                let _: Int = try await largeSourceRuntime.evaluate(largeProgram.source)
            }
        )
        measurements.append(
            try await measure("large-prepared-program", iterations: iterations) {
                let _: Int = try await largePreparedRuntime.evaluate(largeProgram)
            }
        )
        measurements.append(
            try await measure("template-create-and-first-import", iterations: iterations) {
                let runtime = try await template.makeRuntime()
                let module = try await runtime.importModule("benchmark:module")
                let _: Int = try await module.value(forExport: "answer")
            }
        )
        measurements.append(
            try await measure("source-create-and-first-import", iterations: iterations) {
                let runtime = try JavaScriptRuntime()
                try await runtime.registerModule(source, as: "benchmark:module")
                let module = try await runtime.importModule("benchmark:module")
                let _: Int = try await module.value(forExport: "answer")
            }
        )
        measurements.append(
            try await measure("repeated-module-import", iterations: iterations) {
                let module = try await repeatedImportRuntime.importModule("benchmark:module")
                let _: Int = try await module.value(forExport: "answer")
            }
        )
        measurements.append(
            try await measure("template-create-and-link", iterations: iterations) {
                _ = try await linkedTemplate.makeRuntime()
            }
        )
        measurements.append(
            try await measure("template-create-and-start-module", iterations: iterations) {
                _ = try await startedTemplate.makeRuntime()
            }
        )
        measurements.append(
            try await measure("javascript-to-swift-call", iterations: iterations) {
                let _: Int = try await hostCallRuntime.evaluate(hostCallProgram)
            }
        )
        measurements.append(
            try await measure("retained-javascript-function-call", iterations: iterations) {
                let _: Int = try await exportedSum.call(20, 22)
            }
        )
        measurements.append(
            try await measure(
                "template-concurrent-creation",
                iterations: iterations,
                operationsPerIteration: 4
            ) {
                try await withThrowingTaskGroup(of: Void.self) { group in
                    for _ in 0..<4 {
                        group.addTask { _ = try await template.makeRuntime() }
                    }
                    try await group.waitForAll()
                }
            }
        )
        measurements.append(
            try await measure(
                "cold-provisioner-acquisition",
                iterations: iterations
            ) {
                let cold = try JavaScriptRuntimeProvisioner(
                    template: template,
                    warmCapacity: 1
                )
                _ = try await cold.makeRuntime()
                await cold.shutdown()
            }
        )
        measurements.append(
            try await measure("runtime-create-and-teardown", iterations: iterations) {
                var runtime: JavaScriptRuntime? = try JavaScriptRuntime()
                withExtendedLifetime(runtime) {}
                runtime = nil
            }
        )
        measurements.append(
            try await measure(
                "ready-provisioner-acquisition",
                iterations: iterations,
                beforeEach: { try await provisioner.warmUp() }
            ) {
                _ = try await provisioner.makeRuntime()
            }
        )
        measurements.append(
            try await measure("template-runtime-with-mixed-swift-types", iterations: iterations) {
                _ = try await typeTemplate.makeRuntime()
            }
        )
        measurements.append(
            try await measure("swift-struct-canonicalization", iterations: iterations) {
                let _: Int = try await typeRuntime.evaluate(structProgram)
            }
        )
        measurements.append(
            try await measure("swift-enum-validation", iterations: iterations) {
                let _: String = try await typeRuntime.evaluate(enumProgram)
            }
        )
        measurements.append(
            try await measure("swift-host-construction-and-call", iterations: iterations) {
                let _: Int = try await typeRuntime.evaluate(hostProgram)
            }
        )
        measurements.append(
            try await measure("mixed-value-host-call", iterations: iterations) {
                let _: Int = try await typeRuntime.evaluate(mixedProgram)
            }
        )
        measurements.append(
            try await measure("swift-host-identity-reuse", iterations: iterations) {
                let _: Bool = try await typeRuntime.evaluate(identityProgram)
            }
        )
        measurements.append(
            try await measure(
                "host-allocation-garbage-collection-teardown",
                iterations: iterations
            ) {
                let runtime = try await typeTemplate.makeRuntime()
                let _: Bool = try await runtime.evaluate("""
                    globalThis.hosts = Array.from(
                        { length: 100 },
                        (_, index) => new BenchmarkHost(index)
                    );
                    delete globalThis.hosts;
                    true;
                    """)
                await runtime.collectGarbage()
            }
        )
        measurements.append(
            contentsOf: try await additionalMeasurements(iterations: iterations)
        )
        if let consumerExecutable {
            measurements.append(
                try await measure(
                    "standalone-consumer-startup",
                    iterations: iterations
                ) {
                    try runConsumer(at: consumerExecutable)
                }
            )
        }

        try await provisioner.warmUp()
        let readyRuntime = try await provisioner.makeRuntime()
        let memory = await readyRuntime.resourceUsage()
        let hostMemoryRuntime = try await typeTemplate.makeRuntime()
        let hostMemoryBefore = await hostMemoryRuntime.resourceUsage()
        let _: Bool = try await hostMemoryRuntime.evaluate("""
            globalThis.hosts = Array.from(
                { length: 100 },
                (_, index) => new BenchmarkHost(index)
            );
            true;
            """)
        let hostMemoryAfter = await hostMemoryRuntime.resourceUsage()
        let hostMemoryDelta = hostMemoryAfter.usedBytes >= hostMemoryBefore.usedBytes
            ? hostMemoryAfter.usedBytes - hostMemoryBefore.usedBytes
            : 0
        let metrics = [
            ScalarMetric(
                name: "ready-runtime-used-memory",
                value: memory.usedBytes,
                unit: "bytes"
            ),
            ScalarMetric(
                name: "used-memory-per-host-instance",
                value: hostMemoryDelta / 100,
                unit: "bytes"
            ),
            ScalarMetric(
                name: "live-host-instance-count",
                value: (await hostMemoryRuntime.resourceUsage()).hostObjectCount,
                unit: "objects"
            ),
        ]
        await provisioner.shutdown()

        if usesJSON || jsonOutput != nil {
            let data = try jsonData(
                measurements: measurements,
                metrics: metrics
            )
            if let jsonOutput {
                try data.write(to: URL(fileURLWithPath: jsonOutput), options: .atomic)
            }
            if usesJSON {
                guard let string = String(data: data, encoding: .utf8) else {
                    throw BenchmarkError.invalidJSONOutput
                }
                print(string)
            }
        } else {
            printHuman(measurements: measurements, metrics: metrics, iterations: iterations)
        }
    }

    private static func additionalMeasurements(
        iterations: Int
    ) async throws -> [Measurement] {
        let conversionRuntime = try JavaScriptRuntime()
        let payload = BenchmarkPayload(
            identifier: 42,
            name: "QuickJSKit",
            enabled: true
        )
        let collection = Array(0..<128)
        let binary = Data((0..<4_096).map { UInt8(truncatingIfNeeded: $0) })
        let nestedPayload = BenchmarkNestedPayload(
            payloads: Array(repeating: payload, count: 16),
            metadata: ["values": collection]
        )
        let encodedPayload = try await conversionRuntime.encoder.encode(payload)
        let encodedCollection = try await conversionRuntime.encoder.encode(collection)
        let encodedBinary = try await conversionRuntime.encoder.encode(binary)
        let encodedNested = try await conversionRuntime.encoder.encode(nestedPayload)

        let promiseRuntime = try JavaScriptRuntime()
        _ = try await promiseRuntime.function("asyncAnswer") { () async -> Int in
            await Task.yield()
            return 42
        }
        let asyncPromiseProgram = JavaScriptProgram("asyncAnswer()")
        let fulfilledPromiseProgram = JavaScriptProgram("Promise.resolve(42)")
        try await promiseRuntime.prepare(asyncPromiseProgram)
        try await promiseRuntime.prepare(fulfilledPromiseProgram)

        var rejectingConfiguration = JavaScriptRuntime.Configuration()
        rejectingConfiguration.maximumPendingHostCallCount = 0
        let rejectingRuntime = try JavaScriptRuntime(
            configuration: rejectingConfiguration
        )
        _ = try await rejectingRuntime.function("rejectedAsyncCall") {
            () async -> Int in 42
        }
        let rejectionProgram = JavaScriptProgram("rejectedAsyncCall()")
        try await rejectingRuntime.prepare(rejectionProgram)

        let restrictedRuntime = try JavaScriptRuntime(configuration: .restricted)
        let restrictedProgram = JavaScriptProgram("20 + 22")
        try await restrictedRuntime.prepare(restrictedProgram)

        let accessRuntime = try JavaScriptRuntime()
        try await accessRuntime.global.set(42, forProperty: "answer")
        let objectValue = try await accessRuntime.evaluate("({ answer: 42 })")
        guard let object = objectValue.objectValue else {
            throw BenchmarkError.invalidFixture
        }
        let arrayValue = try await accessRuntime.evaluate("[42]")
        guard let array = arrayValue.arrayValue else {
            throw BenchmarkError.invalidFixture
        }
        try await accessRuntime.registerModule(
            "export const answer = 42;",
            as: "benchmark:access"
        )
        let module = try await accessRuntime.importModule("benchmark:access")

        var measurements: [Measurement] = []
        measurements.append(
            try await measure("encode-primitive", iterations: iterations) {
                _ = try await conversionRuntime.encoder.encode(42)
            }
        )
        measurements.append(
            try await measure("decode-primitive", iterations: iterations) {
                let _: Int = try await conversionRuntime.decoder.decode(
                    Int.self,
                    from: JavaScriptValue(42)
                )
            }
        )
        measurements.append(
            try await measure("encode-struct", iterations: iterations) {
                _ = try await conversionRuntime.encoder.encode(payload)
            }
        )
        measurements.append(
            try await measure("decode-struct", iterations: iterations) {
                let _: BenchmarkPayload = try await conversionRuntime.decoder.decode(
                    BenchmarkPayload.self,
                    from: encodedPayload
                )
            }
        )
        measurements.append(
            try await measure("encode-collection", iterations: iterations) {
                _ = try await conversionRuntime.encoder.encode(collection)
            }
        )
        measurements.append(
            try await measure("decode-collection", iterations: iterations) {
                let _: [Int] = try await conversionRuntime.decoder.decode(
                    [Int].self,
                    from: encodedCollection
                )
            }
        )
        measurements.append(
            try await measure("encode-data-4k", iterations: iterations) {
                _ = try await conversionRuntime.encoder.encode(binary)
            }
        )
        measurements.append(
            try await measure("decode-data-4k", iterations: iterations) {
                let _: Data = try await conversionRuntime.decoder.decode(
                    Data.self,
                    from: encodedBinary
                )
            }
        )
        measurements.append(
            try await measure("encode-nested-codable", iterations: iterations) {
                _ = try await conversionRuntime.encoder.encode(nestedPayload)
            }
        )
        measurements.append(
            try await measure("decode-nested-codable", iterations: iterations) {
                let _: BenchmarkNestedPayload =
                    try await conversionRuntime.decoder.decode(
                        BenchmarkNestedPayload.self,
                        from: encodedNested
                    )
            }
        )
        measurements.append(
            try await measure("fulfilled-promise-latency", iterations: iterations) {
                let _: Int = try await promiseRuntime.evaluate(
                    fulfilledPromiseProgram
                )
            }
        )
        measurements.append(
            try await measure("async-swift-promise-latency", iterations: iterations) {
                let _: Int = try await promiseRuntime.evaluate(asyncPromiseProgram)
            }
        )
        measurements.append(
            try await measure("restricted-profile-evaluation", iterations: iterations) {
                let _: Int = try await restrictedRuntime.evaluate(restrictedProgram)
            }
        )
        measurements.append(
            try await measure("pending-host-call-admission", iterations: iterations) {
                let _: Int = try await promiseRuntime.evaluate(asyncPromiseProgram)
            }
        )
        measurements.append(
            try await measure("pending-host-call-rejection", iterations: iterations) {
                do {
                    let _: Int = try await rejectingRuntime.evaluate(rejectionProgram)
                    throw BenchmarkError.expectedRejection
                } catch let error as JavaScriptError where error.name == "RangeError" {
                    return
                }
            }
        )
        measurements.append(
            try await measure("global-value-access", iterations: iterations) {
                let _: Int = try await accessRuntime.global.value(
                    forProperty: "answer"
                )
            }
        )
        measurements.append(
            try await measure("object-property-access", iterations: iterations) {
                let _: Int = try await object.value(forProperty: "answer")
            }
        )
        measurements.append(
            try await measure("array-element-access", iterations: iterations) {
                let _: Int = try await array.value(at: 0)
            }
        )
        measurements.append(
            try await measure("module-export-access", iterations: iterations) {
                let _: Int = try await module.value(forExport: "answer")
            }
        )
        return measurements
    }

    private static func equivalentTemplate(
        source: String
    ) throws -> JavaScriptRuntimeTemplate {
        try JavaScriptRuntimeTemplate {
            Globals {
                Function("sum") {
                    (left: Int, right: Int) in left + right
                }
            }
            SourceModule(source, as: "benchmark:module")
        }
    }

    private static func makeBindingTemplate(
        count: Int
    ) throws -> JavaScriptRuntimeTemplate {
        try JavaScriptRuntimeTemplate {
            Globals {
                for index in 0..<count {
                    Function("function\(index)") {
                        (value: Int) in value + index
                    }
                }
            }
        }
    }

    private static func measure(
        _ name: String,
        iterations: Int,
        operationsPerIteration: Int = 1,
        beforeEach: @escaping @Sendable () async throws -> Void = {},
        operation: @escaping @Sendable () async throws -> Void
    ) async throws -> Measurement {
        for _ in 0..<min(3, iterations) {
            try await beforeEach()
            try await operation()
        }

        let clock = ContinuousClock()
        var samples: [Double] = []
        samples.reserveCapacity(iterations)
        for _ in 0..<iterations {
            try await beforeEach()
            let start = clock.now
            try await operation()
            samples.append(nanoseconds(start.duration(to: clock.now)))
        }
        return Measurement(
            name: name,
            iterations: iterations,
            operationsPerIteration: operationsPerIteration,
            samples: samples
        )
    }

    private static func nanoseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000_000_000
            + Double(components.attoseconds) / 1_000_000_000
    }

    private static func parseIterations(_ arguments: [String]) throws -> Int {
        guard let index = arguments.firstIndex(of: "--iterations") else { return 100 }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex,
              let value = Int(arguments[valueIndex]),
              value > 0 else {
            throw BenchmarkError.invalidIterations
        }
        return value
    }

    private static func parseOption(
        _ name: String,
        in arguments: [String]
    ) throws -> String? {
        guard let index = arguments.firstIndex(of: name) else { return nil }
        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex,
              !arguments[valueIndex].isEmpty else {
            throw BenchmarkError.missingOptionValue(name)
        }
        return arguments[valueIndex]
    }

    private static func summarize(_ arguments: [String]) throws {
        let label = try requiredOption("--label", in: arguments)
        let jsonOutput = try requiredOption("--json-output", in: arguments)
        let markdownOutput = try requiredOption("--markdown-output", in: arguments)
        let optionNames: Set<String> = [
            "--label",
            "--json-output",
            "--markdown-output",
        ]
        var reportPaths: [String] = []
        var skipNext = false
        for argument in arguments {
            if skipNext {
                skipNext = false
            } else if optionNames.contains(argument) {
                skipNext = true
            } else {
                reportPaths.append(argument)
            }
        }
        guard !reportPaths.isEmpty else {
            throw BenchmarkError.noReportsToSummarize
        }

        let reports = try reportPaths.map {
            try JSONDecoder().decode(
                JSONReport.self,
                from: Data(contentsOf: URL(fileURLWithPath: $0))
            )
        }
        guard let firstReport = reports.first else {
            throw BenchmarkError.noReportsToSummarize
        }
        let measurements = try firstReport.measurements.map { measurement in
            let samples = try reports.map { report in
                guard let matchingMeasurement = report.measurements.first(
                    where: { $0.name == measurement.name }
                ) else {
                    throw BenchmarkError.inconsistentMeasurement(measurement.name)
                }
                return matchingMeasurement
            }
            return JSONMeasurement(
                name: measurement.name,
                iterations: measurement.iterations,
                operationsPerIteration: measurement.operationsPerIteration,
                p50Nanoseconds: median(samples.map(\.p50Nanoseconds)),
                p95Nanoseconds: median(samples.map(\.p95Nanoseconds)),
                p99Nanoseconds: median(samples.map(\.p99Nanoseconds)),
                normalizedP50Nanoseconds: median(
                    samples.map(\.normalizedP50Nanoseconds)
                ),
                operationsPerSecond: median(samples.map(\.operationsPerSecond))
            )
        }
        let summary = BenchmarkSummary(
            label: label,
            runs: reports.count,
            measurements: measurements
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(summary).write(
            to: URL(fileURLWithPath: jsonOutput),
            options: .atomic
        )

        var markdown = """
            # \(label)

            Runs: \(reports.count)

            | Measurement | Median p50 | Median p95 | Median p99 | Throughput |
            | --- | ---: | ---: | ---: | ---: |

            """
        for measurement in measurements {
            markdown += "| \(measurement.name) "
            markdown += "| \(Int(measurement.p50Nanoseconds)) ns "
            markdown += "| \(Int(measurement.p95Nanoseconds)) ns "
            markdown += "| \(Int(measurement.p99Nanoseconds)) ns "
            markdown += "| \(Int(measurement.operationsPerSecond)) ops/s |\n"
        }
        try Data(markdown.utf8).write(
            to: URL(fileURLWithPath: markdownOutput),
            options: .atomic
        )
    }

    private static func requiredOption(
        _ name: String,
        in arguments: [String]
    ) throws -> String {
        guard let value = try parseOption(name, in: arguments) else {
            throw BenchmarkError.missingOptionValue(name)
        }
        return value
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func printHuman(
        measurements: [Measurement],
        metrics: [ScalarMetric],
        iterations: Int
    ) {
        print("QuickJSKit startup and provisioning benchmarks")
        print("Samples per measurement: \(iterations)")
        for measurement in measurements {
            let p50 = String(format: "%.0f", measurement.p50)
            let p95 = String(format: "%.0f", measurement.p95)
            let p99 = String(format: "%.0f", measurement.p99)
            let normalized = String(format: "%.0f", measurement.normalizedP50)
            let throughput = String(format: "%.0f", measurement.operationsPerSecond)
            print(
                "\(measurement.name): p50 \(p50) ns, p95 \(p95) ns, "
                    + "p99 \(p99) ns, normalized p50 \(normalized) ns/op, "
                    + "\(throughput) ops/s"
            )
        }
        for metric in metrics {
            print("\(metric.name): \(metric.value) \(metric.unit)")
        }
    }

    private static func jsonData(
        measurements: [Measurement],
        metrics: [ScalarMetric]
    ) throws -> Data {
        let report = JSONReport(
            measurements: measurements.map {
                JSONMeasurement(
                    name: $0.name,
                    iterations: $0.iterations,
                    operationsPerIteration: $0.operationsPerIteration,
                    p50Nanoseconds: $0.p50,
                    p95Nanoseconds: $0.p95,
                    p99Nanoseconds: $0.p99,
                    normalizedP50Nanoseconds: $0.normalizedP50,
                    operationsPerSecond: $0.operationsPerSecond
                )
            },
            metrics: metrics.map {
                JSONMetric(name: $0.name, value: $0.value, unit: $0.unit)
            }
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(report)
    }

    private static func runConsumer(at path: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BenchmarkError.consumerFailed(process.terminationStatus)
        }
    }

    private enum BenchmarkError: Error {
        case invalidIterations
        case invalidFixture
        case invalidJSONOutput
        case expectedRejection
        case missingOptionValue(String)
        case noReportsToSummarize
        case inconsistentMeasurement(String)
        case consumerFailed(Int32)
    }
}
