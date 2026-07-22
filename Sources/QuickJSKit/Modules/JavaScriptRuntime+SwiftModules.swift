extension JavaScriptRuntime {
    /// Defines a method-only Swift module from a macro-generated export.
    public func defineModule<Root: JavaScriptExportProviding & Sendable>(
        _ specifier: String,
        exporting root: Root,
        documentation: TypeScriptDocumentation? = nil
    ) async throws {
        let rootIdentifier = try retainRuntimeRoot(root)
        do {
            let members = try await Root.javaScriptExportDefinition.materialize(
                on: self,
                rootIdentifier: rootIdentifier
            )
            try engine.withEngineEntry {
                try engine.registerSwiftModule(
                    specifier: specifier,
                    documentation: documentation ?? Root.javaScriptExportDocumentation,
                    members: members,
                    settle: bindingSettlement
                )
            }
        } catch {
            releaseRuntimeRoot(rootIdentifier)
            throw error
        }
    }

    /// Defines a runtime-lifetime ES module backed by Swift values and functions.
    ///
    /// Definition is transactional: validation and value encoding finish
    /// before the module becomes importable.
    ///
    /// - Parameters:
    ///   - specifier: The canonical module specifier.
    ///   - documentation: Structured TSDoc for the module container.
    ///   - configure: A closure that declares immutable exports.
    /// - Throws: ``JavaScriptError`` when validation, encoding, or publication
    ///   fails. Nothing is published on failure.
    public func defineModule(
        _ specifier: String,
        documentation: TypeScriptDocumentation? = nil,
        _ configure: @Sendable (inout JavaScriptExportBuilder) -> Void
    ) throws {
        if let message = TypeScriptDocumentationValidation.message(for: documentation) {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        var builder = JavaScriptExportBuilder()
        configure(&builder)
        if let message = builder.members.lazy.compactMap(\.validationMessage).first {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        try validateLiveValues(in: builder.members)
        try engine.withEngineEntry() {
            try engine.registerSwiftModule(
                specifier: specifier,
                documentation: documentation,
                members: builder.members,
                settle: bindingSettlement
            )
        }
    }
}
