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
        do {
            let encoded = try engine.encode(
                value,
                maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
            )
            engine.settleSwiftPromise(identifier, with: .success(encoded))
        } catch {
            engine.settleSwiftPromise(identifier, with: .failure(error))
        }
        drainAfterAsyncSettlement()
    }

    internal func settleSwiftPromiseWithUndefined(_ identifier: UInt64) {
        let value = ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        engine.settleSwiftPromise(identifier, with: .success(value))
        drainAfterAsyncSettlement()
    }

    internal func settleSwiftPromise(_ identifier: UInt64, error: any Error) {
        engine.settleSwiftPromise(identifier, with: .failure(error))
        drainAfterAsyncSettlement()
    }

    private func drainAfterAsyncSettlement() {
        do {
            try engine.drainPendingJobs()
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
        let parameterNames = try validatedParameterNames(
            options.parameterNames,
            arity: parameterShapes.count
        )
        let description = BindingDescription(
            location: .global,
            name: try validatedBindingName(name),
            parameters: zip(parameterNames, parameterShapes).map {
                BindingParameterDescription(name: $0, type: $1)
            },
            result: resultShape,
            effects: .init(isAsync: isAsync, isThrowing: isThrowing),
            documentation: options.documentation,
            order: engine.nextBindingIdentifier
        )
        let (identifier, rawValue) = try engine.registerGlobalBinding(
            named: name,
            invocation: AnyBindingInvocation(description: description, invoke: invocation)
        )
        try engine.drainPendingJobs()
        return JavaScriptBinding(
            name: name,
            value: makeValue(rawValue),
            reference: JavaScriptBindingReference(runtime: self, identifier: identifier)
        )
    }

    private func validatedBindingName(_ name: String) throws -> String {
        guard !name.isEmpty, !name.contains("\0") else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Binding names must be non-empty and contain no NUL characters."
            )
        }
        return name
    }

    private func validatedParameterNames(_ names: [String]?, arity: Int) throws -> [String] {
        guard let names else { return (0..<arity).map { "argument\($0)" } }
        guard names.count == arity else {
            throw JavaScriptError(
                kind: .conversion,
                message: "The number of parameter names must match the Swift closure arity."
            )
        }
        guard Set(names).count == names.count,
              names.allSatisfy(isValidJavaScriptIdentifier) else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Parameter names must be unique valid JavaScript identifiers."
            )
        }
        return names
    }

    private func isValidJavaScriptIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first,
              isIdentifierStart(first),
              name.unicodeScalars.dropFirst().allSatisfy(isIdentifierContinue) else {
            return false
        }
        return !Self.reservedParameterNames.contains(name)
    }

    private func isIdentifierStart(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "_" || scalar == "$" ||
            (scalar.value >= 65 && scalar.value <= 90) ||
            (scalar.value >= 97 && scalar.value <= 122)
    }

    private func isIdentifierContinue(_ scalar: Unicode.Scalar) -> Bool {
        isIdentifierStart(scalar) || (scalar.value >= 48 && scalar.value <= 57)
    }

    private static let reservedParameterNames: Set<String> = [
        "await", "break", "case", "catch", "class", "const", "continue",
        "debugger", "default", "delete", "do", "else", "enum", "export",
        "extends", "false", "finally", "for", "function", "if", "import",
        "in", "instanceof", "let", "new", "null", "return", "static",
        "super", "switch", "this", "throw", "true", "try", "typeof",
        "var", "void", "while", "with", "yield", "implements", "interface",
        "package", "private", "protected", "public",
    ]
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
