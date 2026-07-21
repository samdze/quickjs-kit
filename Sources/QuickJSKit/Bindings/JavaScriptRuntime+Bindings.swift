extension JavaScriptRuntime {
    /// Registers a synchronous Swift function in the JavaScript global object.
    @discardableResult
    public func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Result
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable,
          Result: Encodable & Sendable {
        try registerFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: false,
            isThrowing: false,
            resultShape: bindingTypeShape(for: Result.self)
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            let result = body(repeat each decoded)
            return .synchronous(
                try engine.encode(
                    result,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
            )
        }
    }

    /// Registers a throwing synchronous Swift function in the global object.
    @discardableResult
    public func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Result
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable,
          Result: Encodable & Sendable {
        try registerFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: false,
            isThrowing: true,
            resultShape: bindingTypeShape(for: Result.self)
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            let result = try body(repeat each decoded)
            return .synchronous(
                try engine.encode(
                    result,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
            )
        }
    }

    /// Registers an asynchronous Swift function backed by a native JavaScript promise.
    @discardableResult
    public func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Result
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable,
          Result: Encodable & Sendable {
        try registerFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: true,
            isThrowing: false,
            resultShape: bindingTypeShape(for: Result.self)
        ) { [weak self] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak self] operationIdentifier in
                Task {
                    let result = await body(repeat each decoded)
                    await self?.settleSwiftPromise(operationIdentifier, value: result)
                }
            }
        }
    }

    /// Registers an asynchronous throwing Swift function backed by a native promise.
    @discardableResult
    public func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Result
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable,
          Result: Encodable & Sendable {
        try registerFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: true,
            isThrowing: true,
            resultShape: bindingTypeShape(for: Result.self)
        ) { [weak self] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak self] operationIdentifier in
                Task {
                    do {
                        let result = try await body(repeat each decoded)
                        await self?.settleSwiftPromise(operationIdentifier, value: result)
                    } catch {
                        await self?.settleSwiftPromise(operationIdentifier, error: error)
                    }
                }
            }
        }
    }

    /// Registers a synchronous Swift function that returns JavaScript `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        try registerVoidFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: false,
            isThrowing: false
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            body(repeat each decoded)
            return .synchronous(
                ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            )
        }
    }

    /// Registers a throwing Swift function that returns JavaScript `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        try registerVoidFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: false,
            isThrowing: true
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            try body(repeat each decoded)
            return .synchronous(
                ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            )
        }
    }

    /// Registers an asynchronous Swift function that fulfills with `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        try registerVoidFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: true,
            isThrowing: false
        ) { [weak self] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak self] operationIdentifier in
                Task {
                    await body(repeat each decoded)
                    await self?.settleSwiftPromiseWithUndefined(operationIdentifier)
                }
            }
        }
    }

    /// Registers an asynchronous throwing Swift function that fulfills with `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        try registerVoidFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            isAsync: true,
            isThrowing: true
        ) { [weak self] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak self] operationIdentifier in
                Task {
                    do {
                        try await body(repeat each decoded)
                        await self?.settleSwiftPromiseWithUndefined(operationIdentifier)
                    } catch {
                        await self?.settleSwiftPromise(operationIdentifier, error: error)
                    }
                }
            }
        }
    }

    internal func settleSwiftPromise<T: Encodable & Sendable>(
        _ identifier: UInt64,
        value: T
    ) {
        performAsyncSettlement {
            do {
                let encoded = try engine.encode(
                    value,
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
                engine.settleSwiftPromise(identifier, with: .success(encoded))
            } catch {
                engine.settleSwiftPromise(identifier, with: .failure(error))
            }
        }
    }

    internal func settleSwiftPromiseWithUndefined(_ identifier: UInt64) {
        performAsyncSettlement {
            let value = ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            engine.settleSwiftPromise(identifier, with: .success(value))
        }
    }

    internal func settleSwiftPromise(_ identifier: UInt64, error: any Error) {
        performAsyncSettlement {
            engine.settleSwiftPromise(identifier, with: .failure(error))
        }
    }

    private func performAsyncSettlement(_ operation: () throws -> Void) {
        do {
            try engine.withExecution(options: .init(), operation)
        } catch let error as JavaScriptError {
            engine.unhandledRejectionHandler?(error)
        } catch {
            engine.unhandledRejectionHandler?(
                JavaScriptError(
                    kind: .internalFailure,
                    message: String(describing: error)
                )
            )
        }
    }

    private func registerFunction(
        _ name: String,
        options: JavaScriptFunctionOptions,
        parameterShapes: [BindingTypeShape],
        isAsync: Bool,
        isThrowing: Bool,
        resultShape: BindingTypeShape,
        invocation: @escaping (QuickJSEngine, [ManagedQuickJSValue]) throws -> BindingInvocation
    ) throws -> JavaScriptBinding {
        return try registerFunctionWithShapes(
            name,
            options: options,
            parameterShapes: parameterShapes,
            isAsync: isAsync,
            isThrowing: isThrowing,
            resultShape: resultShape,
            invocation: invocation
        )
    }

    private func registerVoidFunction(
        _ name: String,
        options: JavaScriptFunctionOptions,
        parameterShapes: [BindingTypeShape],
        isAsync: Bool,
        isThrowing: Bool,
        invocation: @escaping (QuickJSEngine, [ManagedQuickJSValue]) throws -> BindingInvocation
    ) throws -> JavaScriptBinding {
        try registerFunction(
            name,
            options: options,
            parameterShapes: parameterShapes,
            isAsync: isAsync,
            isThrowing: isThrowing,
            resultShape: .void,
            invocation: invocation
        )
    }

    private func registerFunctionWithShapes(
        _ name: String,
        options: JavaScriptFunctionOptions,
        parameterShapes: [BindingTypeShape],
        isAsync: Bool,
        isThrowing: Bool,
        resultShape: BindingTypeShape,
        invocation: @escaping (QuickJSEngine, [ManagedQuickJSValue]) throws -> BindingInvocation
    ) throws -> JavaScriptBinding {
        try engine.withExecution(options: .init()) {
            let parameterNames = try validatedParameterNames(
                options.parameterNames,
                arity: parameterShapes.count
            )
            let draft = BindingDraft(
                name: try validatedBindingName(name),
                parameters: zip(parameterNames, parameterShapes).map {
                    BindingParameterDescription(name: $0, type: $1)
                },
                result: resultShape,
                effects: .init(isAsync: isAsync, isThrowing: isThrowing),
                documentation: options.documentation
            )
            let binding = AnyBindingDraft(draft: draft, invoke: invocation).finalize(
                location: .global,
                order: engine.nextBindingIdentifier
            )
            let (identifier, rawValue) = try engine.registerGlobalBinding(
                named: name,
                invocation: binding
            )
            return JavaScriptBinding(
                name: name,
                value: makeValue(rawValue),
                reference: JavaScriptBindingReference(runtime: self, identifier: identifier)
            )
        }
    }

    private func validatedBindingName(_ name: String) throws -> String {
        if let message = BindingValidation.nameMessage(name, role: "Binding names") {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        return name
    }

    private func validatedParameterNames(_ names: [String]?, arity: Int) throws -> [String] {
        let validation = BindingValidation.parameterNames(names, arity: arity)
        if let message = validation.message {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        return validation.names
    }
}

internal final class BindingArgumentDecoder {
    private let engine: QuickJSEngine
    private let arguments: [ManagedQuickJSValue]
    private var index = 0

    internal init(engine: QuickJSEngine, arguments: [ManagedQuickJSValue]) {
        self.engine = engine
        self.arguments = arguments
    }

    internal func next<T: Decodable & Sendable>(_ type: T.Type) throws -> T {
        defer { index += 1 }
        let value: ManagedQuickJSValue
        if index < arguments.count {
            value = arguments[index]
        } else {
            value = ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        }
        return try engine.decode(
            type,
            from: value,
            maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
        )
    }
}
