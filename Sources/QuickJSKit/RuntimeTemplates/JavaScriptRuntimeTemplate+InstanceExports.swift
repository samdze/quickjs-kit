extension JavaScriptRuntimeTemplate {
    /// Composes members backed by one per-runtime Swift root.
    @resultBuilder
    public enum InstanceExportBuilder<Root: AnyObject & Sendable> {
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
    public struct InstanceExport<Root: AnyObject & Sendable>: Sendable {
        internal var members: [RuntimeInstanceMemberDefinition<Root>] = []

        internal init() {}

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
        ) -> Self where repeat each Argument: Decodable & Sendable {
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
        ) -> Self where repeat each Argument: Decodable & Sendable {
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
            return result
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
            appendFunction(draft) { root in
                BindingDefinition(draft: draft.value) { engine, arguments in
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
                    let decoder = BindingArgumentDecoder(
                        engine: engine,
                        arguments: arguments
                    )
                    let decoded: (repeat each Argument) =
                        (repeat try decoder.next((each Argument).self))
                    return .asynchronous {
                        do {
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
