# QuickJSKit Examples

This standalone Swift package demonstrates complete consumer workflows.

```sh
swift run --package-path Examples QuickJSKitExamples
swift run --package-path Examples QuickJSKitExamples evaluation
swift run --package-path Examples QuickJSKitExamples binding
swift run --package-path Examples QuickJSKitExamples module
swift run --package-path Examples QuickJSKitExamples template
swift run --package-path Examples QuickJSKitExamples tooling
```

- `evaluation` decodes JavaScript directly into a Codable model.
- `binding` exposes an actor through a typed async Swift binding.
- `module` combines a Swift-defined module and an ES source module.
- `template` creates and prewarms independently isolated runtimes.
- `tooling` derives schemas with `@JavaScriptExport` and writes a managed editor
  workspace.

The separate `IntegrationTests/PlatformSmoke` package combines the portable
features used by the release-blocking platform matrix.
