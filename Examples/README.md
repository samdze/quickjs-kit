# QuickJSKit Examples

This standalone Swift package demonstrates complete consumer workflows without
`@testable` imports or C access.

```sh
swift run --package-path Examples TypedEvaluation
swift run --package-path Examples AsyncHostAPI
swift run --package-path Examples ModuleEmbedding
swift run --package-path Examples RuntimeTemplates
swift run --package-path Examples TypeScriptWorkspace
```

- `TypedEvaluation` decodes JavaScript directly into a Codable model.
- `AsyncHostAPI` exposes an actor through a typed async Swift binding.
- `ModuleEmbedding` combines a Swift-defined module and an ES source module.
- `RuntimeTemplates` creates and prewarms independently isolated runtimes.
- `TypeScriptWorkspace` derives schemas with `@JavaScriptExport` and writes a
  managed editor workspace.

The separate `IntegrationTests/PlatformSmoke` package combines the portable
features used by the release-blocking platform matrix.
