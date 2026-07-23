# Phase 8.1 Benchmark Record

- Date: 2026-07-23
- Toolchain: Swift 6.3 release toolchain
- Configuration: `swift run -c release QuickJSKitBenchmarks --iterations 100 --json`
- Protocol: five independent runs before the change and five independent
  confirmation runs after all release gates

Each reported value is the median of the five per-run percentiles. Times are
microseconds.

| Measurement | Before p50 | After p50 | Change |
|---|---:|---:|---:|
| Template-equivalent runtime | 56.917 | 35.666 | -37.3% |
| Runtime with 100 bindings | 178.500 | 115.166 | -35.5% |
| Prepared program evaluation | 0.917 | 0.625 | -31.8% |
| Template creation and first import | 54.667 | 42.000 | -23.2% |
| JavaScript-to-Swift call | 1.875 | 1.208 | -35.6% |
| Retained JavaScript function call | 1.708 | 1.083 | -36.6% |
| Concurrent template creation | 109.083 | 74.000 | -32.2% |
| Ready provisioner acquisition | 17.042 | 12.250 | -28.1% |
| Swift struct canonicalization | 3.292 | 2.125 | -35.4% |
| Swift host construction and call | 2.916 | 1.875 | -35.7% |
| Host allocation, collection, teardown | 223.834 | 141.084 | -37.0% |

All 27 runtime measurements improved at p50 and p95. Twenty-six also had no
regression above ten percent at p99. `source-program-evaluation` improved from
1.958 to 1.250 microseconds at p50 and from 2.083 to 1.417 microseconds at p95,
while its p99 rose from 2.500 to 3.541 microseconds. With 100 samples, p99 is a
single second-slowest observation; two independent five-run post-change sets
reproduced the faster p50/p95 and a scheduler-sensitive p99 outlier.

Phase 8.1 changes compile-time macro analysis only and does not change a runtime
source file or the benchmark workload. The broad change in timings therefore
reflects machine frequency and load state rather than a claimed runtime
optimization. The useful gate result is that no central tendency regressed and
the isolated tail observation has no corresponding runtime code path change.

Memory stayed byte-identical:

- ready runtime used memory: 68,082 bytes;
- used memory per host instance: 201 bytes;
- live host instance count: 100.
