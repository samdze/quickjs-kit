/// A transactional description of Swift members exported to JavaScript.
///
/// Configure exports inside ``JavaScriptRuntime/export(_:as:documentation:_:)``
/// and ``JavaScriptRuntime/defineModule(_:documentation:_:)``, or reuse the
/// same definitions in ``JavaScriptRuntimeTemplate``. The destination controls
/// property attributes and encodes every snapshot value into its own heap.
public struct JavaScriptExportBuilder {
    internal var members: [JavaScriptExportMemberDefinition] = []

    internal init() {}

    /// Publishes a macro-generated Swift value type from a Swift module.
    public mutating func type<Value>(_ type: Value.Type)
    where Value: JavaScriptValueTypeProviding {
        let definition = Value.javaScriptValueTypeDefinition
        members.append(
            JavaScriptExportMemberDefinition(
                name: definition.name,
                documentation: definition.documentation,
                sourceLocation: definition.sourceLocation,
                validationMessage: nil,
                storage: .type(
                    definition.erase(
                        schema: collectedTypeScriptSchema(from: Value.self)
                    )
                )
            )
        )
    }

    /// Publishes a macro-generated live Swift host type from a Swift module.
    public mutating func type<Root>(_ type: Root.Type)
    where Root: JavaScriptHostTypeProviding {
        let definition = Root.javaScriptHostTypeDefinition
        members.append(
            JavaScriptExportMemberDefinition(
                name: definition.name,
                documentation: definition.documentation,
                sourceLocation: definition.sourceLocation,
                validationMessage: nil,
                storage: .type(.host(definition.erase()))
            )
        )
    }

    /// Adds a synchronous typed method.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        appendSynchronousFunction(
            name,
            options: options,
            resultShape: bindingTypeShape(for: Result.self),
            isThrowing: false,
            body: body
        ) { engine, result in
            try engine.encode(
                result,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
        }
    }

    /// Adds a throwing synchronous typed method.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        appendSynchronousFunction(
            name,
            options: options,
            resultShape: bindingTypeShape(for: Result.self),
            isThrowing: true,
            body: body
        ) { engine, result in
            try engine.encode(
                result,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
        }
    }

    /// Adds an asynchronous typed method backed by a native promise.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        appendAsynchronousFunction(
            name,
            options: options,
            resultShape: bindingTypeShape(for: Result.self),
            isThrowing: false,
            body: body
        ) { result in
            BindingResult { engine in
                try engine.encode(
                    result,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
            }
        }
    }

    /// Adds an asynchronous throwing typed method backed by a native promise.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        appendAsynchronousFunction(
            name,
            options: options,
            resultShape: bindingTypeShape(for: Result.self),
            isThrowing: true,
            body: body
        ) { result in
            BindingResult { engine in
                try engine.encode(
                    result,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
            }
        }
    }

    /// Adds a synchronous typed method returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendSynchronousFunction(
            name,
            options: options,
            resultShape: .void,
            isThrowing: false,
            body: body
        ) { engine, _ in
            ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        }
    }

    /// Adds a throwing typed method returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendSynchronousFunction(
            name,
            options: options,
            resultShape: .void,
            isThrowing: true,
            body: body
        ) { engine, _ in
            ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        }
    }

    /// Adds an asynchronous typed method fulfilling with JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendAsynchronousFunction(
            name,
            options: options,
            resultShape: .void,
            isThrowing: false,
            body: body
        ) { _ in
            BindingResult { engine in
                ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            }
        }
    }

    /// Adds an asynchronous throwing method fulfilling with `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendAsynchronousFunction(
            name,
            options: options,
            resultShape: .void,
            isThrowing: true,
            body: body
        ) { _ in
            BindingResult { engine in
                ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            }
        }
    }

    /// Adds a snapshot value.
    ///
    /// Object and module destinations publish it as read-only and enumerable.
    /// A template global uses ordinary writable global-property semantics.
    public mutating func value<Value: Encodable & Sendable>(
        _ value: Value,
        as name: String,
        documentation: TypeScriptDocumentation? = nil
    ) {
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: exportMemberValidationMessage(name)
                    ?? TypeScriptDocumentationValidation.message(for: documentation),
                storage: .value(
                    type: bindingTypeShape(for: Value.self),
                    encode: { engine in
                        try engine.encode(
                            value,
                            maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                        )
                    }
                )
            )
        )
    }

    /// Adds a read-only enumerable same-runtime JavaScript value.
    public mutating func value(
        _ value: JavaScriptValue,
        as name: String,
        documentation: TypeScriptDocumentation? = nil
    ) {
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: exportMemberValidationMessage(name)
                    ?? TypeScriptDocumentationValidation.message(for: documentation),
                storage: .liveValue(type: bindingTypeShape(for: value), value: value)
            )
        )
    }

    /// Adds a live read-only property.
    public mutating func property<Value: Encodable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        get: @escaping @Sendable () -> Value
    ) {
        var getter = JavaScriptExportBuilder()
        getter.function("get \(name)", get)
        guard case let .function(getterDefinition) = getter.members[0].storage else {
            return
        }
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: exportMemberValidationMessage(name)
                    ?? TypeScriptDocumentationValidation.message(for: documentation),
                storage: .property(
                    type: bindingTypeShape(for: Value.self),
                    getter: getterDefinition,
                    setter: nil
                )
            )
        )
    }

    /// Adds a live readable and writable property.
    public mutating func property<Value: Codable & Sendable>(
        _ name: String,
        documentation: TypeScriptDocumentation? = nil,
        get: @escaping @Sendable () -> Value,
        set: @escaping @Sendable (Value) -> Void
    ) {
        var getter = JavaScriptExportBuilder()
        getter.function("get \(name)", get)
        var setter = JavaScriptExportBuilder()
        setter.function("set \(name)", set)
        guard case let .function(getterDefinition) = getter.members[0].storage,
              case let .function(setterDefinition) = setter.members[0].storage else {
            return
        }
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: exportMemberValidationMessage(name)
                    ?? TypeScriptDocumentationValidation.message(for: documentation),
                storage: .property(
                    type: bindingTypeShape(for: Value.self),
                    getter: getterDefinition,
                    setter: setterDefinition
                )
            )
        )
    }

    private mutating func appendSynchronousFunction<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions,
        resultShape: BindingTypeShape,
        isThrowing: Bool,
        body: @escaping @Sendable (repeat each Argument) throws -> Result,
        encode: @escaping @Sendable (
            QuickJSEngine,
            Result
        ) throws -> ManagedQuickJSValue
    ) where repeat each Argument: Decodable & Sendable,
            Result: Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: resultShape,
            isAsync: false,
            isThrowing: isThrowing
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .synchronous(
                try encode(engine, body(repeat each decoded))
            )
        }
    }

    private mutating func appendAsynchronousFunction<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions,
        resultShape: BindingTypeShape,
        isThrowing: Bool,
        body: @escaping @Sendable (repeat each Argument) async throws -> Result,
        encode: @escaping @Sendable (Result) -> BindingResult
    ) where repeat each Argument: Decodable & Sendable,
            Result: Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: resultShape,
            isAsync: true,
            isThrowing: isThrowing
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { _ in
                do {
                    return .success(encode(try await body(repeat each decoded)))
                } catch {
                    return .failure(error)
                }
            }
        }
    }

    private mutating func appendFunction(
        _ name: String,
        options: JavaScriptFunctionOptions,
        parameterShapes: [BindingTypeShape],
        resultShape: BindingTypeShape,
        isAsync: Bool,
        isThrowing: Bool,
        invocation: @escaping @Sendable (
            QuickJSEngine,
            [ManagedQuickJSValue]
        ) throws -> BindingInvocation
    ) {
        let parameters = BindingValidation.parameterNames(
            options.parameterNames,
            arity: parameterShapes.count
        )
        let names = parameters.names
        let validationMessage = parameters.message
            ?? exportMemberValidationMessage(name)
            ?? options.parameterSourceLocations.keys.sorted().first(where: {
                !names.contains($0)
            }).map {
                "A source location was provided for unknown parameter '\($0)'."
            }
            ?? TypeScriptDocumentationValidation.message(
                for: options.documentation,
                parameterNames: names
            )
        let draft = BindingDraft(
            name: name,
            parameters: zip(names, parameterShapes).map {
                BindingParameterDescription(
                    name: $0,
                    type: $1,
                    sourceLocation: options.parameterSourceLocations[$0]
                )
            },
            result: resultShape,
            effects: .init(isAsync: isAsync, isThrowing: isThrowing),
            documentation: options.documentation,
            sourceLocation: options.sourceLocation
        )
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: nil,
                validationMessage: validationMessage,
                storage: .function(
                    BindingDefinition(draft: draft, invoke: invocation)
                )
            )
        )
    }

    private func exportMemberValidationMessage(_ name: String) -> String? {
        BindingValidation.nameMessage(name, role: "Export member names")
    }
}

internal struct JavaScriptExportMemberDefinition: Sendable {
    internal enum Storage: Sendable {
        case function(BindingDefinition)
        case runtimeFunction(RuntimeLocalFunctionDefinition)
        case property(
            type: BindingTypeShape,
            getter: BindingDefinition,
            setter: BindingDefinition?
        )
        case runtimeProperty(
            type: BindingTypeShape,
            getter: RuntimeLocalFunctionDefinition,
            setter: RuntimeLocalFunctionDefinition?
        )
        case value(
            type: BindingTypeShape,
            encode: @Sendable (QuickJSEngine) throws -> ManagedQuickJSValue
        )
        case liveValue(type: BindingTypeShape, value: JavaScriptValue)
        case type(AnyJavaScriptTypeDefinition)
        case materializedHostType(
            AnyJavaScriptHostTypeDefinition,
            identifier: Int32,
            instanceMembers: [JavaScriptExportMemberDefinition]
        )
    }

    internal let name: String
    internal let documentation: TypeScriptDocumentation?
    internal let sourceLocation: TypeScriptSourceLocation?
    internal let validationMessage: String?
    internal let storage: Storage

    internal init(
        name: String,
        documentation: TypeScriptDocumentation?,
        sourceLocation: TypeScriptSourceLocation? = nil,
        validationMessage: String?,
        storage: Storage
    ) {
        self.name = name
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.validationMessage = validationMessage
        self.storage = storage
    }
}

extension JavaScriptRuntime {
    /// Exposes a macro-generated object definition.
    ///
    /// The supplied root must be `Sendable` because it originates outside this
    /// runtime actor. Runtime-local non-`Sendable` roots are supported only by
    /// `RuntimeInstance` factories.
    @discardableResult
    public func export<Root: JavaScriptExportProviding & Sendable>(
        _ root: Root,
        as name: String,
        documentation: TypeScriptDocumentation? = nil
    ) async throws -> JavaScriptBinding {
        if let message = BindingValidation.nameMessage(name, role: "Export names") {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        let rootIdentifier = try retainRuntimeRoot(root)
        do {
            let members = try await Root.javaScriptExportDefinition.materialize(
                on: self,
                rootIdentifier: rootIdentifier
            )
            return try engine.withEngineEntry {
                let (identifier, rawValue) = try engine.registerExport(
                    named: name,
                    documentation: documentation ?? Root.javaScriptExportDocumentation,
                    root: nil,
                    runtimeRootIdentifier: rootIdentifier,
                    members: members,
                    settle: bindingSettlement
                )
                return JavaScriptBinding(
                    name: name,
                    value: makeValue(rawValue),
                    reference: JavaScriptBindingReference(
                        runtime: self,
                        identifier: identifier
                    )
                )
            }
        } catch {
            releaseRuntimeRoot(rootIdentifier)
            throw error
        }
    }

    /// Exposes explicitly configured methods and snapshot values on one object.
    ///
    /// The operation is transactional: the global object is unchanged if any
    /// member fails validation or encoding.
    ///
    /// - Parameters:
    ///   - root: The actor or object retained by the export binding.
    ///   - name: The property installed on the JavaScript global object.
    ///   - documentation: Structured TSDoc for the exported object container.
    ///   - configure: A closure that explicitly selects exported members.
    /// - Returns: A handle controlling the export's runtime lifecycle.
    /// - Throws: ``JavaScriptError`` when validation, encoding, or publication
    ///   fails. Nothing is published on failure.
    @discardableResult
    public func export<Root: AnyObject & Sendable>(
        _ root: Root,
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        _ configure: @Sendable (Root, inout JavaScriptExportBuilder) -> Void
    ) throws -> JavaScriptBinding {
        if let message = BindingValidation.nameMessage(name, role: "Export names") {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        if let message = TypeScriptDocumentationValidation.message(for: documentation) {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        var builder = JavaScriptExportBuilder()
        configure(root, &builder)
        if let message = builder.members.lazy.compactMap(\.validationMessage).first {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        try validateLiveValues(in: builder.members)
        return try engine.withEngineEntry() {
            let (identifier, rawValue) = try engine.registerExport(
                named: name,
                documentation: documentation,
                root: root,
                members: builder.members,
                settle: bindingSettlement
            )
            return JavaScriptBinding(
                name: name,
                value: makeValue(rawValue),
                reference: JavaScriptBindingReference(runtime: self, identifier: identifier)
            )
        }
    }

    internal var bindingSettlement: BindingSettlement {
        { [weak self] identifier, completion in
            await self?.settleSwiftPromise(identifier, completion: completion)
        }
    }

    internal func validateLiveValues(
        in members: [JavaScriptExportMemberDefinition]
    ) throws {
        for member in members {
            if case let .liveValue(_, value) = member.storage {
                try validate(value)
            }
        }
    }
}
