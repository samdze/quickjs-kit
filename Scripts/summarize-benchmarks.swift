#!/usr/bin/env swift

import Foundation

struct Report: Decodable {
    let measurements: [Measurement]
}

struct Measurement: Codable {
    let name: String
    let iterations: Int
    let operationsPerIteration: Int
    let p50Nanoseconds: Double
    let p95Nanoseconds: Double
    let p99Nanoseconds: Double
    let normalizedP50Nanoseconds: Double
    let operationsPerSecond: Double
}

struct Summary: Codable {
    let label: String
    let runs: Int
    let measurements: [Measurement]
}

enum SummaryError: Error, CustomStringConvertible {
    case invalidArguments
    case noReports
    case inconsistentMeasurements(String)

    var description: String {
        switch self {
        case .invalidArguments:
            "Usage: summarize-benchmarks.swift --label LABEL "
                + "--json-output FILE --markdown-output FILE REPORT..."
        case .noReports:
            "At least one benchmark report is required."
        case let .inconsistentMeasurements(name):
            "Benchmark reports do not contain the same measurement: \(name)"
        }
    }
}

func value(after option: String, in arguments: [String]) throws -> String {
    guard let index = arguments.firstIndex(of: option) else {
        throw SummaryError.invalidArguments
    }
    let valueIndex = arguments.index(after: index)
    guard valueIndex < arguments.endIndex else {
        throw SummaryError.invalidArguments
    }
    return arguments[valueIndex]
}

func median(_ values: [Double]) -> Double {
    let sorted = values.sorted()
    let middle = sorted.count / 2
    if sorted.count.isMultiple(of: 2) {
        return (sorted[middle - 1] + sorted[middle]) / 2
    }
    return sorted[middle]
}

let arguments = Array(CommandLine.arguments.dropFirst())

do {
    let label = try value(after: "--label", in: arguments)
    let jsonOutput = try value(after: "--json-output", in: arguments)
    let markdownOutput = try value(after: "--markdown-output", in: arguments)
    let optionNames = Set([
        "--label",
        "--json-output",
        "--markdown-output",
    ])
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
    guard !reportPaths.isEmpty else { throw SummaryError.noReports }

    let decoder = JSONDecoder()
    let reports = try reportPaths.map {
        try decoder.decode(
            Report.self,
            from: Data(contentsOf: URL(fileURLWithPath: $0))
        )
    }
    let names = reports[0].measurements.map(\.name)
    let measurements = try names.map { name in
        let samples = try reports.map { report in
            guard let measurement = report.measurements.first(where: {
                $0.name == name
            }) else {
                throw SummaryError.inconsistentMeasurements(name)
            }
            return measurement
        }
        guard let first = samples.first else {
            throw SummaryError.inconsistentMeasurements(name)
        }
        return Measurement(
            name: name,
            iterations: first.iterations,
            operationsPerIteration: first.operationsPerIteration,
            p50Nanoseconds: median(samples.map(\.p50Nanoseconds)),
            p95Nanoseconds: median(samples.map(\.p95Nanoseconds)),
            p99Nanoseconds: median(samples.map(\.p99Nanoseconds)),
            normalizedP50Nanoseconds: median(
                samples.map(\.normalizedP50Nanoseconds)
            ),
            operationsPerSecond: median(samples.map(\.operationsPerSecond))
        )
    }
    let summary = Summary(
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
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
