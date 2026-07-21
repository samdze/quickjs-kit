# ADR 0021: Precompiled programs and one-shot hot provisioning

- Status: Accepted
- Date: 2026-07-22

## Context

Compile-only module artifacts remove repeated parsing for registered ES
modules, but global scripts still parse on every evaluation and module linking
or top-level initialization remains on the first-use path. Some applications
also need runtime acquisition latency lower than fresh heap construction.

Cloning an evaluated QuickJS heap is not a supported ownership boundary. A
general reset cannot prove that arbitrary globals, module state, pending jobs,
host captures, and live values have returned to a pristine state.

## Decision

`JavaScriptProgram` is an immutable source-and-identity value. Templates compile
known programs once into private process-local artifacts, and every runtime
materializes an independent compiled function. Direct runtimes may prepare the
same program into their own heap. Evaluation duplicates the retained bytecode
value before `JS_EvalFunction`, so repeated execution cannot consume the cache.

Template startup remains explicit. Programs, module linking, and module imports
run only when declared and only after all shared definitions and per-runtime
roots are installed. Promise and top-level-await completion uses the ordinary
root-result machinery. Artifact failure discards the incomplete runtime and
retries once from canonical source before factories or startup execute.

`JavaScriptRuntimeProvisioner` is a separate actor that maintains bounded ready
capacity. It transfers runtimes permanently and creates replacements with
bounded concurrency. It never accepts a returned runtime and provides no reset
or leasing contract.

## Consequences

Known scripts avoid repeated parsing, and applications can choose whether
linking or initialization belongs to provisioning or first use. A prewarmed
runtime can leave the provisioner without constructing QuickJS state on the
request path, at the cost of explicit idle memory.

Arbitrary string evaluation, loader-returned source, persistent bytecode, heap
snapshots, reusable pools, custom allocators, and ROM-data bytecode remain
outside this optimization boundary.
