extension JavaScriptRuntime {
    /// Defines a runtime-lifetime ES module backed by Swift values and functions.
    ///
    /// Definition is transactional: validation and value encoding finish
    /// before the module becomes importable.
    public func defineModule(
        _ specifier: String,
        _ configure: @Sendable (inout JavaScriptExportBuilder) -> Void
    ) throws {
        var builder = JavaScriptExportBuilder()
        configure(&builder)
        if let message = builder.members.lazy.compactMap(\.validationMessage).first {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        try validateLiveValues(in: builder.members)
        try engine.withEngineEntry() {
            try engine.registerSwiftModule(
                specifier: specifier,
                members: builder.members,
                settle: bindingSettlement
            )
        }
    }
}
