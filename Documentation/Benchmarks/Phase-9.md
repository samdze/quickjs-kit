# Phase 9 Benchmark Report

## Method

Measurements were collected on the same Apple silicon machine with Swift 6.3
in release mode. Each report is the median of five independent runs.

- Baseline: commit `1e30a64543bbba69bfa9d3948080155be757fffd`
- Final implementation: Phase 9 working tree after the runtime resource changes
- Baseline samples per run: 100
- Final samples per run: 200
- Clock: Swift `ContinuousClock`
- Host: macOS 26.5, arm64

The report records the relevant baseline and result summary. The generated raw
JSON reports were intentionally not retained because no automated historical
comparison consumes them. Timing remains diagnostic rather than a unit-test
assertion because sub-microsecond measurements are sensitive to scheduling,
temperature, and code layout.

## Representative results

| Measurement | Baseline p50 | Final p50 | Final p95 | Final p99 |
| --- | ---: | ---: | ---: | ---: |
| Manual runtime creation | 32.458 µs | 34.750 µs | 43.292 µs | 89.541 µs |
| Template runtime creation | 39.292 µs | 38.166 µs | 45.083 µs | 80.167 µs |
| Template with 100 bindings | 125.709 µs | 119.667 µs | 133.125 µs | 177.625 µs |
| Prepared program evaluation | 0.667 µs | 0.583 µs | 0.792 µs | 0.959 µs |
| JavaScript-to-Swift call | 1.250 µs | 1.167 µs | 1.250 µs | 1.500 µs |
| Retained JavaScript function call | 1.125 µs | 1.083 µs | 1.250 µs | 1.542 µs |
| Concurrent template creation | 77.459 µs | 74.042 µs | 82.458 µs | 103.875 µs |
| Ready provisioner acquisition | 11.917 µs | 12.292 µs | 13.750 µs | 21.916 µs |

The final suite also records conversion, Promise, access, configured-limit, and
standalone-consumer measurements:

| Measurement | Final p50 | Final p95 | Final p99 |
| --- | ---: | ---: | ---: |
| Primitive encode / decode | 0.333 / 0.500 µs | 0.375 / 0.542 µs | 0.458 / 0.583 µs |
| Struct encode / decode | 1.334 / 1.250 µs | 3.792 / 1.625 µs | 8.125 / 1.833 µs |
| `Data` 4 KiB encode / decode | 1.166 / 0.792 µs | 3.584 / 1.125 µs | 6.209 / 1.291 µs |
| Fulfilled Promise | 0.833 µs | 0.875 µs | 0.917 µs |
| Asynchronously settled Swift Promise | 5.042 µs | 8.375 µs | 13.083 µs |
| Restricted-profile evaluation | 0.583 µs | 0.625 µs | 0.667 µs |
| Pending-call admission / rejection | 5.208 / 1.459 µs | 9.084 / 1.666 µs | 10.292 / 2.125 µs |
| Global, object, array, and module access | 0.500–0.542 µs | 0.542–0.584 µs | 0.625–0.667 µs |
| Standalone consumer startup | 3.343 ms | 4.013 ms | 4.500 ms |

## Interpretation

The established provisioning and call paths remain stable. Template creation
with 100 bindings, prepared evaluation, JavaScript-to-Swift calls, and
concurrent creation improved in the final measurements.

A second same-session run of the unchanged baseline was used to separate code
changes from machine drift. It placed the final implementation within eight
percent of the unchanged implementation on almost every existing path.
Repeated module import and source creation plus first import differed by less
than one and seven microseconds respectively, but crossed ten percent because
their absolute durations are small and varied between consecutive runs. Phase 9
does not change the module execution call graph; these differences are recorded
as measurement variability rather than attributed to a module implementation
change.

The configured runtime profile adds no measurable evaluation overhead. Pending
asynchronous-call accounting is paid only when an asynchronous host operation
is admitted or rejected.
