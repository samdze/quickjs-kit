/// Describes members backed by a Swift root created for one runtime.
///
/// The root is supplied to Swift closures as their first argument but is not
/// part of the JavaScript signature or generated TypeScript declaration.
public struct JavaScriptInstanceExportBuilder<Root: AnyObject & Sendable> {
    internal var members: [RuntimeInstanceMemberDefinition<Root>] = []

    internal init() {}

    /// Adds a synchronous typed function.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) -> Result
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

    /// Adds a throwing synchronous typed function.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result
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

    /// Adds an asynchronous typed function backed by a native promise.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async -> Result
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

    /// Adds an asynchronous throwing typed function backed by a native promise.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Result
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

    /// Adds a synchronous function returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) -> Void
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

    /// Adds a throwing synchronous function returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Void
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

    /// Adds an asynchronous function fulfilling with JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async -> Void
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

    /// Adds an asynchronous throwing function fulfilling with `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Void
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

    /// Adds a snapshot value produced from the per-runtime root.
    ///
    /// The producer runs once during runtime creation. Its value is encoded
    /// directly into that runtime's QuickJS heap.
    public mutating func value<Value: Encodable & Sendable>(
        as name: String,
        documentation: TypeScriptDocumentation? = nil,
        _ produce: @escaping @Sendable (Root) async throws -> Value
    ) {
        let type = bindingTypeShape(for: Value.self)
        members.append(
            RuntimeInstanceMemberDefinition(
                name: name,
                validationMessage: BindingValidation.nameMessage(
                    name,
                    role: "Export member names"
                ) ?? TypeScriptDocumentationValidation.message(for: documentation),
                environmentDescription: .value(
                    EnvironmentValueDescription(
                        name: name,
                        type: type,
                        documentation: documentation,
                        isReadOnly: true
                    )
                ),
                materialize: { root in
                    let value = try await produce(root)
                    return JavaScriptExportMemberDefinition(
                        name: name,
                        documentation: documentation,
                        validationMessage: nil,
                        storage: .value(
                            type: type,
                            encode: { engine in
                                try engine.encode(
                                    value,
                                    maximumNestingDepth:
                                        JavaScriptEncoder.defaultMaximumNestingDepth
                                )
                            }
                        )
                    )
                }
            )
        )
    }

    private mutating func appendSynchronousFunction<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions,
        resultShape: BindingTypeShape,
        isThrowing: Bool,
        body: @escaping @Sendable (Root, repeat each Argument) throws -> Result,
        encode: @escaping @Sendable (
            QuickJSEngine,
            Result
        ) throws -> ManagedQuickJSValue
    ) where repeat each Argument: Decodable & Sendable,
            Result: Sendable {
        let draft = makeDraft(
            name: name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: resultShape,
            isAsync: false,
            isThrowing: isThrowing
        )
        appendFunction(draft) { root in
            BindingDefinition(draft: draft.value) { engine, arguments in
                let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
                let decoded: (repeat each Argument) =
                    (repeat try decoder.next((each Argument).self))
                return .synchronous(
                    try encode(engine, body(root, repeat each decoded))
                )
            }
        }
    }

    private mutating func appendAsynchronousFunction<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions,
        resultShape: BindingTypeShape,
        isThrowing: Bool,
        body: @escaping @Sendable (Root, repeat each Argument) async throws -> Result,
        encode: @escaping @Sendable (Result) -> BindingResult
    ) where repeat each Argument: Decodable & Sendable,
            Result: Sendable {
        let draft = makeDraft(
            name: name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: resultShape,
            isAsync: true,
            isThrowing: isThrowing
        )
        appendFunction(draft) { root in
            BindingDefinition(draft: draft.value) { engine, arguments in
                let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
                let decoded: (repeat each Argument) =
                    (repeat try decoder.next((each Argument).self))
                return .asynchronous {
                    do {
                        return .success(encode(try await body(root, repeat each decoded)))
                    } catch {
                        return .failure(error)
                    }
                }
            }
        }
    }

    private mutating func appendFunction(
        _ draft: InstanceBindingDraft,
        materialize: @escaping @Sendable (Root) -> BindingDefinition
    ) {
        members.append(
            RuntimeInstanceMemberDefinition(
                name: draft.value.name,
                validationMessage: draft.validationMessage,
                environmentDescription: .function(
                    EnvironmentFunctionDescription(draft.value)
                ),
                materialize: { root in
                    JavaScriptExportMemberDefinition(
                        name: draft.value.name,
                        documentation: nil,
                        validationMessage: nil,
                        storage: .function(materialize(root))
                    )
                }
            )
        )
    }

    private func makeDraft(
        name: String,
        options: JavaScriptFunctionOptions,
        parameterShapes: [BindingTypeShape],
        resultShape: BindingTypeShape,
        isAsync: Bool,
        isThrowing: Bool
    ) -> InstanceBindingDraft {
        let parameters = BindingValidation.parameterNames(
            options.parameterNames,
            arity: parameterShapes.count
        )
        let draft = BindingDraft(
            name: name,
            parameters: zip(parameters.names, parameterShapes).map {
                BindingParameterDescription(name: $0, type: $1)
            },
            result: resultShape,
            effects: .init(isAsync: isAsync, isThrowing: isThrowing),
            documentation: options.documentation
        )
        return InstanceBindingDraft(
            value: draft,
            validationMessage: parameters.message
                ?? BindingValidation.nameMessage(name, role: "Export member names")
                ?? TypeScriptDocumentationValidation.message(
                    for: options.documentation,
                    parameterNames: parameters.names
                )
        )
    }
}

private struct InstanceBindingDraft: Sendable {
    let value: BindingDraft
    let validationMessage: String?
}

internal struct RuntimeInstanceMemberDefinition<Root: AnyObject & Sendable>: Sendable {
    internal let name: String
    internal let validationMessage: String?
    internal let environmentDescription: EnvironmentMemberDescription
    internal let materialize: @Sendable (
        Root
    ) async throws -> JavaScriptExportMemberDefinition

    internal var environmentGlobalDescription: EnvironmentGlobalDescription {
        switch environmentDescription {
        case let .function(function):
            return .function(function)
        case let .value(value):
            return .value(
                EnvironmentValueDescription(
                    name: value.name,
                    type: value.type,
                    documentation: value.documentation,
                    isReadOnly: false
                )
            )
        }
    }
}
