# TypeScript Tooling

Generate declarations and an editor workspace for the exact Swift-provided
JavaScript environment.

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

The managed writer changes only files it owns and whose previous contents match
its manifest unless overwrite is explicitly requested. It rejects traversal and
managed-path symlinks.

See <doc:MacroExports> for deriving schemas, TSDoc, and source maps from Swift
declarations.
