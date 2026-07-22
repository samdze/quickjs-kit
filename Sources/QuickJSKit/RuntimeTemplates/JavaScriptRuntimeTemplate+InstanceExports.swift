extension JavaScriptRuntimeTemplate {
    /// Composes members backed by one per-runtime Swift root.
    @resultBuilder
    public enum InstanceExportBuilder<Root: AnyObject> {
        /// Accepts one contextual root-backed member declaration.
        internal static func buildExpression(
            _ expression: InstanceExport<Root>
        ) -> InstanceExport<Root> {
            expression
        }

        /// Combines members in lexical order.
        public static func buildBlock(
            _ components: InstanceExport<Root>...
        ) -> InstanceExport<Root> {
            InstanceExport.merging(components)
        }

        /// Includes members produced by an optional branch.
        public static func buildOptional(
            _ component: InstanceExport<Root>?
        ) -> InstanceExport<Root> {
            component ?? InstanceExport()
        }

        /// Selects the first branch of a conditional member declaration.
        public static func buildEither(
            first component: InstanceExport<Root>
        ) -> InstanceExport<Root> {
            component
        }

        /// Selects the second branch of a conditional member declaration.
        public static func buildEither(
            second component: InstanceExport<Root>
        ) -> InstanceExport<Root> {
            component
        }

        /// Flattens members produced by a loop.
        public static func buildArray(
            _ components: [InstanceExport<Root>]
        ) -> InstanceExport<Root> {
            InstanceExport.merging(components)
        }

        /// Preserves members guarded by an availability check.
        public static func buildLimitedAvailability(
            _ component: InstanceExport<Root>
        ) -> InstanceExport<Root> {
            component
        }
    }

    /// One or more declarations backed by a per-runtime Swift root.
    ///
    /// The root is supplied to Swift closures as their first argument but is
    /// omitted from JavaScript signatures and generated TypeScript declarations.
    public struct InstanceExport<Root: AnyObject>: Sendable {
        internal var members: [RuntimeInstanceMemberDefinition<Root>] = []

        internal init() {}

        /// Creates a reusable root-aware export definition.
        public init(
            @InstanceExportBuilder<Root>
            _ content: @Sendable () -> InstanceExport<Root>
        ) {
            self = content()
        }

        /// Declares a synchronous member returning a live Swift host object.
        internal static func hostFunction<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: JavaScriptHostTypeProviding & Sendable {
            makeHostResultFunction(
                name,
                options: options,
                isThrowing: false,
                body: body
            )
        }

        /// Declares a throwing synchronous member returning a live Swift host object.
        internal static func hostFunction<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: JavaScriptHostTypeProviding & Sendable {
            makeHostResultFunction(
                name,
                options: options,
                isThrowing: true,
                body: body
            )
        }

        private static func makeHostResultFunction<each Argument,
            Result: JavaScriptHostTypeProviding & Sendable
        >(
            _ name: String,
            options: JavaScriptFunctionOptions,
            isThrowing: Bool,
            body: @escaping @Sendable (Root, repeat each Argument) throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable {
            let parameterShapes = bindingParameterShapes(
                repeat (each Argument).self
            )
            let parameters = BindingValidation.parameterNames(
                options.parameterNames,
                arity: parameterShapes.count
            )
            let draft = BindingDraft(
                name: name,
                parameters: zip(parameters.names, parameterShapes).map {
                    BindingParameterDescription(
                        name: $0,
                        type: $1,
                        sourceLocation: options.parameterSourceLocations[$0]
                    )
                },
                result: .host(
                    name: Result.javaScriptHostTypeName,
                    scope: Result.javaScriptHostTypeScope
                ),
                effects: .init(isAsync: false, isThrowing: isThrowing),
                documentation: options.documentation,
                sourceLocation: options.sourceLocation
            )
            var result = Self()
            result.members.append(
                RuntimeInstanceMemberDefinition(
                    name: name,
                    validationMessage: parameters.message
                        ?? BindingValidation.nameMessage(name, role: "Export member names"),
                    environmentDescription: .function(
                        EnvironmentFunctionDescription(draft)
                    ),
                    materialize: { _, rootSource in
                        let function = RuntimeLocalFunctionDefinition(draft: draft) {
                            runtime, engine, receiver, arguments in
                            let decoder = BindingArgumentDecoder(
                                engine: engine,
                                arguments: arguments
                            )
                            let decoded: (repeat each Argument) =
                                (repeat try decoder.next((each Argument).self))
                            let root = try runtime.runtimeRoot(
                                from: rootSource,
                                receiver: receiver,
                                as: Root.self
                            )
                            let returned = try body(root, repeat each decoded)
                            let typeIdentifier = try engine.hostTypeIdentifier(
                                for: Result.self
                            )
                            let rootIdentifier = try runtime.retainHostObject(returned)
                            do {
                                return .synchronous(
                                    try engine.makeRegisteredHostObject(
                                        rootIdentifier: rootIdentifier,
                                        typeIdentifier: typeIdentifier
                                    )
                                )
                            } catch {
                                runtime.releaseRuntimeRoot(rootIdentifier)
                                throw error
                            }
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: nil,
                            validationMessage: nil,
                            storage: .runtimeFunction(function)
                        )
                    }
                )
            )
            return result
        }

        internal static func optionalHostFunction<each Argument,
            Result: JavaScriptHostTypeProviding & Sendable
        >(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            isThrowing: Bool,
            _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result?
        ) -> Self where repeat each Argument: Decodable & Sendable {
            let parameterShapes = bindingParameterShapes(
                repeat (each Argument).self
            )
            let parameters = BindingValidation.parameterNames(
                options.parameterNames,
                arity: parameterShapes.count
            )
            let resultShape = BindingTypeShape.optional(
                .host(
                    name: Result.javaScriptHostTypeName,
                    scope: Result.javaScriptHostTypeScope
                )
            )
            let draft = BindingDraft(
                name: name,
                parameters: zip(parameters.names, parameterShapes).map {
                    BindingParameterDescription(
                        name: $0,
                        type: $1,
                        sourceLocation: options.parameterSourceLocations[$0]
                    )
                },
                result: resultShape,
                effects: .init(isAsync: false, isThrowing: isThrowing),
                documentation: options.documentation,
                sourceLocation: options.sourceLocation
            )
            var result = Self()
            result.members.append(
                RuntimeInstanceMemberDefinition(
                    name: name,
                    validationMessage: parameters.message
                        ?? BindingValidation.nameMessage(
                            name,
                            role: "Export member names"
                        ),
                    environmentDescription: .function(
                        EnvironmentFunctionDescription(draft)
                    ),
                    materialize: { _, rootSource in
                        let function = RuntimeLocalFunctionDefinition(draft: draft) {
                            runtime, engine, receiver, arguments in
                            let decoder = BindingArgumentDecoder(
                                engine: engine,
                                arguments: arguments
                            )
                            let decoded: (repeat each Argument) =
                                (repeat try decoder.next((each Argument).self))
                            let root = try runtime.runtimeRoot(
                                from: rootSource,
                                receiver: receiver,
                                as: Root.self
                            )
                            guard let returned = try body(
                                root,
                                repeat each decoded
                            ) else {
                                return .synchronous(
                                    ManagedQuickJSValue(
                                        quickJSNull(),
                                        in: engine.context
                                    )
                                )
                            }
                            let typeIdentifier = try engine.hostTypeIdentifier(
                                for: Result.self
                            )
                            let rootIdentifier = try runtime.retainHostObject(returned)
                            do {
                                return .synchronous(
                                    try engine.makeRegisteredHostObject(
                                        rootIdentifier: rootIdentifier,
                                        typeIdentifier: typeIdentifier
                                    )
                                )
                            } catch {
                                runtime.releaseRuntimeRoot(rootIdentifier)
                                throw error
                            }
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: nil,
                            validationMessage: nil,
                            storage: .runtimeFunction(function)
                        )
                    }
                )
            )
            return result
        }

        internal static func runtimeIsolatedHostResultFunction<each Argument,
            Result: JavaScriptHostTypeProviding
        >(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            optional: Bool = false,
            isThrowing: Bool,
            _ body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async throws -> Result?
        ) -> Self where repeat each Argument: Decodable & Sendable {
            let parameterShapes = bindingParameterShapes(
                repeat (each Argument).self
            )
            let parameters = BindingValidation.parameterNames(
                options.parameterNames,
                arity: parameterShapes.count
            )
            let hostShape = BindingTypeShape.host(
                name: Result.javaScriptHostTypeName,
                scope: Result.javaScriptHostTypeScope
            )
            let draft = BindingDraft(
                name: name,
                parameters: zip(parameters.names, parameterShapes).map {
                    BindingParameterDescription(
                        name: $0,
                        type: $1,
                        sourceLocation: options.parameterSourceLocations[$0]
                    )
                },
                result: optional ? .optional(hostShape) : hostShape,
                effects: .init(isAsync: true, isThrowing: isThrowing),
                documentation: options.documentation,
                sourceLocation: options.sourceLocation
            )
            var result = Self()
            result.members.append(
                RuntimeInstanceMemberDefinition(
                    name: name,
                    validationMessage: parameters.message
                        ?? BindingValidation.nameMessage(
                            name,
                            role: "Export member names"
                        ),
                    environmentDescription: .function(
                        EnvironmentFunctionDescription(draft)
                    ),
                    materialize: { _, rootSource in
                        let function = RuntimeLocalFunctionDefinition(draft: draft) {
                            runtime, engine, receiver, arguments in
                            let decoder = BindingArgumentDecoder(
                                engine: engine,
                                arguments: arguments
                            )
                            let decoded: (repeat each Argument) =
                                (repeat try decoder.next((each Argument).self))
                            let receiverIdentifier = try runtime
                                .retainRuntimeRootForOperation(
                                    from: rootSource,
                                    receiver: receiver
                                )
                            let typeIdentifier = try engine.hostTypeIdentifier(
                                for: Result.self
                            )
                            return .asynchronous { runtime in
                                defer {
                                    runtime.releaseRuntimeRoot(receiverIdentifier)
                                }
                                do {
                                    let root = try runtime.runtimeRoot(
                                        receiverIdentifier,
                                        as: Root.self
                                    )
                                    guard let returned = try await body(
                                        runtime,
                                        root,
                                        repeat each decoded
                                    ) else {
                                        return .success(
                                            BindingResult { engine in
                                                ManagedQuickJSValue(
                                                    quickJSNull(),
                                                    in: engine.context
                                                )
                                            }
                                        )
                                    }
                                    let returnedIdentifier = try runtime
                                        .retainHostObject(returned)
                                    return .success(
                                        BindingResult { engine in
                                            do {
                                                return try engine
                                                    .makeRegisteredHostObject(
                                                        rootIdentifier:
                                                            returnedIdentifier,
                                                        typeIdentifier:
                                                            typeIdentifier
                                                    )
                                            } catch {
                                                engine.releaseRuntimeRoot(
                                                    returnedIdentifier
                                                )
                                                throw error
                                            }
                                        }
                                    )
                                } catch {
                                    return .failure(error)
                                }
                            }
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: nil,
                            validationMessage: nil,
                            storage: .runtimeFunction(function)
                        )
                    }
                )
            )
            return result
        }

        /// Declares a synchronous member accepting one exact host reference.
        internal static func hostArgumentFunction<
            Argument: JavaScriptHostTypeProviding,
            Result: Encodable & Sendable
        >(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            optional: Bool = false,
            isThrowing: Bool,
            _ body: @escaping @Sendable (Root, Argument?) throws -> Result
        ) -> Self {
            let names = BindingValidation.parameterNames(options.parameterNames, arity: 1)
            let hostShape = BindingTypeShape.host(
                name: Argument.javaScriptHostTypeName,
                scope: Argument.javaScriptHostTypeScope
            )
            let draft = BindingDraft(
                name: name,
                parameters: [
                    BindingParameterDescription(
                        name: names.names[0],
                        type: optional ? .optional(hostShape) : hostShape,
                        sourceLocation: options.parameterSourceLocations[names.names[0]]
                    )
                ],
                result: bindingTypeShape(for: Result.self),
                effects: .init(isAsync: false, isThrowing: isThrowing),
                documentation: options.documentation,
                sourceLocation: options.sourceLocation
            )
            var result = Self()
            result.members.append(
                RuntimeInstanceMemberDefinition(
                    name: name,
                    validationMessage: names.message
                        ?? BindingValidation.nameMessage(name, role: "Export member names"),
                    environmentDescription: .function(EnvironmentFunctionDescription(draft)),
                    materialize: { _, rootSource in
                        let function = RuntimeLocalFunctionDefinition(draft: draft) {
                            runtime, engine, receiver, arguments in
                            let root = try runtime.runtimeRoot(
                                from: rootSource,
                                receiver: receiver,
                                as: Root.self
                            )
                            let decoder = BindingArgumentDecoder(
                                engine: engine,
                                arguments: arguments
                            )
                            let argument = optional
                                ? try decoder.nextOptionalHost(Argument.self, runtime: runtime)
                                : try decoder.nextHost(Argument.self, runtime: runtime)
                            return .synchronous(
                                try engine.encode(
                                    body(root, argument),
                                    maximumNestingDepth:
                                        JavaScriptEncoder.defaultMaximumNestingDepth
                                )
                            )
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: nil,
                            validationMessage: nil,
                            storage: .runtimeFunction(function)
                        )
                    }
                )
            )
            return result
        }

        internal static func runtimeIsolatedHostArgumentFunction<
            Argument: JavaScriptHostTypeProviding,
            Result: Sendable
        >(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            optional: Bool = false,
            isThrowing: Bool,
            resultShape: BindingTypeShape,
            _ body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                Argument?
            ) async throws -> Result,
            encode: @escaping @Sendable (Result) -> BindingResult
        ) -> Self {
            let names = BindingValidation.parameterNames(
                options.parameterNames,
                arity: 1
            )
            let hostShape = BindingTypeShape.host(
                name: Argument.javaScriptHostTypeName,
                scope: Argument.javaScriptHostTypeScope
            )
            let draft = BindingDraft(
                name: name,
                parameters: [
                    BindingParameterDescription(
                        name: names.names[0],
                        type: optional ? .optional(hostShape) : hostShape,
                        sourceLocation:
                            options.parameterSourceLocations[names.names[0]]
                    )
                ],
                result: resultShape,
                effects: .init(isAsync: true, isThrowing: isThrowing),
                documentation: options.documentation,
                sourceLocation: options.sourceLocation
            )
            var result = Self()
            result.members.append(
                RuntimeInstanceMemberDefinition(
                    name: name,
                    validationMessage: names.message
                        ?? BindingValidation.nameMessage(
                            name,
                            role: "Export member names"
                        ),
                    environmentDescription: .function(
                        EnvironmentFunctionDescription(draft)
                    ),
                    materialize: { _, rootSource in
                        let function = RuntimeLocalFunctionDefinition(draft: draft) {
                            runtime, engine, receiver, arguments in
                            let receiverIdentifier = try runtime
                                .retainRuntimeRootForOperation(
                                    from: rootSource,
                                    receiver: receiver
                                )
                            do {
                                let decoder = BindingArgumentDecoder(
                                    engine: engine,
                                    arguments: arguments
                                )
                                let argumentIdentifier = optional
                                    ? try decoder.nextOptionalHostIdentifier(Argument.self)
                                    : try decoder.nextHostIdentifier(Argument.self)
                                if let argumentIdentifier {
                                    try runtime.retainRuntimeRootForOperation(
                                        argumentIdentifier
                                    )
                                }
                                return .asynchronous { runtime in
                                    defer {
                                        runtime.releaseRuntimeRoot(receiverIdentifier)
                                        if let argumentIdentifier {
                                            runtime.releaseRuntimeRoot(argumentIdentifier)
                                        }
                                    }
                                    do {
                                        let root = try runtime.runtimeRoot(
                                            receiverIdentifier,
                                            as: Root.self
                                        )
                                        let argument = try argumentIdentifier.map {
                                            try runtime.runtimeRoot($0, as: Argument.self)
                                        }
                                        return .success(
                                            encode(
                                                try await body(
                                                    runtime,
                                                    root,
                                                    argument
                                                )
                                            )
                                        )
                                    } catch {
                                        return .failure(error)
                                    }
                                }
                            } catch {
                                runtime.releaseRuntimeRoot(receiverIdentifier)
                                throw error
                            }
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: nil,
                            validationMessage: nil,
                            storage: .runtimeFunction(function)
                        )
                    }
                )
            )
            return result
        }

        internal func materialize(
            on runtime: isolated JavaScriptRuntime,
            rootIdentifier: UInt64
        ) async throws -> [JavaScriptExportMemberDefinition] {
            try await materialize(on: runtime, rootSource: .fixed(rootIdentifier))
        }

        internal func materialize(
            on runtime: isolated JavaScriptRuntime,
            rootSource: RuntimeRootSource
        ) async throws -> [JavaScriptExportMemberDefinition] {
            var result: [JavaScriptExportMemberDefinition] = []
            result.reserveCapacity(members.count)
            for member in members {
                result.append(
                    try await member.materialize(runtime, rootSource)
                )
            }
            return result
        }

        /// Declares a synchronous typed function.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeSynchronousFunction(
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

        /// Declares a throwing synchronous typed function.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeSynchronousFunction(
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

        /// Declares an asynchronous typed function backed by a native promise.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) async -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Root: Sendable,
                        Result: Encodable & Sendable {
            makeAsynchronousFunction(
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

        /// Declares an asynchronous throwing function backed by a native promise.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Root: Sendable,
                        Result: Encodable & Sendable {
            makeAsynchronousFunction(
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

        /// Declares a synchronous function returning JavaScript `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeSynchronousFunction(
                name,
                options: options,
                resultShape: .void,
                isThrowing: false,
                body: body
            ) { engine, _ in
                ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            }
        }

        /// Declares a throwing synchronous function returning `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) throws -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeSynchronousFunction(
                name,
                options: options,
                resultShape: .void,
                isThrowing: true,
                body: body
            ) { engine, _ in
                ManagedQuickJSValue(quickJSUndefined(), in: engine.context)
            }
        }

        /// Declares an asynchronous function fulfilling with `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) async -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Root: Sendable {
            makeAsynchronousFunction(
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

        /// Declares an asynchronous throwing function fulfilling with `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            _ body: @escaping @Sendable (Root, repeat each Argument) async throws -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Root: Sendable {
            makeAsynchronousFunction(
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

        /// Declares a snapshot value produced from the per-runtime root.
        ///
        /// The producer runs once during runtime creation. Its value is encoded
        /// directly into that runtime's QuickJS heap.
        internal static func value<Value: Encodable & Sendable>(
            as name: String,
            documentation: TypeScriptDocumentation? = nil,
            _ produce: @escaping @Sendable (Root) async throws -> Value
        ) -> Self where Root: Sendable {
            let type = bindingTypeShape(for: Value.self)
            var result = Self()
            result.members.append(
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
                    materialize: { runtime, rootSource in
                        let root = try runtime.runtimeRoot(
                            from: rootSource,
                            receiver: nil,
                            as: Root.self
                        )
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
            return result
        }

        /// Declares a live read-only property backed by the runtime-local root.
        internal static func property<Value: Encodable & Sendable>(
            _ name: String,
            documentation: TypeScriptDocumentation? = nil,
            sourceLocation: TypeScriptSourceLocation? = nil,
            get: @escaping @Sendable (Root) -> Value
        ) -> Self {
            makeReadOnlySynchronousProperty(
                name,
                documentation: documentation,
                sourceLocation: sourceLocation,
                get: get
            )
        }

        /// Declares a live readable and writable runtime-local property.
        internal static func property<Value: Codable & Sendable>(
            _ name: String,
            documentation: TypeScriptDocumentation? = nil,
            sourceLocation: TypeScriptSourceLocation? = nil,
            get: @escaping @Sendable (Root) -> Value,
            set: @escaping @Sendable (Root, Value) -> Void
        ) -> Self {
            makeSynchronousProperty(
                name,
                documentation: documentation,
                sourceLocation: sourceLocation,
                get: get,
                set: set
            )
        }

        /// Declares a Promise-valued read-only property isolated to the runtime actor.
        internal static func property<Value: Encodable & Sendable>(
            _ name: String,
            documentation: TypeScriptDocumentation? = nil,
            sourceLocation: TypeScriptSourceLocation? = nil,
            runtimeIsolatedGet get: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root
            ) async -> Value
        ) -> Self {
            let type = bindingTypeShape(for: Value.self)
            let draft = BindingDraft(
                name: "get \(name)",
                parameters: [],
                result: type,
                effects: .init(isAsync: true, isThrowing: false),
                documentation: nil,
                sourceLocation: nil
            )
            var result = Self()
            result.members.append(
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
                            isReadOnly: true,
                            sourceLocation: sourceLocation
                        )
                    ),
                    materialize: { _, rootSource in
                        let getter = RuntimeLocalFunctionDefinition(draft: draft) {
                            runtime, _, receiver, _ in
                            let rootIdentifier = try runtime.retainRuntimeRootForOperation(
                                from: rootSource,
                                receiver: receiver
                            )
                            return .asynchronous { runtime in
                                defer { runtime.releaseRuntimeRoot(rootIdentifier) }
                                do {
                                    let root = try runtime.runtimeRoot(
                                        rootIdentifier,
                                        as: Root.self
                                    )
                                    let value = await get(runtime, root)
                                    return .success(
                                        BindingResult { engine in
                                            try engine.encode(
                                                value,
                                                maximumNestingDepth:
                                                    JavaScriptEncoder.defaultMaximumNestingDepth
                                            )
                                        }
                                    )
                                } catch {
                                    return .failure(error)
                                }
                            }
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: documentation,
                            sourceLocation: sourceLocation,
                            validationMessage: nil,
                            storage: .runtimeProperty(
                                type: type,
                                getter: getter,
                                setter: nil
                            )
                        )
                    }
                )
            )
            return result
        }

        private static func makeSynchronousProperty<Value: Codable & Sendable>(
            _ name: String,
            documentation: TypeScriptDocumentation?,
            sourceLocation: TypeScriptSourceLocation?,
            get: @escaping @Sendable (Root) -> Value,
            set: (@Sendable (Root, Value) -> Void)?
        ) -> Self {
            let type = bindingTypeShape(for: Value.self)
            let getterDraft = BindingDraft(
                name: "get \(name)",
                parameters: [],
                result: type,
                effects: .init(isAsync: false, isThrowing: false),
                documentation: nil,
                sourceLocation: nil
            )
            let setterDraft = BindingDraft(
                name: "set \(name)",
                parameters: [BindingParameterDescription(name: "value", type: type)],
                result: .void,
                effects: .init(isAsync: false, isThrowing: false),
                documentation: nil,
                sourceLocation: nil
            )
            var result = Self()
            result.members.append(
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
                            isReadOnly: set == nil,
                            sourceLocation: sourceLocation
                        )
                    ),
                    materialize: { _, rootSource in
                        let getterDefinition = RuntimeLocalFunctionDefinition(
                            draft: getterDraft
                        ) { runtime, engine, receiver, _ in
                            let root = try runtime.runtimeRoot(
                                from: rootSource,
                                receiver: receiver,
                                as: Root.self
                            )
                            return .synchronous(
                                try engine.encode(
                                    get(root),
                                    maximumNestingDepth:
                                        JavaScriptEncoder.defaultMaximumNestingDepth
                                )
                            )
                        }
                        let setterDefinition = set.map { setter in
                            RuntimeLocalFunctionDefinition(draft: setterDraft) {
                                runtime, engine, receiver, arguments in
                                let root = try runtime.runtimeRoot(
                                    from: rootSource,
                                    receiver: receiver,
                                    as: Root.self
                                )
                                let decoder = BindingArgumentDecoder(
                                    engine: engine,
                                    arguments: arguments
                                )
                                setter(root, try decoder.next(Value.self))
                                return .synchronous(
                                    ManagedQuickJSValue(
                                        quickJSUndefined(),
                                        in: engine.context
                                    )
                                )
                            }
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: documentation,
                            sourceLocation: sourceLocation,
                            validationMessage: nil,
                            storage: .runtimeProperty(
                                type: type,
                                getter: getterDefinition,
                                setter: setterDefinition
                            )
                        )
                    }
                )
            )
            return result
        }

        private static func makeReadOnlySynchronousProperty<
            Value: Encodable & Sendable
        >(
            _ name: String,
            documentation: TypeScriptDocumentation?,
            sourceLocation: TypeScriptSourceLocation?,
            get: @escaping @Sendable (Root) -> Value
        ) -> Self {
            let type = bindingTypeShape(for: Value.self)
            let getterDraft = BindingDraft(
                name: "get \(name)",
                parameters: [],
                result: type,
                effects: .init(isAsync: false, isThrowing: false),
                documentation: nil,
                sourceLocation: nil
            )
            var result = Self()
            result.members.append(
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
                            isReadOnly: true,
                            sourceLocation: sourceLocation
                        )
                    ),
                    materialize: { _, rootSource in
                        let getterDefinition = RuntimeLocalFunctionDefinition(
                            draft: getterDraft
                        ) { runtime, engine, receiver, _ in
                            let root = try runtime.runtimeRoot(
                                from: rootSource,
                                receiver: receiver,
                                as: Root.self
                            )
                            return .synchronous(
                                try engine.encode(
                                    get(root),
                                    maximumNestingDepth:
                                        JavaScriptEncoder.defaultMaximumNestingDepth
                                )
                            )
                        }
                        return JavaScriptExportMemberDefinition(
                            name: name,
                            documentation: documentation,
                            sourceLocation: sourceLocation,
                            validationMessage: nil,
                            storage: .runtimeProperty(
                                type: type,
                                getter: getterDefinition,
                                setter: nil
                            )
                        )
                    }
                )
            )
            return result
        }

        /// Declares a snapshot value produced while isolated to the runtime actor.
        internal static func value<Value: Encodable & Sendable>(
            as name: String,
            documentation: TypeScriptDocumentation? = nil,
            runtimeIsolated produce: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root
            ) async throws -> Value
        ) -> Self {
            let type = bindingTypeShape(for: Value.self)
            var result = Self()
            result.members.append(
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
                    materialize: { runtime, rootSource in
                        let root = try runtime.runtimeRoot(
                            from: rootSource,
                            receiver: nil,
                            as: Root.self
                        )
                        let value = try await produce(runtime, root)
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
            return result
        }

        /// Declares an actor-confined asynchronous typed function.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            runtimeIsolated body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeRuntimeIsolatedAsynchronousFunction(
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

        /// Declares an actor-confined asynchronous throwing typed function.
        internal static func function<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            runtimeIsolated body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async throws -> Result
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Encodable & Sendable {
            makeRuntimeIsolatedAsynchronousFunction(
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

        /// Declares an actor-confined asynchronous function returning `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            runtimeIsolated body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeRuntimeIsolatedAsynchronousFunction(
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

        /// Declares an actor-confined asynchronous throwing function returning `undefined`.
        internal static func function<each Argument>(
            _ name: String,
            options: JavaScriptFunctionOptions = .init(),
            runtimeIsolated body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async throws -> Void
        ) -> Self where repeat each Argument: Decodable & Sendable {
            makeRuntimeIsolatedAsynchronousFunction(
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

        private static func makeSynchronousFunction<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions,
            resultShape: BindingTypeShape,
            isThrowing: Bool,
            body: @escaping @Sendable (Root, repeat each Argument) throws -> Result,
            encode: @escaping @Sendable (
                QuickJSEngine,
                Result
            ) throws -> ManagedQuickJSValue
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Sendable {
            var result = Self()
            result.appendSynchronousFunction(
                name,
                options: options,
                resultShape: resultShape,
                isThrowing: isThrowing,
                body: body,
                encode: encode
            )
            return result
        }

        private static func makeAsynchronousFunction<each Argument, Result>(
            _ name: String,
            options: JavaScriptFunctionOptions,
            resultShape: BindingTypeShape,
            isThrowing: Bool,
            body: @escaping @Sendable (Root, repeat each Argument) async throws -> Result,
            encode: @escaping @Sendable (Result) -> BindingResult
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Root: Sendable,
                        Result: Sendable {
            var result = Self()
            result.appendAsynchronousFunction(
                name,
                options: options,
                resultShape: resultShape,
                isThrowing: isThrowing,
                body: body,
                encode: encode
            )
            return result
        }

        private static func makeRuntimeIsolatedAsynchronousFunction<
            each Argument,
            Result
        >(
            _ name: String,
            options: JavaScriptFunctionOptions,
            resultShape: BindingTypeShape,
            isThrowing: Bool,
            body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async throws -> Result,
            encode: @escaping @Sendable (Result) -> BindingResult
        ) -> Self where repeat each Argument: Decodable & Sendable,
                        Result: Sendable {
            var result = Self()
            result.appendRuntimeIsolatedAsynchronousFunction(
                name,
                options: options,
                resultShape: resultShape,
                isThrowing: isThrowing,
                body: body,
                encode: encode
            )
            return result
        }

        internal static func merging(_ components: [Self]) -> Self {
            var result = Self()
            for component in components {
                result.members.append(contentsOf: component.members)
            }
            return result
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
            appendFunction(draft) { rootSource in
                RuntimeLocalFunctionDefinition(draft: draft.value) {
                    runtime, engine, receiver, arguments in
                    let root = try runtime.runtimeRoot(
                        from: rootSource,
                        receiver: receiver,
                        as: Root.self
                    )
                    let decoder = BindingArgumentDecoder(
                        engine: engine,
                        arguments: arguments
                    )
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
                Root: Sendable,
                Result: Sendable {
            let draft = makeDraft(
                name: name,
                options: options,
                parameterShapes: bindingParameterShapes(repeat (each Argument).self),
                resultShape: resultShape,
                isAsync: true,
                isThrowing: isThrowing
            )
            appendFunction(draft) { rootSource in
                RuntimeLocalFunctionDefinition(draft: draft.value) {
                    runtime, engine, receiver, arguments in
                    let decoder = BindingArgumentDecoder(
                        engine: engine,
                        arguments: arguments
                    )
                    let decoded: (repeat each Argument) =
                        (repeat try decoder.next((each Argument).self))
                    let rootIdentifier = try runtime.retainRuntimeRootForOperation(
                        from: rootSource,
                        receiver: receiver
                    )
                    return .asynchronous { runtime in
                        defer { runtime.releaseRuntimeRoot(rootIdentifier) }
                        do {
                            let root = try runtime.runtimeRoot(
                                rootIdentifier,
                                as: Root.self
                            )
                            return .success(
                                encode(try await body(root, repeat each decoded))
                            )
                        } catch {
                            return .failure(error)
                        }
                    }
                }
            }
        }

        private mutating func appendRuntimeIsolatedAsynchronousFunction<
            each Argument,
            Result
        >(
            _ name: String,
            options: JavaScriptFunctionOptions,
            resultShape: BindingTypeShape,
            isThrowing: Bool,
            body: @escaping @Sendable (
                isolated JavaScriptRuntime,
                Root,
                repeat each Argument
            ) async throws -> Result,
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
            appendFunction(draft) { rootSource in
                RuntimeLocalFunctionDefinition(draft: draft.value) {
                    runtime, engine, receiver, arguments in
                    let decoder = BindingArgumentDecoder(
                        engine: engine,
                        arguments: arguments
                    )
                    let decoded: (repeat each Argument) =
                        (repeat try decoder.next((each Argument).self))
                    let rootIdentifier = try runtime.retainRuntimeRootForOperation(
                        from: rootSource,
                        receiver: receiver
                    )
                    return .asynchronous { runtime in
                        defer { runtime.releaseRuntimeRoot(rootIdentifier) }
                        do {
                            let root = try runtime.runtimeRoot(
                                rootIdentifier,
                                as: Root.self
                            )
                            return .success(
                                encode(
                                    try await body(
                                        runtime,
                                        root,
                                        repeat each decoded
                                    )
                                )
                            )
                        } catch {
                            return .failure(error)
                        }
                    }
                }
            }
        }

        private mutating func appendFunction(
            _ draft: InstanceBindingDraft,
            materialize: @escaping @Sendable (
                RuntimeRootSource
            ) -> RuntimeLocalFunctionDefinition
        ) {
            members.append(
                RuntimeInstanceMemberDefinition(
                    name: draft.value.name,
                    validationMessage: draft.validationMessage,
                    environmentDescription: .function(
                        EnvironmentFunctionDescription(draft.value)
                    ),
                    materialize: { _, rootSource in
                        JavaScriptExportMemberDefinition(
                            name: draft.value.name,
                            documentation: nil,
                            validationMessage: nil,
                            storage: .runtimeFunction(materialize(rootSource))
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
            return InstanceBindingDraft(
                value: draft,
                validationMessage: parameters.message
                    ?? BindingValidation.nameMessage(name, role: "Export member names")
                    ?? options.parameterSourceLocations.keys.sorted().first(where: {
                        !parameters.names.contains($0)
                    }).map {
                        "A source location was provided for unknown parameter '\($0)'."
                    }
                    ?? TypeScriptDocumentationValidation.message(
                        for: options.documentation,
                        parameterNames: parameters.names
                    )
            )
        }
    }
}

private struct InstanceBindingDraft: Sendable {
    let value: BindingDraft
    let validationMessage: String?
}

internal struct RuntimeInstanceMemberDefinition<Root: AnyObject>: Sendable {
    internal let name: String
    internal let validationMessage: String?
    internal let environmentDescription: EnvironmentMemberDescription
    internal let materialize: @Sendable (
        isolated JavaScriptRuntime,
        RuntimeRootSource
    ) async throws -> JavaScriptExportMemberDefinition

    internal var environmentGlobalDescription: EnvironmentGlobalDescription {
        switch environmentDescription {
        case let .function(function):
            return .function(function)
        case let .type(type):
            return .type(type)
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

internal enum RuntimeRootSource: Sendable, Hashable {
    case fixed(UInt64)
    case receiver(hostTypeIdentifier: Int32)
}
