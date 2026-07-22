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
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
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
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
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
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
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
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
    }

    /// Registers a synchronous Swift function that returns JavaScript `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
    }

    /// Registers a throwing Swift function that returns JavaScript `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
    }

    /// Registers an asynchronous Swift function that fulfills with `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
    }

    /// Registers an asynchronous throwing function that fulfills with `undefined`.
    @discardableResult
    public func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
    ) throws -> JavaScriptBinding
    where repeat each Argument: Decodable & Sendable {
        var builder = JavaScriptExportBuilder()
        builder.function(name, options: options, body)
        return try registerGlobalFunction(builder.members[0])
    }

    internal func settleSwiftPromise(
        _ identifier: UInt64,
        completion: BindingCompletion
    ) {
        reportEngineEntryFailure {
            switch completion {
            case let .success(result):
                do {
                    engine.settleSwiftPromise(
                        identifier,
                        with: .success(try result.encode(engine))
                    )
                } catch {
                    engine.settleSwiftPromise(identifier, with: .failure(error))
                }
            case let .failure(error):
                engine.settleSwiftPromise(identifier, with: .failure(error))
            }
        }
    }

    internal func reportEngineEntryFailure(_ operation: () throws -> Void) {
        do {
            try engine.withEngineEntry(operation)
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

    internal func registerGlobalFunction(
        _ member: JavaScriptExportMemberDefinition
    ) throws -> JavaScriptBinding {
        if let message = member.validationMessage {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        guard case let .function(definition) = member.storage else {
            throw JavaScriptError(
                kind: .internalFailure,
                message: "A global function definition contained a non-function member."
            )
        }
        return try engine.withEngineEntry() {
            let function = definition.bind(
                location: .global,
                order: engine.nextBindingIdentifier,
                settle: bindingSettlement
            )
            let (identifier, rawValue) = try engine.registerGlobalBinding(
                named: member.name,
                function: function
            )
            return JavaScriptBinding(
                name: member.name,
                value: makeValue(rawValue),
                reference: JavaScriptBindingReference(runtime: self, identifier: identifier)
            )
        }
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

    internal func nextHost<T: JavaScriptHostTypeProviding>(
        _ type: T.Type,
        runtime: isolated JavaScriptRuntime
    ) throws -> T {
        defer { index += 1 }
        let value = index < arguments.count
            ? arguments[index]
            : ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        let rootIdentifier = try hostIdentifier(type, from: value)
        return try runtime.runtimeRoot(rootIdentifier, as: type)
    }

    internal func nextHostIdentifier<T: JavaScriptHostTypeProviding>(
        _ type: T.Type
    ) throws -> UInt64 {
        defer { index += 1 }
        let value = index < arguments.count
            ? arguments[index]
            : ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
        return try hostIdentifier(type, from: value)
    }

    internal func nextOptionalHostIdentifier<T: JavaScriptHostTypeProviding>(
        _ type: T.Type
    ) throws -> UInt64? {
        guard index < arguments.count else {
            index += 1
            return nil
        }
        let value = arguments[index]
        if engine.isNullish(value) {
            index += 1
            return nil
        }
        return try nextHostIdentifier(type)
    }

    internal func nextOptionalHost<T: JavaScriptHostTypeProviding>(
        _ type: T.Type,
        runtime: isolated JavaScriptRuntime
    ) throws -> T? {
        guard index < arguments.count else {
            index += 1
            return nil
        }
        let value = arguments[index]
        if engine.isNullish(value) {
            index += 1
            return nil
        }
        return try nextHost(type, runtime: runtime)
    }

    private func hostIdentifier<T: JavaScriptHostTypeProviding>(
        _ type: T.Type,
        from value: ManagedQuickJSValue
    ) throws -> UInt64 {
        let typeIdentifier = try engine.hostTypeIdentifier(for: type)
        return try engine.hostRootIdentifier(
            from: value.raw,
            expectedTypeIdentifier: typeIdentifier
        )
    }
}
