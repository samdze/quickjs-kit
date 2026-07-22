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

    private struct JSONReport: Encodable {
        let measurements: [JSONMeasurement]
        let metrics: [JSONMetric]
    }

    private struct JSONMeasurement: Encodable {
        let name: String
        let iterations: Int
        let operationsPerIteration: Int
        let p50Nanoseconds: Double
        let p95Nanoseconds: Double
        let p99Nanoseconds: Double
        let normalizedP50Nanoseconds: Double
        let operationsPerSecond: Double
    }

    private struct JSONMetric: Encodable {
        let name: String
        let value: UInt64
        let unit: String
    }

    static func main() async throws {
        let arguments = CommandLine.arguments
        let iterations = try parseIterations(arguments)
        let usesJSON = arguments.contains("--json")
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

        try await provisioner.warmUp()
        let readyRuntime = try await provisioner.makeRuntime()
        let memory = await readyRuntime.memoryUsage()
        let hostMemoryRuntime = try await typeTemplate.makeRuntime()
        let hostMemoryBefore = await hostMemoryRuntime.memoryUsage()
        let _: Bool = try await hostMemoryRuntime.evaluate("""
            globalThis.hosts = Array.from(
                { length: 100 },
                (_, index) => new BenchmarkHost(index)
            );
            true;
            """)
        let hostMemoryAfter = await hostMemoryRuntime.memoryUsage()
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
                value: (await hostMemoryRuntime.memoryUsage()).hostObjectCount,
                unit: "objects"
            ),
        ]
        await provisioner.shutdown()

        if usesJSON {
            try printJSON(measurements: measurements, metrics: metrics)
        } else {
            printHuman(measurements: measurements, metrics: metrics, iterations: iterations)
        }
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

    private static func printJSON(
        measurements: [Measurement],
        metrics: [ScalarMetric]
    ) throws {
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
        let data = try encoder.encode(report)
        guard let string = String(data: data, encoding: .utf8) else {
            throw BenchmarkError.invalidJSONOutput
        }
        print(string)
    }

    private enum BenchmarkError: Error {
        case invalidIterations
        case invalidJSONOutput
    }
}
