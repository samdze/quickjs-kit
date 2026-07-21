extension JavaScriptRuntime {
    internal func encode<T: Encodable & Sendable>(
        _ value: T,
        maximumNestingDepth: Int
    ) throws -> JavaScriptValue {
        try engine.withEngineEntry() {
            let raw = try engine.encode(value, maximumNestingDepth: maximumNestingDepth)
            return try makeValue(engine.decodeUntyped(raw))
        }
    }

    internal func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from value: JavaScriptValue,
        maximumNestingDepth: Int
    ) async throws -> T {
        try await decodeRoot(
            type,
            maximumNestingDepth: maximumNestingDepth
        ) {
            try validate(value)
            return try engine.materialize(value)
        }
    }

    internal func value(
        forProperty name: String,
        on reference: JavaScriptReference
    ) throws -> JavaScriptValue {
        try engine.withEngineEntry() {
            try validate(reference)
            return try makeValue(
                engine.propertyValue(named: name, on: reference.identifier)
            )
        }
    }

    internal func value<T: Decodable & Sendable>(
        forProperty name: String,
        on reference: JavaScriptReference,
        as type: T.Type
    ) async throws -> T {
        try await decodeRoot(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        ) {
            try validate(reference)
            return try engine.rawPropertyValue(named: name, on: reference.identifier)
        }
    }

    internal func set<T: Encodable & Sendable>(
        _ value: T,
        forProperty name: String,
        on reference: JavaScriptReference
    ) throws {
        try engine.withEngineEntry() {
            try validate(reference)
            let raw = try engine.encode(
                value,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
            try engine.setProperty(named: name, on: reference.identifier, to: raw)
        }
    }

    internal func set(
        _ value: JavaScriptValue,
        forProperty name: String,
        on reference: JavaScriptReference
    ) throws {
        try engine.withEngineEntry() {
            try validate(reference)
            try validate(value)
            let raw = try engine.materialize(value)
            try engine.setProperty(named: name, on: reference.identifier, to: raw)
        }
    }

    internal func hasProperty(_ name: String, on reference: JavaScriptReference) throws -> Bool {
        try engine.withEngineEntry() {
            try validate(reference)
            return try engine.hasProperty(named: name, on: reference.identifier)
        }
    }

    internal func deleteProperty(
        _ name: String,
        on reference: JavaScriptReference
    ) throws -> Bool {
        try engine.withEngineEntry() {
            try validate(reference)
            return try engine.deleteProperty(named: name, on: reference.identifier)
        }
    }

    internal func propertyNames(of reference: JavaScriptReference) throws -> [String] {
        try engine.withEngineEntry() {
            try validate(reference)
            return try engine.ownEnumerablePropertyNames(of: reference.identifier)
        }
    }

    internal func arrayCount(_ reference: JavaScriptReference) throws -> Int {
        try engine.withEngineEntry() {
            try validate(reference, expected: .array)
            return try engine.arrayLength(reference.identifier)
        }
    }

    internal func value(at index: Int, in reference: JavaScriptReference) throws -> JavaScriptValue {
        try engine.withEngineEntry() {
            try validate(reference, expected: .array)
            return try makeValue(engine.arrayValue(at: index, in: reference.identifier))
        }
    }

    internal func value<T: Decodable & Sendable>(
        at index: Int,
        in reference: JavaScriptReference,
        as type: T.Type
    ) async throws -> T {
        try await decodeRoot(
            type,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        ) {
            try validate(reference, expected: .array)
            return try engine.rawArrayValue(at: index, in: reference.identifier)
        }
    }

    internal func set<T: Encodable & Sendable>(
        _ value: T,
        at index: Int,
        in reference: JavaScriptReference
    ) throws {
        try engine.withEngineEntry() {
            try validate(reference, expected: .array)
            let raw = try engine.encode(
                value,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
            try engine.setArrayValue(raw, at: index, in: reference.identifier)
        }
    }

    internal func set(
        _ value: JavaScriptValue,
        at index: Int,
        in reference: JavaScriptReference
    ) throws {
        try engine.withEngineEntry() {
            try validate(reference, expected: .array)
            try validate(value)
            let raw = try engine.materialize(value)
            try engine.setArrayValue(raw, at: index, in: reference.identifier)
        }
    }

    internal func append<T: Encodable & Sendable>(
        _ value: T,
        to reference: JavaScriptReference
    ) throws {
        try engine.withEngineEntry() {
            try validate(reference, expected: .array)
            let index = try engine.arrayLength(reference.identifier)
            let raw = try engine.encode(
                value,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
            try engine.setArrayValue(raw, at: index, in: reference.identifier)
        }
    }

    internal func append(_ value: JavaScriptValue, to reference: JavaScriptReference) throws {
        try engine.withEngineEntry() {
            try validate(reference, expected: .array)
            try validate(value)
            let index = try engine.arrayLength(reference.identifier)
            let raw = try engine.materialize(value)
            try engine.setArrayValue(raw, at: index, in: reference.identifier)
        }
    }

    nonisolated internal func makeValue(_ value: EngineJavaScriptValue) -> JavaScriptValue {
        switch value {
        case let .detached(value):
            value
        case let .reference(record):
            JavaScriptValue(
                reference: JavaScriptReference(
                    runtime: self,
                    identifier: record.identifier,
                    kind: record.kind
                )
            )
        }
    }

    internal func validate(_ reference: JavaScriptReference) throws {
        guard reference.runtimeIdentifier == ObjectIdentifier(self) else {
            throw JavaScriptError(
                kind: .runtime,
                message: "JavaScript values cannot cross runtime boundaries."
            )
        }
    }

    internal func validate(
        _ reference: JavaScriptReference,
        expected kind: JavaScriptReferenceKind
    ) throws {
        try validate(reference)
        guard reference.kind == kind else {
            throw JavaScriptError(
                kind: .conversion,
                message: "The JavaScript value has the wrong live-value kind."
            )
        }
    }

    internal func validate(_ value: JavaScriptValue) throws {
        guard case let .reference(reference) = value.storage else { return }
        try validate(reference)
    }
}
