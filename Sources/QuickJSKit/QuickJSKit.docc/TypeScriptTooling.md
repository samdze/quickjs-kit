# TypeScript Tooling

Describe the exact Swift-provided JavaScript environment to TypeScript and
editor tooling.

```swift
let environment = try await runtime.environmentDescription()
let declarations = try environment.typeScriptDeclarations()
let workspace = try environment.typeScriptWorkspace(
    options: .init(
        sourceGlobs: ["Scripts/**/*.js", "Scripts/**/*.ts"],
        checkJavaScript: true,
        includePackageJSON: true
    )
)
try workspace.write(to: workspaceURL)
```

The detached environment snapshot contains globals, exported objects,
Swift-defined modules, known source modules, reachable schemas, structured
TSDoc, and logical source locations. It retains no runtime, closure, actor,
QuickJS value, or pointer.

Schemas may be ambient globals, members of named namespaces, or exports of an
ES module. Type-level namespaces do not create JavaScript objects. Module
declarations group cross-module references into local `import type` statements;
global declarations retain inline `import("...").Type` references so the
generated file remains ambient.

Template publication supplies the location for macro-generated types:

```swift
let template = try JavaScriptRuntimeTemplate {
    Globals {
        JavaScriptType(Configuration.self)
    }
    SwiftModule("host:users") {
        JavaScriptType(User.self)
    }
}
```

The same rule applies to immediate `registerType` and `defineModule` calls.
Register a referenced type separately when it belongs in another module;
otherwise its schema follows the container that publishes it.

The managed writer changes only files it owns and whose previous contents match
its manifest unless overwrite is explicitly requested. It rejects traversal and
managed-path symlinks.

## Choose a source of metadata

Call ``JavaScriptRuntime/environmentDescription(including:)`` for the environment already
installed in a runtime. Call ``JavaScriptRuntimeTemplate/environmentDescription(including:)``
when declarations are needed without creating a runtime or invoking a per-runtime
factory.

Both snapshots are detached metadata. They contain globals, exported objects,
Swift-defined modules, source modules, reachable schemas, structured TSDoc, and
logical source locations, but no runtime, closure, actor, live value, or C
state.

## Describe schemas

Use ``TypeScriptSchemaProviding`` for custom Codable shapes, or construct
``TypeScriptSchema`` directly for interfaces, aliases, and enumerations. A
schema can be ambient, belong to a named namespace, or be exported from an ES
module. Type-level namespaces do not create JavaScript objects.

## Document the generated API

Attach ``TypeScriptDocumentation`` to functions, containers, properties, and
schema definitions. Documentation can include remarks, examples, parameters,
return values, thrown errors, links, deprecations, and default values.

Use strict documentation completeness when generated declarations are a public
contract. Use the permissive mode while incrementally documenting an existing
environment.

See <doc:CompileTimeExports> for deriving schemas, TSDoc, and source maps from
Swift declarations.

## Related guides

- <doc:CompileTimeExports>
- <doc:RuntimeTemplates>
- <doc:ExportingSwiftTypes>
