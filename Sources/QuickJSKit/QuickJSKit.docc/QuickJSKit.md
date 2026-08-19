# ``QuickJSKit``

Embed QuickJS in a Swift application with an actor-isolated, type-safe API.

QuickJSKit lets an application evaluate JavaScript, exchange values through
Swift's `Codable` system, expose typed Swift capabilities, use ES modules,
bridge native Promises, generate TypeScript declarations, and create isolated
runtimes from reusable definitions.

```swift
import QuickJSKit

let runtime = try JavaScriptRuntime()
let answer: Int = try await runtime.evaluate("20 + 22")
```

Each ``JavaScriptRuntime`` owns one independent JavaScript heap. Operations on
that heap are serialized by the runtime actor; separate runtimes can make
progress concurrently. Live JavaScript handles remain associated with the
runtime that owns them, while decoded Swift values are detached data.

## Choose a path

### Run JavaScript

Choose <doc:BuildAHostForJavaScript> for an app command that turns a meeting
note into a typed plan. Choose <doc:BuildAProductionPluginRunner> for a
server workflow that reuses isolated runtime environments.

### Exchange values

Use <doc:EvaluationAndConversion> to learn typed evaluation, direct `Codable`
conversion, special values, and live identity.

### Expose Swift capabilities

Read <doc:BindingsAndPromises> for functions and Promises, then
<doc:ExportingSwiftTypes> for objects, actors, and modules.

### Use modules

<doc:ModulesAndLoaders> explains source modules, Swift modules, top-level
`await`, and custom asynchronous loaders.

### Reuse environments

Use <doc:RuntimeTemplates> for declarative environments and
<doc:RuntimeProvisioning> when runtimes should be prepared before demand.

### Generate TypeScript declarations

<doc:TypeScriptTooling> shows how to describe the exact JavaScript environment
to editors and TypeScript tooling.

### Run untrusted code

Read <doc:SecurityAndUntrustedCode> before accepting scripts from outside the
application, and use <doc:CancellationAndExecutionControl> for deadlines and
interrupts.

## Topics

### Learn the core model

- <doc:table-of-contents>
- <doc:BuildAHostForJavaScript>
- <doc:BuildAProductionPluginRunner>
- <doc:GettingStarted>
- <doc:RuntimeModel>
- <doc:EvaluationAndConversion>
- <doc:WorkingWithJavaScriptValues>
- <doc:ErrorsAndDiagnostics>

### Integrate Swift and JavaScript

- <doc:BindingsAndPromises>
- <doc:ExportingSwiftTypes>
- <doc:CompileTimeExports>
- <doc:ModulesAndLoaders>

### Build and provision runtimes

- <doc:RuntimeTemplates>
- <doc:RuntimeProvisioning>
- ``JavaScriptProgram``
- ``Globals``
- ``SwiftModule``
- ``RuntimeInstance``
- ``Startup``

### Work with values and data

- ``JavaScriptValue``
- ``JavaScriptObject``
- ``JavaScriptArray``
- ``JavaScriptFunction``
- ``JavaScriptBigInt``
- ``JavaScriptEncoder``
- ``JavaScriptDecoder``

### TypeScript and operations

- <doc:TypeScriptTooling>
- ``JavaScriptEnvironmentDescription``
- ``TypeScriptSchema``
- ``TypeScriptWorkspace``
- <doc:SecurityAndUntrustedCode>
- <doc:CancellationAndExecutionControl>
- <doc:PerformanceAndResourceUsage>
- <doc:PlatformSupport>

### Public API reference

- ``JavaScriptRuntime``
- ``JavaScriptRuntime/Configuration``
- ``JavaScriptExecutionOptions``
- ``JavaScriptResourceUsage``
- ``JavaScriptError``
- ``JavaScriptBinding``
- ``JavaScriptModule``
- ``JavaScriptModuleLoader``
- ``JavaScriptRuntimeTemplate``
- ``JavaScriptRuntimeProvisioner``
