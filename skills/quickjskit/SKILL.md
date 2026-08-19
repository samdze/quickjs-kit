---
name: quickjskit
description: Guide package users integrating QuickJSKit into Swift apps and services. Use when designing, implementing, debugging, reviewing, or testing JavaScriptRuntime evaluation, Codable conversion, live JavaScript values, Swift bindings and Promises, modules and loaders, runtime templates and provisioning, @JavaScriptExport, TypeScript declarations, cancellation, resource limits, diagnostics, or untrusted JavaScript execution.
---

# QuickJSKit integration

Build integrations from QuickJSKit's public Swift API. Treat every
`JavaScriptRuntime` as an actor-isolated ownership boundary around one
JavaScript heap. Do not use QuickJS C APIs, retain engine pointers, or invent
an application-side runtime wrapper unless the existing public API cannot
express a demonstrated requirement.

## Work in this order

1. State what crosses the Swift/JavaScript boundary: detached data, a live JS
   identity, a host capability, a module, or a reusable runtime definition.
2. Select one pattern below. Start with the least stateful pattern that meets
   the requirement.
3. Implement with public APIs and preserve the listed invariants.
4. Add the success test and the boundary test named by the pattern.
5. Read the canonical sources only when an API signature, configuration option,
   or advanced edge case still needs confirmation.

Do not default to JSON conversion, a shared global runtime, live values, or a
general-purpose host API. Prefer typed data, narrow capabilities, and explicit
publication locations.

## Pattern: transfer ordinary data

Use typed evaluation, calls, and property reads when the result is a Swift
value. `Codable` is the transfer contract; `Sendable` keeps the model usable
across Swift concurrency domains.

```swift
struct User: Codable, Sendable, Equatable {
    let id: Int
    let name: String
}

let runtime = try JavaScriptRuntime()
let user: User = try await runtime.evaluate(
    "({ id: 42, name: 'Ada' })"
)
```

Use an explicit result type and `sourceURL` when diagnostics need a stable
source location. Typed APIs await native JavaScript Promises before decoding.

Avoid evaluating to a live value and serializing it through JSON just to decode
it later. Avoid using a live value when identity and mutation do not matter.

If required, test a representative successful decode and each relevant boundary: missing
required data, wrong representation, JavaScript exception, syntax error, and
timeout.

## Pattern: preserve JavaScript identity

Use `JavaScriptValue`, `JavaScriptObject`, `JavaScriptArray`, or
`JavaScriptFunction` only when JavaScript identity, mutation, sparse arrays,
an explicit `this`, or repeated calls matter.

```swift
let value = try await runtime.evaluate("({ answer: 42 })")
let object = try #require(value.objectValue)

try await object.set(43, forProperty: "answer")
let answer: Int = try await object.value(forProperty: "answer")
```

Treat a live handle as runtime-affine even though it is pointer-free and safe
to store across Swift executors. Every operation returns to its owner runtime.

Never pass a live object, array, function, or value to another runtime. Decode
to a detached `Codable` DTO in the source runtime, then encode that DTO in the
destination runtime. This intentionally loses JavaScript identity, prototypes,
functions, symbols, and non-data properties.

## Pattern: expose a narrow Swift capability

Use a typed runtime binding for a small Swift operation exposed to JavaScript.
Preserve the Swift closure's effects exactly.

```swift
try await runtime.function("loadUser") {
    (id: Int) async throws -> User in
    try await service.loadUser(id: id)
}

let user: User = try await runtime.evaluate("loadUser(42)")
```

| Swift closure | JavaScript behavior |
| --- | --- |
| Synchronous | Returns a normal value |
| Throwing | Throws a JavaScript exception |
| Async | Returns a native Promise |
| Async throwing | Returns a Promise that can reject |

Use parameter names and documentation when the binding is a user-facing
JavaScript API. Keep the returned binding when the application needs explicit
removal or lifecycle control.

Avoid blocking the runtime actor while waiting for I/O. Put external work in an
async binding. Do not assume that dropping a JavaScript Promise cancels host
work. Cancelling one Swift waiter does not cancel a shared Promise producer;
remove a binding with `cancellingInFlight: true` only when the binding owns work
that should be cancelled for every consumer.

## Pattern: organize JavaScript as modules

Register known source modules for application-owned code. Define Swift modules
for namespaced host capabilities. Import a module when its namespace or exports
are the required result.

```swift
try await runtime.registerModule(
    "export const answer = 42;",
    as: "app:answer"
)

let module = try await runtime.importModule("app:answer")
let answer: Int = try await module.value(forExport: "answer")
```

Use a custom `JavaScriptModuleLoader` only when the application supplies a
complete, deliberate source policy. Canonicalize specifiers, allowlist every
host module, restrict relative imports to the intended namespace, and reject
unknown specifiers without falling back to disk, network, npm, or a package
manager. Give generated sources stable synthetic `sourceURL` values.

Avoid dynamically fetching arbitrary modules from inside a loader. Prevalidate
the complete source bundle before runtime creation when running user-supplied
code. Do not expose a module loader as an ambient filesystem or network
capability.

## Pattern: reuse runtime definitions, never runtime state

Use `JavaScriptRuntimeTemplate` to describe a repeatable runtime: configuration,
globals, Swift modules, source modules, and detached metadata. Create a runtime
from the template for each independent heap.

```swift
let template = try JavaScriptRuntimeTemplate(configuration: .restricted) {
    Globals {
        Function("sum") { (left: Int, right: Int) in left + right }
    }
}

let runtime = try await template.makeRuntime()
let answer: Int = try await runtime.evaluate("sum(20, 22)")
```

Use prepared programs when the same source must be compiled once and invoked in
many otherwise independent runtimes. Use `JavaScriptRuntimeProvisioner` only
when predictable acquisition latency justifies prewarmed memory and creation
capacity.

Never put live values, runtime-bound closures, or mutable per-runtime state in
a template. Each created runtime has its own heap, globals, modules, jobs,
limits, and failure domain. A provisioner permanently transfers a runtime to
the caller; it is not a resettable pool and shutdown does not reclaim handed-out
runtimes.

## Pattern: publish Swift types and TypeScript contracts

Use `@JavaScriptExport` from `QuickJSKitMacros` for supported Swift value types,
final classes, and actors. Treat the macro as checked export metadata, not as a
publication location. Publish it explicitly through a global or module
container.

```swift
import QuickJSKit
import QuickJSKitMacros

@JavaScriptExport
struct User: Codable, Sendable {
    let id: Int
    let name: String
}

let template = try JavaScriptRuntimeTemplate {
    SwiftModule("host:users") {
        JavaScriptType(User.self)
    }
}

let declarations = try template.environmentDescription()
    .typeScriptDeclarations()
```

Use a value type when JavaScript receives transferred data. Use a final class
or actor only when JavaScript needs a live host identity and its lifecycle is
explicitly acceptable. Keep API documentation accurate because it can become
TSDoc. Generate declarations from the same detached metadata that defines the
actual globals and module exports.

Never give an exported Swift type an intrinsic host scope. Do not publish a live
host type at multiple locations. Do not claim TypeScript declarations describe
an API that is not actually published in the matching runtime/template.

## Pattern: control execution and untrusted code

Choose explicit memory, JavaScript stack, active-execution, host-object, and
pending-host-call limits from measured application behavior. Apply an operation
timeout for request-specific deadlines and use Swift cancellation for the
end-to-end caller boundary.

Treat the timeout as a limit on active QuickJS work only. It does not include
time suspended in a Swift binding, loader, or host Promise. Give host I/O its
own authorization, cancellation, rate, and deadline policy.

Start from `.restricted` for untrusted or constrained workloads, then tune and
test the limits. It is in-process resource control, not an operating-system
sandbox. Run hostile or multi-tenant code in a separately sandboxed process
when isolation from application memory and native capabilities is required.

Install observation appropriate to the application: structured JavaScript
errors, unhandled Promise rejections, loader failures, timeouts, and
`resourceUsage()`. Keep exported capabilities minimal; QuickJSKit grants no
implicit filesystem, network, credential, process, or npm access.

## Review and completion gate

Before declaring an integration complete, answer all of these questions:

1. Is every cross-boundary data value typed `Codable` unless JavaScript identity
   is explicitly required?
2. Does every live handle stay in its owning runtime, with a DTO snapshot for
   every cross-runtime transfer?
3. Do bindings preserve synchronous, throwing, async, and async-throwing
   semantics without blocking an actor?
4. Are cancellation, timeout, and host-work ownership separately understood and
   tested?
5. Does every loader/module capability have an explicit allowlist and a stable
   diagnostic source URL?
6. Do templates share definitions only, never mutable heap state or live values?
7. Do macro exports have exactly the intended global or module publication
   location, and do generated declarations match it?
8. Does untrusted-code handling use minimal capabilities, measured limits, and
   a real process boundary where an OS sandbox is required?
9. Do focused tests cover success plus the relevant error, lifecycle, isolation,
   or cancellation boundary without network access, sleeps, or shared state?

## Consult package documentation when needed

Use the package documentation and public examples only to confirm an API
signature, option, or advanced behavior after selecting a pattern. Search for
the topic that matches the work:

- Evaluation and conversion for typed data transfer and decoding failures.
- Runtime model and JavaScript values for live-handle lifetime, identity, and
  runtime affinity.
- Bindings, Promises, and cancellation for host effects, Promise settlement,
  interruption, and pending-call behavior.
- Modules and loaders for source registration, resolution, asynchronous loading,
  and module policy.
- Runtime templates and provisioning for prepared programs, startup, warm
  capacity, and transfer semantics.
- Compile-time exports and TypeScript tooling for macro support, publication,
  schemas, TSDoc, and generated declarations.
- Security and untrusted code for resource controls, capability design,
  observability, and process isolation.
