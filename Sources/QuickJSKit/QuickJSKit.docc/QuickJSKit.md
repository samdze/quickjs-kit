# ``QuickJSKit``

Embed QuickJS through an actor-isolated, type-safe Swift API.

## Overview

QuickJSKit hides C pointers and manual ownership while providing direct
`Codable` conversion, live JavaScript values, typed Swift bindings, native
Promise interoperability, ES modules, execution controls, TypeScript tooling,
and reusable runtime templates.

Start with one runtime for an independently isolated JavaScript heap:

```swift
let runtime = try JavaScriptRuntime()
let answer: Int = try await runtime.evaluate("20 + 22")
```

Use ``JavaScriptRuntimeTemplate`` when several runtimes need the same declared
environment. See <doc:RuntimeTemplates>.

## Topics

### Runtime provisioning

- ``JavaScriptRuntime``
- ``JavaScriptRuntimeTemplate``
- ``JavaScriptProgram``
- ``JavaScriptRuntimeProvisioner``
- ``Globals``
- ``Function``
- ``Value``
- ``RuntimeInstance``
- ``Startup``

### JavaScript values

- ``JavaScriptValue``
- ``JavaScriptObject``
- ``JavaScriptArray``
- ``JavaScriptFunction``
- ``JavaScriptBigInt``

### Modules and tooling

- ``JavaScriptModule``
- ``JavaScriptModuleLoader``
- ``JavaScriptEnvironmentDescription``
- ``TypeScriptSchema``
- ``TypeScriptWorkspace``
