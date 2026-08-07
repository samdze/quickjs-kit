/// Supplies deterministic TypeScript metadata for a Swift model.
///
/// QuickJSKit discovers this conformance when the model appears in a typed
/// binding or exported value. Future macros can synthesize the same metadata
/// without creating a separate declaration system.
public protocol TypeScriptSchemaProviding {
    /// The TypeScript schema representing this Swift type.
    static var typeScriptSchema: TypeScriptSchema { get }

    /// Schemas referenced by this model.
    ///
    /// Macro-generated conformances use this detached graph to describe
    /// recursive and mutually recursive models without global registration.
    static var typeScriptSchemaDependencies: [any TypeScriptSchemaProviding.Type] { get }
}

extension TypeScriptSchemaProviding {
    /// No additional schemas are required by default.
    public static var typeScriptSchemaDependencies: [any TypeScriptSchemaProviding.Type] {
        []
    }
}

/// The TypeScript declaration location owned by a schema or definition.
///
/// Scopes describe compile-time TypeScript names only. They do not create
/// JavaScript objects or alter QuickJS module loading. A global or namespaced
/// type is available without an import. A module type is exported from the
/// matching ambient module and can be consumed with `import type`.
public enum TypeScriptDeclarationScope:
    Sendable,
    Hashable,
    ExpressibleByStringLiteral
{
    /// An ambient type declared at the top level.
    case global

    /// A type inside a namespace such as `Acme.Models`.
    case namespace(String)

    /// A type exported by the JavaScript module with this specifier.
    case module(String)

    /// Creates a named namespace from a string literal.
    public init(stringLiteral value: String) {
        self = .namespace(value)
    }
}

/// A complete TypeScript representation for one Swift type.
///
/// A schema has one primary type and may carry several related definitions.
/// Keeping references and definitions separate permits recursive and mutually
/// recursive interfaces without recursive Swift storage.
public struct TypeScriptSchema: Sendable, Hashable {
    /// The TypeScript type used at binding call sites.
    public let type: TypeScriptType

    /// Named declarations required by ``type``.
    public let definitions: [TypeScriptDefinition]

    /// The declaration scope inherited by this schema's definitions.
    ///
    /// A `nil` value inherits the enclosing ``Globals`` or ``SwiftModule``
    /// location. For standalone schemas it uses
    /// ``TypeScriptDeclarationOptions/defaultTypeScope``.
    public let scope: TypeScriptDeclarationScope?

    /// The logical Swift declaration location, when known.
    public let sourceLocation: TypeScriptSourceLocation?

    /// Creates a schema from a primary type and its named declarations.
    public init(
        type: TypeScriptType,
        definitions: [TypeScriptDefinition],
        scope: TypeScriptDeclarationScope? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil
    ) {
        self.type = type
        self.definitions = definitions
        self.scope = scope
        self.sourceLocation = sourceLocation
    }

    /// Creates a schema containing one interface declaration.
    public static func interface(
        _ name: String,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        properties: [TypeScriptProperty]
    ) -> Self {
        Self(
            type: .named(name),
            definitions: [
                .interface(
                    name: name,
                    documentation: documentation,
                    sourceLocation: sourceLocation,
                    properties: properties
                ),
            ],
            scope: scope,
            sourceLocation: sourceLocation
        )
    }

    /// Creates a schema containing one named type alias.
    public static func alias(
        _ name: String,
        to type: TypeScriptType,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil
    ) -> Self {
        Self(
            type: .named(name),
            definitions: [
                .alias(
                    name: name,
                    documentation: documentation,
                    sourceLocation: sourceLocation,
                    type: type
                ),
            ],
            scope: scope,
            sourceLocation: sourceLocation
        )
    }

    /// Creates a schema containing an enum-style literal union.
    ///
    /// The declaration is a type alias rather than a TypeScript runtime enum,
    /// matching Codable values that do not export a JavaScript enum object.
    public static func enumeration(
        _ name: String,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        cases: [TypeScriptEnumCase]
    ) -> Self {
        Self(
            type: .named(name),
            definitions: [
                .enumeration(
                    name: name,
                    documentation: documentation,
                    sourceLocation: sourceLocation,
                    cases: cases
                ),
            ],
            scope: scope,
            sourceLocation: sourceLocation
        )
    }
}

/// A TypeScript type expression supported by QuickJSKit schemas.
public indirect enum TypeScriptType: Sendable, Hashable {
    /// TypeScript `boolean`.
    case boolean
    /// TypeScript `string`.
    case string
    /// TypeScript `number`.
    case number
    /// TypeScript `bigint`.
    case bigint
    /// TypeScript `null`.
    case null
    /// TypeScript `undefined`.
    case undefined
    /// TypeScript `unknown`.
    case unknown
    /// The standard JavaScript `Date` object.
    case date
    /// The standard JavaScript `Uint8Array` object.
    case uint8Array
    /// A named type declared by a schema definition.
    ///
    /// A `nil` scope resolves relative to the containing schema or definition.
    case named(String, scope: TypeScriptDeclarationScope? = nil)
    /// A mutable JavaScript array.
    case array(TypeScriptType)
    /// A string-keyed JavaScript object.
    case record(TypeScriptType)
    /// A union of one or more TypeScript types.
    case union([TypeScriptType])
    /// A string or integer literal type.
    case literal(TypeScriptLiteral)
}

/// A named TypeScript declaration carried by a schema.
public struct TypeScriptDefinition: Sendable, Hashable {
    /// The structural form of a named declaration.
    public enum Kind: Sendable, Hashable {
        /// A structural interface.
        case interface(properties: [TypeScriptProperty])

        /// A named type alias.
        case alias(TypeScriptType)

        /// A named string or integer literal union.
        case enumeration(cases: [TypeScriptEnumCase])
    }

    /// The declared TypeScript name.
    public let name: String

    /// An optional scope overriding the containing schema's scope.
    public let scope: TypeScriptDeclarationScope?

    /// Structured documentation rendered before the declaration.
    public let documentation: TypeScriptDocumentation?

    /// The logical Swift declaration location, when known.
    public let sourceLocation: TypeScriptSourceLocation?

    /// The declaration's structural form.
    public let kind: Kind

    /// Creates a named declaration.
    public init(
        name: String,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        kind: Kind
    ) {
        self.name = name
        self.scope = scope
        self.documentation = documentation
        self.sourceLocation = sourceLocation
        self.kind = kind
    }

    /// Creates an interface declaration.
    public static func interface(
        name: String,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        properties: [TypeScriptProperty]
    ) -> Self {
        Self(
            name: name,
            scope: scope,
            documentation: documentation,
            sourceLocation: sourceLocation,
            kind: .interface(properties: properties)
        )
    }

    /// Creates a type-alias declaration.
    public static func alias(
        name: String,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        type: TypeScriptType
    ) -> Self {
        Self(
            name: name,
            scope: scope,
            documentation: documentation,
            sourceLocation: sourceLocation,
            kind: .alias(type)
        )
    }

    /// Creates an enum-style literal-union declaration.
    public static func enumeration(
        name: String,
        scope: TypeScriptDeclarationScope? = nil,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil,
        cases: [TypeScriptEnumCase]
    ) -> Self {
        Self(
            name: name,
            scope: scope,
            documentation: documentation,
            sourceLocation: sourceLocation,
            kind: .enumeration(cases: cases)
        )
    }
}

/// A property in a TypeScript interface.
public struct TypeScriptProperty: Sendable, Hashable {
    /// The JavaScript property name.
    public let name: String

    /// The property's TypeScript type.
    public let type: TypeScriptType

    /// Whether callers may omit this property.
    public let isOptional: Bool

    /// Whether TypeScript should prevent assignment to this property.
    public let isReadonly: Bool

    /// Structured documentation rendered as TSDoc.
    public let documentation: TypeScriptDocumentation?

    /// The documented canonical default value, rendered with `@defaultValue`.
    public let defaultValue: String?

    /// The logical Swift property location, when known.
    public let sourceLocation: TypeScriptSourceLocation?

    /// Creates an interface property.
    public init(
        _ name: String,
        type: TypeScriptType,
        isOptional: Bool = false,
        isReadonly: Bool = false,
        documentation: TypeScriptDocumentation? = nil,
        defaultValue: String? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil
    ) {
        self.name = name
        self.type = type
        self.isOptional = isOptional
        self.isReadonly = isReadonly
        self.documentation = documentation
        self.defaultValue = defaultValue
        self.sourceLocation = sourceLocation
    }
}

/// One documented value in an enum-style literal union.
public struct TypeScriptEnumCase: Sendable, Hashable {
    /// The Swift-facing case name used in generated documentation.
    public let name: String

    /// The encoded JavaScript literal.
    public let value: TypeScriptLiteral

    /// Structured documentation summarized in the literal union's TSDoc.
    public let documentation: TypeScriptDocumentation?

    /// The logical Swift enum-case location, when known.
    public let sourceLocation: TypeScriptSourceLocation?

    /// Creates a literal-union case.
    public init(
        _ name: String,
        value: TypeScriptLiteral,
        documentation: TypeScriptDocumentation? = nil,
        sourceLocation: TypeScriptSourceLocation? = nil
    ) {
        self.name = name
        self.value = value
        self.documentation = documentation
        self.sourceLocation = sourceLocation
    }
}

/// A literal value supported in generated TypeScript types.
public enum TypeScriptLiteral: Sendable, Hashable {
    /// A string literal.
    case string(String)
    /// A signed integer literal.
    case integer(Int64)
}
