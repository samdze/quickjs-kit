extension JavaScriptRuntime {
    /// Publishes a macro-generated struct or enum as a permanent global
    /// JavaScript type.
    ///
    /// Type registrations cannot be replaced or removed because constructors,
    /// prototypes, and dependent declarations remain valid for the runtime
    /// lifetime.
    public func registerType<Value>(_ type: Value.Type) throws
    where Value: JavaScriptValueTypeProviding {
        let definition = Value.javaScriptValueTypeDefinition.erase(
            schema: collectedTypeScriptSchema(from: Value.self)
        )
        guard case let .value(value) = definition else { return }
        try JavaScriptTypeLocation.global.validate(
            scope: value.schema.scope,
            typeName: value.name
        )
        try engine.withEngineEntry {
            try engine.publishGlobalValueType(value)
        }
    }

    /// Publishes a macro-generated final class or actor as a permanent global
    /// JavaScript host type.
    public func registerType<Root>(_ type: Root.Type) async throws
    where Root: JavaScriptHostTypeProviding {
        let erased = Root.javaScriptHostTypeDefinition.erase()
        let identifier = try engine.withEngineEntry(drainJobs: false) {
            try engine.reserveHostType(erased, location: .global)
        }
        do {
            let members = try await erased.materializeInstanceMembers(self, identifier)
            try engine.withEngineEntry {
                let function = try engine.registerHostType(
                    erased,
                    identifier: identifier,
                    location: .global,
                    instanceMembers: members,
                    settle: bindingSettlement
                )
                try engine.publishGlobalHostType(erased, function: function)
            }
        } catch {
            engine.cancelHostTypeReservation(erased)
            throw error
        }
    }
}
