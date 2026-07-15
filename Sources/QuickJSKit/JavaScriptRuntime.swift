/// An isolated JavaScript engine and its associated object heap.
///
/// Every QuickJS operation is serialized by this actor. Independent runtimes
/// may execute concurrently, while live values always route operations back to
/// the runtime that owns them.
public actor JavaScriptRuntime {
    /// Resource limits applied when a runtime is created.
    public struct Configuration: Sendable, Hashable {
        /// The maximum number of bytes the JavaScript heap may allocate.
        public var memoryLimit: UInt64?

        /// The maximum number of bytes available to the JavaScript stack.
        public var maximumStackSize: UInt64?

        /// Creates a runtime configuration.
        public init(
            memoryLimit: UInt64? = nil,
            maximumStackSize: UInt64? = nil
        ) {
            self.memoryLimit = memoryLimit
            self.maximumStackSize = maximumStackSize
        }
    }

    /// The immutable configuration used to create this runtime.
    public nonisolated let configuration: Configuration

    private let engine: QuickJSEngine

    /// Creates an isolated JavaScript runtime.
    public init(configuration: Configuration = Configuration()) throws {
        self.configuration = configuration
        self.engine = try QuickJSEngine(configuration: configuration)
    }

    /// A codec that directly creates JavaScript values in this runtime.
    public nonisolated var encoder: JavaScriptEncoder {
        JavaScriptEncoder(runtime: self)
    }

    /// A codec that directly reads JavaScript values from this runtime.
    public nonisolated var decoder: JavaScriptDecoder {
        JavaScriptDecoder(runtime: self)
    }

    /// A live handle to this runtime's global object.
    public nonisolated var global: JavaScriptObject {
        JavaScriptObject(
            reference: JavaScriptReference(
                runtime: self,
                identifier: 0,
                kind: .object,
                releasesOnDeinit: false
            )
        )
    }

    /// Evaluates a JavaScript script and returns its general value.
    public func evaluate(
        _ source: String,
        sourceURL: String = "<eval>"
    ) throws -> JavaScriptValue {
        try makeValue(engine.evaluate(source, sourceURL: sourceURL))
    }

    /// Evaluates JavaScript and directly decodes its result as a Swift type.
    ///
    /// The result type may be inferred from context or selected with `as:`.
    public func evaluate<T: Decodable & Sendable>(
        _ source: String,
        as type: T.Type = T.self,
        sourceURL: String = "<eval>"
    ) throws -> T {
        let raw = try engine.evaluateRaw(source, sourceURL: sourceURL)
        return try engine.decode(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        )
    }

    internal func releaseReference(_ identifier: UInt64) {
        engine.prepareForEngineCall()
        engine.releaseReference(identifier)
    }

    internal var retainedReferenceCountForTesting: Int {
        engine.retainedReferenceCount
    }

    internal func encode<T: Encodable & Sendable>(
        _ value: T,
        maximumNestingDepth: Int
    ) throws -> JavaScriptValue {
        let raw = try engine.encode(value, maximumNestingDepth: maximumNestingDepth)
        return try makeValue(engine.decodeUntyped(raw))
    }

    internal func decode<T: Decodable & Sendable>(
        _ type: T.Type,
        from value: JavaScriptValue,
        maximumNestingDepth: Int
    ) throws -> T {
        try validate(value)
        let raw = try engine.materialize(value)
        return try engine.decode(
            type,
            from: raw,
            maximumNestingDepth: maximumNestingDepth
        )
    }

    internal func value(
        forProperty name: String,
        on reference: JavaScriptReference
    ) throws -> JavaScriptValue {
        try validate(reference)
        return try makeValue(
            engine.propertyValue(named: name, on: reference.identifier)
        )
    }

    internal func value<T: Decodable & Sendable>(
        forProperty name: String,
        on reference: JavaScriptReference,
        as type: T.Type
    ) throws -> T {
        try validate(reference)
        let raw = try engine.rawPropertyValue(named: name, on: reference.identifier)
        return try engine.decode(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        )
    }

    internal func set<T: Encodable & Sendable>(
        _ value: T,
        forProperty name: String,
        on reference: JavaScriptReference
    ) throws {
        try validate(reference)
        let raw = try engine.encode(
            value,
            maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
        )
        try engine.setProperty(named: name, on: reference.identifier, to: raw)
    }

    internal func set(
        _ value: JavaScriptValue,
        forProperty name: String,
        on reference: JavaScriptReference
    ) throws {
        try validate(reference)
        try validate(value)
        let raw = try engine.materialize(value)
        try engine.setProperty(named: name, on: reference.identifier, to: raw)
    }

    internal func hasProperty(_ name: String, on reference: JavaScriptReference) throws -> Bool {
        try validate(reference)
        return try engine.hasProperty(named: name, on: reference.identifier)
    }

    internal func deleteProperty(
        _ name: String,
        on reference: JavaScriptReference
    ) throws -> Bool {
        try validate(reference)
        return try engine.deleteProperty(named: name, on: reference.identifier)
    }

    internal func propertyNames(of reference: JavaScriptReference) throws -> [String] {
        try validate(reference)
        return try engine.ownEnumerablePropertyNames(of: reference.identifier)
    }

    internal func arrayCount(_ reference: JavaScriptReference) throws -> Int {
        try validate(reference, expected: .array)
        return try engine.arrayLength(reference.identifier)
    }

    internal func value(at index: Int, in reference: JavaScriptReference) throws -> JavaScriptValue {
        try validate(reference, expected: .array)
        return try makeValue(engine.arrayValue(at: index, in: reference.identifier))
    }

    internal func value<T: Decodable & Sendable>(
        at index: Int,
        in reference: JavaScriptReference,
        as type: T.Type
    ) throws -> T {
        try validate(reference, expected: .array)
        let raw = try engine.rawArrayValue(at: index, in: reference.identifier)
        return try engine.decode(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        )
    }

    internal func set<T: Encodable & Sendable>(
        _ value: T,
        at index: Int,
        in reference: JavaScriptReference
    ) throws {
        try validate(reference, expected: .array)
        let raw = try engine.encode(
            value,
            maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
        )
        try engine.setArrayValue(raw, at: index, in: reference.identifier)
    }

    internal func set(
        _ value: JavaScriptValue,
        at index: Int,
        in reference: JavaScriptReference
    ) throws {
        try validate(reference, expected: .array)
        try validate(value)
        let raw = try engine.materialize(value)
        try engine.setArrayValue(raw, at: index, in: reference.identifier)
    }

    internal func append<T: Encodable & Sendable>(
        _ value: T,
        to reference: JavaScriptReference
    ) throws {
        let index = try arrayCount(reference)
        try set(value, at: index, in: reference)
    }

    internal func append(_ value: JavaScriptValue, to reference: JavaScriptReference) throws {
        let index = try arrayCount(reference)
        try set(value, at: index, in: reference)
    }

    internal func call<each Argument>(
        _ function: JavaScriptReference,
        arguments: repeat each Argument
    ) throws -> JavaScriptValue
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable {
        try validate(function, expected: .function)
        let arguments = try encodeArguments(repeat each arguments)
        return try makeValue(
            engine.call(
                function.identifier,
                receiverIdentifier: nil,
                arguments: arguments
            )
        )
    }

    internal func call<each Argument, Result>(
        _ function: JavaScriptReference,
        arguments: repeat each Argument,
        as type: Result.Type
    ) throws -> Result
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable,
          Result: Decodable & Sendable {
        try validate(function, expected: .function)
        let arguments = try encodeArguments(repeat each arguments)
        let raw = try engine.callRaw(
            function.identifier,
            receiverIdentifier: nil,
            arguments: arguments
        )
        return try engine.decode(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        )
    }

    internal func call<each Argument, Result>(
        _ function: JavaScriptReference,
        on receiver: JavaScriptReference,
        arguments: repeat each Argument,
        as type: Result.Type
    ) throws -> Result
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable,
          Result: Decodable & Sendable {
        try validate(function, expected: .function)
        try validate(receiver)
        let arguments = try encodeArguments(repeat each arguments)
        let raw = try engine.callRaw(
            function.identifier,
            receiverIdentifier: receiver.identifier,
            arguments: arguments
        )
        return try engine.decode(
            type,
            from: raw,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        )
    }

    internal func call(
        _ function: JavaScriptReference,
        arguments: [JavaScriptValue],
        receiver: JavaScriptReference?
    ) throws -> JavaScriptValue {
        try validate(function, expected: .function)
        if let receiver { try validate(receiver) }
        for argument in arguments { try validate(argument) }
        let rawArguments = try arguments.map(engine.materialize)
        return try makeValue(
            engine.call(
                function.identifier,
                receiverIdentifier: receiver?.identifier,
                arguments: rawArguments
            )
        )
    }

    private func encodeArguments<each Argument>(
        _ arguments: repeat each Argument
    ) throws -> [ManagedQuickJSValue]
    where repeat each Argument: Encodable,
          repeat each Argument: Sendable {
        var result: [ManagedQuickJSValue] = []
        for argument in repeat each arguments {
            result.append(
                try engine.encode(
                    argument,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
            )
        }
        return result
    }

    private func makeValue(_ value: EngineJavaScriptValue) -> JavaScriptValue {
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

    private func validate(_ reference: JavaScriptReference) throws {
        guard reference.runtimeIdentifier == ObjectIdentifier(self) else {
            throw JavaScriptError(
                kind: .runtime,
                message: "JavaScript values cannot cross runtime boundaries."
            )
        }
    }

    private func validate(
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

    private func validate(_ value: JavaScriptValue) throws {
        guard case let .reference(reference) = value.storage else { return }
        try validate(reference)
    }
}
