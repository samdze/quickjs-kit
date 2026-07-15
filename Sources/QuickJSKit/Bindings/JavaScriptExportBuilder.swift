/// A transactional description of members exposed on a Swift-backed JavaScript object.
///
/// Configure exports only inside ``JavaScriptRuntime/export(_:as:_:)``. The
/// runtime validates and encodes every member before publishing the object.
public struct JavaScriptExportBuilder {
    internal let runtime: JavaScriptRuntime
    internal var members: [JavaScriptExportMemberDefinition] = []

    internal init(runtime: JavaScriptRuntime) {
        self.runtime = runtime
    }

    /// Adds a synchronous typed method.
    public mutating func function<each Argument, Result>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Result
    ) where repeat each Argument: Decodable & Sendable,
            Result: Encodable & Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: bindingTypeShape(for: Result.self),
            isAsync: false,
            isThrowing: false
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .synchronous(
                try engine.encode(
                    body(repeat each decoded),
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
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
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: bindingTypeShape(for: Result.self),
            isAsync: false,
            isThrowing: true
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .synchronous(
                try engine.encode(
                    body(repeat each decoded),
                    maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                )
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
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: bindingTypeShape(for: Result.self),
            isAsync: true,
            isThrowing: false
        ) { [weak runtime] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak runtime] operationIdentifier in
                Task {
                    let value = await body(repeat each decoded)
                    await runtime?.settleSwiftPromise(operationIdentifier, value: value)
                }
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
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: bindingTypeShape(for: Result.self),
            isAsync: true,
            isThrowing: true
        ) { [weak runtime] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak runtime] operationIdentifier in
                Task {
                    do {
                        let value = try await body(repeat each decoded)
                        await runtime?.settleSwiftPromise(operationIdentifier, value: value)
                    } catch {
                        await runtime?.settleSwiftPromise(operationIdentifier, error: error)
                    }
                }
            }
        }
    }

    /// Adds a synchronous typed method returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: .void,
            isAsync: false,
            isThrowing: false
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            body(repeat each decoded)
            return .synchronous(ManagedQuickJSValue(quickJSUndefined(), in: engine.context))
        }
    }

    /// Adds a throwing typed method returning JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: .void,
            isAsync: false,
            isThrowing: true
        ) { engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            try body(repeat each decoded)
            return .synchronous(ManagedQuickJSValue(quickJSUndefined(), in: engine.context))
        }
    }

    /// Adds an asynchronous typed method fulfilling with JavaScript `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: .void,
            isAsync: true,
            isThrowing: false
        ) { [weak runtime] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak runtime] operationIdentifier in
                Task {
                    await body(repeat each decoded)
                    await runtime?.settleSwiftPromiseWithUndefined(operationIdentifier)
                }
            }
        }
    }

    /// Adds an asynchronous throwing method fulfilling with `undefined`.
    public mutating func function<each Argument>(
        _ name: String,
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Void
    ) where repeat each Argument: Decodable & Sendable {
        appendFunction(
            name,
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            resultShape: .void,
            isAsync: true,
            isThrowing: true
        ) { [weak runtime] engine, arguments in
            let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
            let decoded: (repeat each Argument) =
                (repeat try decoder.next((each Argument).self))
            return .asynchronous { [weak runtime] operationIdentifier in
                Task {
                    do {
                        try await body(repeat each decoded)
                        await runtime?.settleSwiftPromiseWithUndefined(operationIdentifier)
                    } catch {
                        await runtime?.settleSwiftPromise(operationIdentifier, error: error)
                    }
                }
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
                storage: .value { engine in
                    try engine.encode(
                        value,
                        maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                    )
                }
            )
        )
    }

    /// Adds a read-only enumerable same-runtime JavaScript value.
    public mutating func value(
        _ value: JavaScriptValue,
        as name: String,
        documentation: String? = nil
    ) {
        let crossRuntime: Bool
        if case let .reference(reference) = value.storage {
            crossRuntime = reference.runtimeIdentifier != ObjectIdentifier(runtime)
        } else {
            crossRuntime = false
        }
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: documentation,
                validationMessage: crossRuntime
                    ? "JavaScript values cannot cross runtime boundaries."
                    : exportMemberValidationMessage(name),
                storage: .value { engine in try engine.materialize(value) }
            )
        )
    }

    private mutating func appendFunction(
        _ name: String,
        options: JavaScriptFunctionOptions,
        parameterShapes: [BindingTypeShape],
        resultShape: BindingTypeShape,
        isAsync: Bool,
        isThrowing: Bool,
        invocation: @escaping (QuickJSEngine, [ManagedQuickJSValue]) throws -> BindingInvocation
    ) {
        let names = options.parameterNames ?? (0..<parameterShapes.count).map { "argument\($0)" }
        var validationMessage = exportMemberValidationMessage(name)
        if names.count != parameterShapes.count {
            validationMessage = "The number of parameter names must match the Swift closure arity."
        } else if Set(names).count != names.count || !names.allSatisfy(isConservativeIdentifier) {
            validationMessage = "Parameter names must be unique valid JavaScript identifiers."
        }
        let description = BindingDescription(
            location: .exportMember(exportName: ""),
            name: name,
            parameters: zip(names, parameterShapes).map {
                BindingParameterDescription(name: $0, type: $1)
            },
            result: resultShape,
            effects: .init(isAsync: isAsync, isThrowing: isThrowing),
            documentation: options.documentation,
            order: UInt64(members.count)
        )
        members.append(
            JavaScriptExportMemberDefinition(
                name: name,
                documentation: options.documentation,
                validationMessage: validationMessage,
                storage: .function(
                    AnyBindingInvocation(description: description, invoke: invocation)
                )
            )
        )
    }

    private func exportMemberValidationMessage(_ name: String) -> String? {
        name.isEmpty || name.contains("\0")
            ? "Export member names must be non-empty and contain no NUL characters."
            : nil
    }

    private func isConservativeIdentifier(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        func isStart(_ scalar: Unicode.Scalar) -> Bool {
            scalar == "_" || scalar == "$" ||
                (65...90).contains(scalar.value) || (97...122).contains(scalar.value)
        }
        let hasValidScalars = isStart(first) && name.unicodeScalars.dropFirst().allSatisfy {
            isStart($0) || (48...57).contains($0.value)
        }
        return hasValidScalars && !Self.reservedParameterNames.contains(name)
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

internal struct JavaScriptExportMemberDefinition {
    internal enum Storage {
        case function(AnyBindingInvocation)
        case value((QuickJSEngine) throws -> ManagedQuickJSValue)
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
        guard !name.isEmpty, !name.contains("\0") else {
            throw JavaScriptError(
                kind: .conversion,
                message: "Export names must be non-empty and contain no NUL characters."
            )
        }
        var builder = JavaScriptExportBuilder(runtime: self)
        configure(root, &builder)
        if let message = builder.members.lazy.compactMap(\.validationMessage).first {
            throw JavaScriptError(kind: .conversion, message: message)
        }
        let (identifier, rawValue) = try engine.registerExport(
            named: name,
            root: root,
            members: builder.members
        )
        try engine.drainPendingJobs()
        return JavaScriptBinding(
            name: name,
            value: makeValue(rawValue),
            reference: JavaScriptBindingReference(runtime: self, identifier: identifier)
        )
    }
}
