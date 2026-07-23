# Ownership, Cancellation, and Performance

Choose APIs that preserve identity only when identity is needed.

``JavaScriptRuntime`` owns one independent QuickJS heap and context. Temporary C
values use RAII, while long-lived objects, arrays, functions, modules, Promises,
and host objects live in actor-owned registries behind pointer-free handles.
The registries release their values before context and runtime teardown.

Codable conversion is the direct value path and avoids JSON. Live handles add
registry lifetime and identity costs. Retain a ``JavaScriptFunction`` when
calling the same export repeatedly, and use ``JavaScriptProgram`` to avoid
reparsing a known script.

Runtime templates reuse detached definitions and private compile-only artifacts
but never share a mutable heap. ``JavaScriptRuntimeProvisioner`` can move
provisioning latency ahead of demand at the cost of memory for ready runtimes.

Swift waiter cancellation is local. Promise producers continue for other
consumers unless their binding is explicitly removed with cancellation.
Execution timeouts cover active QuickJS work, not time suspended in Swift
bindings, loaders, or host Promise waiting.

Use ``JavaScriptRuntime/resourceUsage()`` and the benchmark executable to
measure real workloads. Micro-optimization must not weaken ownership,
isolation, deterministic cleanup, or source-canonical cache fallback.
