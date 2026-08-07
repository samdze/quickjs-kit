/// A Swift value type that can be published as a JavaScript constructor or
/// enum validator.
///
/// Conformance describes a detached value contract. It does not publish a
/// global or module export until the type is included with ``JavaScriptType``
/// or registered on a ``JavaScriptRuntime``.
public protocol JavaScriptValueTypeProviding:
    Encodable,
    Decodable,
    Sendable,
    TypeScriptSchemaProviding
{
    /// The reusable JavaScript representation of this value type.
    static var javaScriptValueTypeDefinition:
        JavaScriptValueTypeDefinition<Self> { get }
}

/// A Swift reference type that can be published as a live JavaScript host
/// type.
///
/// The runtime, rather than this detached definition, owns every constructed
/// class or actor instance.
public protocol JavaScriptHostTypeProviding: JavaScriptExportProviding {
    /// The detached JavaScript name, available without initializing bindings.
    static var javaScriptHostTypeName: String { get }

    /// The reusable JavaScript representation of this host type.
    static var javaScriptHostTypeDefinition:
        JavaScriptHostTypeDefinition<Self> { get }
}

/// A detached description of a Codable JavaScript value type.
public struct JavaScriptValueTypeDefinition<Value>: Sendable
where Value: Encodable & Decodable & Sendable {
    /// The runtime shape published for the Swift value.
    public enum Kind: Sendable, Hashable {
        /// A validating constructor that returns a canonical JavaScript object.
        case structure

        /// A callable validator with readonly raw-value case properties.
        case enumeration(cases: [TypeScriptEnumCase])
    }

    /// The exported JavaScript and TypeScript name.
    public let name: String

    /// Structured documentation for the type and runtime value.
    public let documentation: TypeScriptDocumentation?

    /// The logical Swift declaration location.
    public let sourceLocation: TypeScriptSourceLocation?

    /// The runtime representation of the value.
    public let kind: Kind

    /// Creates a detached value-type definition.
    public init(
        name: String,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        kind: Kind
    ) {
        self.name = name
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.kind = kind
    }
}

/// A detached description of a live Swift class or actor type.
///
/// Initializers and static members are added in the same definition so macros,
/// templates, immediate registration, and TypeScript tooling consume one
/// source of truth.
public struct JavaScriptHostTypeDefinition<Root: AnyObject>: Sendable {
    /// The exported JavaScript and TypeScript name.
    public let name: String

    /// Structured documentation for the host type.
    public let documentation: TypeScriptDocumentation?

    /// The logical Swift declaration location.
    public let sourceLocation: TypeScriptSourceLocation?

    /// The reusable instance-member definition.
    public let instanceMembers: JavaScriptRuntimeTemplate.InstanceExport<Root>

    internal let constructors: [JavaScriptHostConstructorDefinition<Root>]
    internal let staticMembers: [JavaScriptExportMemberDefinition]

    /// Creates a detached host-type definition.
    public init(
        name: String,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        instanceMembers: JavaScriptRuntimeTemplate.InstanceExport<Root>,
        constructors: [JavaScriptHostConstructor<Root>] = []
    ) {
        self.name = name
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.instanceMembers = instanceMembers
        self.constructors = constructors.map(\.definition)
        self.staticMembers = []
    }

    /// Creates a detached host-type definition with static members.
    public init(
        name: String,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        instanceMembers: JavaScriptRuntimeTemplate.InstanceExport<Root>,
        constructors: [JavaScriptHostConstructor<Root>] = [],
        @JavaScriptRuntimeTemplate.ExportBuilder
        staticMembers: @Sendable () -> JavaScriptRuntimeTemplate.Export
    ) {
        self.name = name
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.instanceMembers = instanceMembers
        self.constructors = constructors.map(\.definition)
        self.staticMembers = staticMembers().members
    }
}

internal enum AnyJavaScriptTypeDefinition: Sendable {
    case value(AnyJavaScriptValueTypeDefinition)
    case host(AnyJavaScriptHostTypeDefinition)

    internal var name: String {
        switch self {
        case let .value(definition): definition.name
        case let .host(definition): definition.name
        }
    }

    internal var swiftIdentity: ObjectIdentifier {
        switch self {
        case let .value(definition): definition.swiftIdentity
        case let .host(definition): definition.swiftIdentity
        }
    }

    internal var environmentDescription: EnvironmentTypeDescription {
        switch self {
        case let .value(definition): definition.environmentDescription
        case let .host(definition): definition.environmentDescription
        }
    }

    internal func environmentDescription(
        at location: JavaScriptTypeLocation
    ) -> EnvironmentTypeDescription {
        let description = environmentDescription
        guard let schema = description.schema else {
            return description
        }
        let scope: TypeScriptDeclarationScope
        switch location {
        case .global: scope = .global
        case let .module(specifier): scope = .module(specifier)
        }
        let locatedSchema: TypeScriptSchema
        if schema.scope == nil {
            locatedSchema = TypeScriptSchema(
                type: schema.type,
                definitions: schema.definitions,
                scope: scope,
                sourceLocation: schema.sourceLocation
            )
        } else {
            locatedSchema = schema
        }
        var result = description
        result.schema = locatedSchema
        return result
    }
}

internal struct AnyJavaScriptValueTypeDefinition: Sendable {
    internal let swiftIdentity: ObjectIdentifier
    internal let name: String
    internal let schema: TypeScriptSchema
    internal let documentation: TypeScriptDocumentation?
    internal let sourceLocation: TypeScriptSourceLocation?
    internal let kind: JavaScriptValueTypeRuntimeKind
    internal let construct: @Sendable (
        QuickJSEngine,
        ManagedQuickJSValue
    ) throws -> ManagedQuickJSValue

    internal var environmentDescription: EnvironmentTypeDescription {
        let environmentKind: EnvironmentTypeDescription.Kind
        switch kind {
        case .structure:
            environmentKind = .structure
        case let .enumeration(cases):
            environmentKind = .enumeration(cases: cases)
        }
        return EnvironmentTypeDescription(
            name: name,
            schema: schema,
            documentation: documentation,
            sourceLocation: sourceLocation,
            kind: environmentKind
        )
    }
}

internal enum JavaScriptValueTypeRuntimeKind: Sendable, Hashable {
    case structure
    case enumeration(cases: [TypeScriptEnumCase])
}

internal struct AnyJavaScriptHostTypeDefinition: Sendable {
    internal let swiftIdentity: ObjectIdentifier
    internal let name: String
    internal let documentation: TypeScriptDocumentation?
    internal let sourceLocation: TypeScriptSourceLocation?
    internal let environmentDescription: EnvironmentTypeDescription
    internal let constructors: [AnyJavaScriptHostConstructor]
    internal let staticMembers: [JavaScriptExportMemberDefinition]
    internal let materializeInstanceMembers: @Sendable (
        isolated JavaScriptRuntime,
        Int32
    ) async throws -> [JavaScriptExportMemberDefinition]
}

internal struct AnyJavaScriptHostConstructor: Sendable {
    internal let draft: BindingDraft
    internal let argumentProbes: [JavaScriptHostConstructorArgumentProbe]
    internal let invocation: AnyJavaScriptHostConstructorInvocation

    internal func accepts(
        _ arguments: [ManagedQuickJSValue],
        in engine: QuickJSEngine
    ) -> Bool {
        guard arguments.count == argumentProbes.count else { return false }
        return zip(arguments, argumentProbes).allSatisfy { argument, probe in
            probe.accepts(argument, in: engine)
        }
    }
}

internal enum AnyJavaScriptHostConstructorInvocation: Sendable {
    case synchronous(
        @Sendable (
            isolated JavaScriptRuntime,
            QuickJSEngine,
            [ManagedQuickJSValue]
        ) throws -> UInt64
    )
    case asynchronous(
        @Sendable (
            QuickJSEngine,
            [ManagedQuickJSValue]
        ) throws -> @Sendable () async throws -> any AnyObject & Sendable
    )
}

internal enum JavaScriptTypeLocation: Sendable, Hashable {
    case global
    case module(String)
}

internal extension JavaScriptTypeLocation {
    func validate(
        scope: TypeScriptDeclarationScope?,
        typeName: String
    ) throws {
        guard let scope else { return }
        let matches: Bool = switch (self, scope) {
        case (.global, .global): true
        case let (.module(location), .module(scope)): location == scope
        default: false
        }
        guard matches else {
            throw JavaScriptError(
                kind: .conversion,
                message: "JavaScript type '\(typeName)' has a TypeScript scope that does not match its runtime location."
            )
        }
    }
}

internal extension JavaScriptValueTypeDefinition {
    func erase(schema: TypeScriptSchema) -> AnyJavaScriptTypeDefinition {
        let runtimeKind: JavaScriptValueTypeRuntimeKind
        switch kind {
        case .structure:
            runtimeKind = .structure
        case let .enumeration(cases):
            runtimeKind = .enumeration(cases: cases)
        }
        return .value(
            AnyJavaScriptValueTypeDefinition(
                swiftIdentity: ObjectIdentifier(Value.self),
                name: name,
                schema: schema,
                documentation: documentation,
                sourceLocation: sourceLocation,
                kind: runtimeKind,
                construct: { engine, input in
                    let decoded = try engine.decode(
                        Value.self,
                        from: input,
                        maximumNestingDepth: JavaScriptDecoder.defaultMaximumNestingDepth
                    )
                    return try engine.encode(
                        decoded,
                        maximumNestingDepth: JavaScriptEncoder.defaultMaximumNestingDepth
                    )
                }
            )
        )
    }
}

/// One synchronous initializer exported by a live Swift host type.
///
/// Async initializer factories use the same native Promise machinery and are
/// introduced by the host-type runtime implementation.
public struct JavaScriptHostConstructor<Root: AnyObject>: Sendable {
    internal let definition: JavaScriptHostConstructorDefinition<Root>

    /// Creates a nonthrowing synchronous constructor.
    public init<each Argument>(
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) -> Root
    ) where repeat each Argument: Decodable & Sendable {
        definition = JavaScriptHostConstructorDefinition(
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            argumentProbes: hostConstructorArgumentProbes(
                repeat (each Argument).self
            ),
            isAsync: false,
            isThrowing: false,
            invocation: .synchronous { engine, arguments in
                let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
                let decoded: (repeat each Argument) =
                    (repeat try decoder.next((each Argument).self))
                return body(repeat each decoded)
            }
        )
    }

    /// Creates a throwing synchronous constructor.
    public init<each Argument>(
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) throws -> Root
    ) where repeat each Argument: Decodable & Sendable {
        definition = JavaScriptHostConstructorDefinition(
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            argumentProbes: hostConstructorArgumentProbes(
                repeat (each Argument).self
            ),
            isAsync: false,
            isThrowing: true,
            invocation: .synchronous { engine, arguments in
                let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
                let decoded: (repeat each Argument) =
                    (repeat try decoder.next((each Argument).self))
                return try body(repeat each decoded)
            }
        )
    }

    /// Creates a nonthrowing asynchronous factory exposed as `Type.create`.
    public init<each Argument>(
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async -> Root
    ) where repeat each Argument: Decodable & Sendable, Root: Sendable {
        definition = JavaScriptHostConstructorDefinition(
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            argumentProbes: hostConstructorArgumentProbes(
                repeat (each Argument).self
            ),
            isAsync: true,
            isThrowing: false,
            invocation: .asynchronous { engine, arguments in
                let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
                let decoded: (repeat each Argument) =
                    (repeat try decoder.next((each Argument).self))
                return { await body(repeat each decoded) as any AnyObject & Sendable }
            }
        )
    }

    /// Creates a throwing asynchronous factory exposed as `Type.create`.
    public init<each Argument>(
        options: JavaScriptFunctionOptions = .init(),
        _ body: @escaping @Sendable (repeat each Argument) async throws -> Root
    ) where repeat each Argument: Decodable & Sendable, Root: Sendable {
        definition = JavaScriptHostConstructorDefinition(
            options: options,
            parameterShapes: bindingParameterShapes(repeat (each Argument).self),
            argumentProbes: hostConstructorArgumentProbes(
                repeat (each Argument).self
            ),
            isAsync: true,
            isThrowing: true,
            invocation: .asynchronous { engine, arguments in
                let decoder = BindingArgumentDecoder(engine: engine, arguments: arguments)
                let decoded: (repeat each Argument) =
                    (repeat try decoder.next((each Argument).self))
                return { try await body(repeat each decoded) as any AnyObject & Sendable }
            }
        )
    }

}

internal struct JavaScriptHostConstructorDefinition<Root: AnyObject>: Sendable {
    internal let options: JavaScriptFunctionOptions
    internal let parameterShapes: [BindingTypeShape]
    internal let argumentProbes: [JavaScriptHostConstructorArgumentProbe]
    internal let isAsync: Bool
    internal let isThrowing: Bool
    internal let invocation: JavaScriptHostConstructorInvocation<Root>

    internal var draft: BindingDraft {
        let parameters = BindingValidation.parameterNames(
            options.parameterNames,
            arity: parameterShapes.count
        )
        return BindingDraft(
            name: "constructor",
            parameters: zip(parameters.names, parameterShapes).map {
                BindingParameterDescription(
                    name: $0,
                    type: $1,
                    sourceLocation: options.parameterSourceLocations[$0]
                )
            },
            result: .unknown,
            effects: .init(isAsync: isAsync, isThrowing: isThrowing),
            documentation: options.documentation,
            sourceLocation: options.sourceLocation
        )
    }
}

internal enum JavaScriptHostConstructorInvocation<Root: AnyObject>: Sendable {
    case synchronous(
        @Sendable (QuickJSEngine, [ManagedQuickJSValue]) throws -> Root
    )
    case asynchronous(
        @Sendable (
            QuickJSEngine,
            [ManagedQuickJSValue]
        ) throws -> @Sendable () async throws -> any AnyObject & Sendable
    )
}

internal extension JavaScriptHostTypeDefinition {
    func erase() -> AnyJavaScriptHostTypeDefinition {
        let environment = EnvironmentTypeDescription(
            name: name,
            schema: nil,
            documentation: documentation,
            sourceLocation: sourceLocation,
            kind: .host(
                constructors: constructors.map {
                    EnvironmentFunctionDescription($0.draft)
                },
                staticMembers: staticMembers.map(\.environmentDescription),
                instanceMembers: instanceMembers.members.map(\.environmentDescription)
            )
        )
        return AnyJavaScriptHostTypeDefinition(
            swiftIdentity: ObjectIdentifier(Root.self),
            name: name,
            documentation: documentation,
            sourceLocation: sourceLocation,
            environmentDescription: environment,
            constructors: constructors.map { constructor in
                let invocation: AnyJavaScriptHostConstructorInvocation
                switch constructor.invocation {
                case let .synchronous(body):
                    invocation = .synchronous { runtime, engine, arguments in
                        let root = try body(engine, arguments)
                        return try runtime.retainHostObject(root)
                    }
                case let .asynchronous(body):
                    invocation = .asynchronous { engine, arguments in
                        let operation = try body(engine, arguments)
                        return { try await operation() }
                    }
                }
                return AnyJavaScriptHostConstructor(
                    draft: constructor.draft,
                    argumentProbes: constructor.argumentProbes,
                    invocation: invocation
                )
            },
            staticMembers: staticMembers,
            materializeInstanceMembers: { runtime, typeIdentifier in
                try await instanceMembers.materialize(
                    on: runtime,
                    rootSource: .receiver(hostTypeIdentifier: typeIdentifier)
                )
            }
        )
    }
}

internal struct JavaScriptHostConstructorArgumentProbe: Sendable {
    private let operation: @Sendable (
        QuickJSEngine,
        ManagedQuickJSValue
    ) -> Bool

    internal init<Value: Decodable & Sendable>(_ type: Value.Type) {
        operation = { engine, value in
            do {
                _ = try engine.decode(
                    type,
                    from: value,
                    maximumNestingDepth:
                        JavaScriptDecoder.defaultMaximumNestingDepth
                )
                return true
            } catch {
                return false
            }
        }
    }

    internal func accepts(
        _ value: ManagedQuickJSValue,
        in engine: QuickJSEngine
    ) -> Bool {
        operation(engine, value)
    }
}

internal func hostConstructorArgumentProbes<each Argument>(
    _ types: repeat (each Argument).Type
) -> [JavaScriptHostConstructorArgumentProbe]
where repeat each Argument: Decodable & Sendable {
    var probes: [JavaScriptHostConstructorArgumentProbe] = []
    for type in repeat each types {
        probes.append(JavaScriptHostConstructorArgumentProbe(type))
    }
    return probes
}
