/// A transactional description of Swift members exported to JavaScript.
///
/// Configure exports inside ``JavaScriptRuntime/export(_:as:_:)`` or
/// ``JavaScriptRuntime/defineModule(_:_:)``. The destination runtime validates
/// and encodes every member before publishing it.
public struct JavaScriptExportBuilder {
    internal var members: [JavaScriptExportMemberDefinition] = []

    internal init() {}

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

    /// Adds a read-only enumerable snapshot value.
    public mutating func value<Value: Encodable & Sendable>(
        _ value: Value,
        as name: String,
        documentation: String? = nil
    ) {
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: exportMemberValidationMessage(name),
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
        documentation: String? = nil
    ) {
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: exportMemberValidationMessage(name),
                storage: .liveValue(type: bindingTypeShape(for: value), value: value)
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
            return .asynchronous {
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
        let validationMessage = parameters.message ?? exportMemberValidationMessage(name)
        let draft = BindingDraft(
            name: name,
            parameters: zip(names, parameterShapes).map {
                BindingParameterDescription(name: $0, type: $1)
            },
            result: resultShape,
            effects: .init(isAsync: isAsync, isThrowing: isThrowing),
            documentation: options.documentation
        )
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: options.documentation,
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
        case value(
            type: BindingTypeShape,
            encode: @Sendable (QuickJSEngine) throws -> ManagedQuickJSValue
        )
        case liveValue(type: BindingTypeShape, value: JavaScriptValue)
    }

    internal let name: String
    internal let documentation: String?
    internal let validationMessage: String?
    internal let storage: Storage
}

extension JavaScriptRuntime {
    /// Exposes explicitly configured methods and snapshot values on one object.
    ///
    /// The operation is transactional: the global object is unchanged if any
    /// member fails validation or encoding.
    @discardableResult
    public func export<Root: AnyObject & Sendable>(
        _ root: Root,
        as name: String,
        _ configure: @Sendable (Root, inout JavaScriptExportBuilder) -> Void
    ) throws -> JavaScriptBinding {
        if let message = BindingValidation.nameMessage(name, role: "Export names") {
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
